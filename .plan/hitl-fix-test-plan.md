# Test Plan — HITL Fix (Issue #69)

> PRs: [cerebelum#70](https://github.com/ZeaCl/cerebelum/pull/70) · [cerebelum-python#1](https://github.com/ZeaCl/cerebelum-python/pull/1)

---

## Nivel 1: Engine Unit Tests (sin DB, sin worker)

### 1.1 `WorkerServiceServer` — detección de patrones

```bash
cd cerebelum
mix test test/cerebelum/infrastructure/worker_service_server_test.exs
```

**Nuevo test a agregar** (`worker_service_server_test.exs`):

```elixir
describe "submit_result/2 — approval/sleep detection" do
  alias Cerebelum.Worker.{TaskResult, TaskStatus, Ack}

  test "detects approval from status field in result data" do
    result = %TaskResult{
      task_id: "task-1",
      execution_id: "exec-1",
      worker_id: "worker-1",
      status: :SUCCESS,
      result: %Google.Protobuf.Struct{
        fields: %{
          "status" => %Google.Protobuf.Value{kind: {:string_value, "waiting_for_approval"}},
          "approval_type" => %Google.Protobuf.Value{kind: {:string_value, "manual"}},
          "data" => %Google.Protobuf.Value{kind: {:struct_value,
            %Google.Protobuf.Struct{fields: %{
              "doc_id" => %Google.Protobuf.Value{kind: {:string_value, "123"}}
            }}
          }}
        }
      },
      completed_at: %Google.Protobuf.Timestamp{seconds: 0, nanos: 0}
    }

    response = WorkerServiceServer.submit_result(result, nil)
    assert %Ack{success: true} = response
    # Verify Log shows "Detected approval request (status field)"
  end

  test "detects sleep from status field in result data" do
    result = %TaskResult{
      task_id: "task-2",
      execution_id: "exec-2",
      worker_id: "worker-1",
      status: :SUCCESS,
      result: %Google.Protobuf.Struct{
        fields: %{
          "status" => %Google.Protobuf.Value{kind: {:string_value, "sleep"}},
          "duration_ms" => %Google.Protobuf.Value{kind: {:number_value, 5000}}
        }
      },
      completed_at: %Google.Protobuf.Timestamp{seconds: 0, nanos: 0}
    }

    response = WorkerServiceServer.submit_result(result, nil)
    assert %Ack{success: true} = response
    # Verify Log shows "Detected sleep request (status field)"
  end

  test "still detects legacy __cerebelum_approval_request__ marker" do
    result = %TaskResult{
      task_id: "task-3",
      execution_id: "exec-3",
      worker_id: "worker-1",
      status: :SUCCESS,
      result: %Google.Protobuf.Struct{
        fields: %{
          "__cerebelum_approval_request__" => %Google.Protobuf.Value{kind: {:bool_value, true}},
          "approval_type" => %Google.Protobuf.Value{kind: {:string_value, "manual"}}
        }
      },
      completed_at: %Google.Protobuf.Timestamp{seconds: 0, nanos: 0}
    }

    response = WorkerServiceServer.submit_result(result, nil)
    assert %Ack{success: true} = response
    # Verify Log shows "Detected approval request (marker)"
  end

  test "handles native APPROVAL status correctly" do
    result = %TaskResult{
      task_id: "task-4",
      execution_id: "exec-4",
      worker_id: "worker-1",
      status: :APPROVAL,
      approval_request: %Cerebelum.Worker.ApprovalRequest{
        approval_type: "manual",
        data: %Google.Protobuf.Struct{fields: %{}},
        timeout_ms: 60_000
      },
      completed_at: %Google.Protobuf.Timestamp{seconds: 0, nanos: 0}
    }

    response = WorkerServiceServer.submit_result(result, nil)
    assert %Ack{success: true} = response
  end

  test "handles native SLEEP status correctly" do
    result = %TaskResult{
      task_id: "task-5",
      execution_id: "exec-5",
      worker_id: "worker-1",
      status: :SLEEP,
      sleep_request: %Cerebelum.Worker.SleepRequest{
        duration_ms: 10_000,
        data: %Google.Protobuf.Struct{fields: %{}}
      },
      completed_at: %Google.Protobuf.Timestamp{seconds: 0, nanos: 0}
    }

    response = WorkerServiceServer.submit_result(result, nil)
    assert %Ack{success: true} = response
  end
end
```

### 1.2 `StateHandlers` — arms para `{:approval, data}` y `{:sleep, ...}`

```bash
mix test test/cerebelum/execution/engine_test.exs
mix test test/cerebelum/execution/approval_test.exs
```

**Nuevo test a agregar** (`engine_test.exs`):

```elixir
describe "executing_step — delegating workflow format" do
  defmodule DelegatingApprovalWorkflow do
    use Cerebelum.Workflow
    workflow do
      timeline do
        step1() |> step2()
      end
    end
    def step1(_ctx), do: {:approval, %{"type" => "manual", "data" => %{doc: "123"}}}
    def step2(_ctx, _), do: {:ok, :finished}
  end

  test "handles {:approval, data} format from delegating workflow" do
    {:ok, pid} = Engine.start_link(
      workflow_module: DelegatingApprovalWorkflow,
      inputs: %{}
    )

    # Wait for state transition
    Process.sleep(100)

    status = Engine.get_status(pid)
    assert status.state == :waiting_for_approval
    assert status.approval_type == :manual
    assert status.approval_data == %{"doc" => "123"}

    Engine.stop(pid)
  end

  defmodule DelegatingSleepWorkflow do
    use Cerebelum.Workflow
    workflow do
      timeline do
        step1() |> step2()
      end
    end
    def step1(_ctx), do: {:sleep, 500, %{checkpoint: true}}
    def step2(_ctx, _), do: {:ok, :awake}
  end

  test "handles {:sleep, duration, data} format from delegating workflow" do
    {:ok, pid} = Engine.start_link(
      workflow_module: DelegatingSleepWorkflow,
      inputs: %{}
    )

    Process.sleep(100)

    status = Engine.get_status(pid)
    assert status.state == :sleeping
    assert status.sleep_duration_ms == 500

    Engine.stop(pid)
  end
end
```

---

## Nivel 2: Python SDK Unit Tests

```bash
cd cerebelum-python
pip install -e ".[dev]"
pytest tests/ -v
```

**Nuevo test a agregar** (`tests/test_async_helpers.py`):

```python
import pytest
from cerebelum.dsl.workflow_markers import ApprovalMarker, SleepMarker
from cerebelum.dsl.async_helpers import wait_for_approval, sleep


class TestWaitForApproval:
    async def test_raises_approval_marker_defaults(self):
        with pytest.raises(ApprovalMarker) as exc:
            await wait_for_approval()
        assert exc.value.approval_type == "manual"
        assert exc.value.data == {}
        assert exc.value.timeout_ms is None

    async def test_raises_approval_marker_with_data(self):
        with pytest.raises(ApprovalMarker) as exc:
            await wait_for_approval(
                approval_type="review",
                data={"doc_id": "abc"},
                timeout_ms=60_000
            )
        assert exc.value.approval_type == "review"
        assert exc.value.data == {"doc_id": "abc"}
        assert exc.value.timeout_ms == 60_000


class TestSleepMarker:
    async def test_raises_sleep_marker(self):
        with pytest.raises(SleepMarker) as exc:
            await sleep(5000)
        assert exc.value.duration_ms == 5000
```

**Nuevo test a agregar** (`tests/test_distributed.py`):

```python
import pytest
from unittest.mock import AsyncMock, patch
from cerebelum.proto.worker_service_pb2 import TaskStatus
from cerebelum.dsl.workflow_markers import ApprovalMarker, SleepMarker


class TestDistributedTaskResult:
    @pytest.mark.asyncio
    async def test_task_result_uses_native_approval_status(self):
        """Verify that ApprovalMarker produces TaskStatus.APPROVAL with approval_request."""
        from cerebelum.distributed import DistributedWorker

        worker = DistributedWorker("test-worker")
        worker.steps = {}

        # Create a mock task
        class MockTask:
            task_id = "task-1"
            execution_id = "exec-1"
            workflow_module = "test"
            step_name = "test_step"
            step_inputs = {}

        # Monkey-patch _execute_task to raise ApprovalMarker
        async def mock_step(ctx, **kwargs):
            raise ApprovalMarker(
                approval_type="manual",
                data={"doc": "123"},
                timeout_ms=60_000
            )

        worker.steps["test_step"] = mock_step

        result = await worker._execute_task(MockTask())

        assert result.status == TaskStatus.APPROVAL
        assert result.approval_request is not None
        assert result.approval_request.approval_type == "manual"
        assert result.approval_request.timeout_ms == 60_000

    @pytest.mark.asyncio
    async def test_task_result_uses_native_sleep_status(self):
        """Verify that SleepMarker produces TaskStatus.SLEEP with sleep_request."""
        from cerebelum.distributed import DistributedWorker

        worker = DistributedWorker("test-worker")
        worker.steps = {}

        class MockTask:
            task_id = "task-2"
            execution_id = "exec-2"
            workflow_module = "test"
            step_name = "test_step"
            step_inputs = {}

        async def mock_sleep(ctx, **kwargs):
            raise SleepMarker(duration_ms=5000, data={"checkpoint": True})

        worker.steps["test_step"] = mock_sleep

        result = await worker._execute_task(MockTask())

        assert result.status == TaskStatus.SLEEP
        assert result.sleep_request is not None
        assert result.sleep_request.duration_ms == 5000

    @pytest.mark.asyncio
    async def test_normal_success_unchanged(self):
        """Verify normal steps still use TaskStatus.SUCCESS."""
        from cerebelum.distributed import DistributedWorker

        worker = DistributedWorker("test-worker")
        worker.steps = {}

        class MockTask:
            task_id = "task-3"
            execution_id = "exec-3"
            workflow_module = "test"
            step_name = "test_step"
            step_inputs = {}

        async def mock_normal(ctx, **kwargs):
            return {"ok": True}

        worker.steps["test_step"] = mock_normal

        result = await worker._execute_task(MockTask())

        assert result.status == TaskStatus.SUCCESS
```

---

## Nivel 3: Integration Test — Engine + Worker (Docker)

### Requisitos

- Docker + docker-compose
- PostgreSQL corriendo

### Setup

```bash
# 1. Levantar dependencias
cd cerebelum
docker compose up -d postgres

# 2. Crear DB y migrar
mix ecto.create
mix ecto.migrate

# 3. Levantar engine
mix phx.server
# → http://localhost:4001

# 4. En otra terminal, worker Python
cd cerebelum-python
pip install -e .
python -m cerebelum.worker --engine-url http://localhost:4001 --port 9000
```

### 3.1 Test: HITL approval via REST API

```bash
# 1. Crear workflow Python con HITL
cat > /tmp/test_hitl.py << 'EOF'
from cerebelum import step, workflow, wait_for_approval


@step
async def step_1_identity(context, **kwargs):
    """First step — always pauses for approval."""
    await wait_for_approval(
        approval_type="manual",
        data={"stage": "identity_verification"},
        timeout_ms=60_000
    )
    return {"status": "approved", "stage": "identity"}


@step
async def step_2_financials(context, step_1_identity=None, **kwargs):
    """Second step — only runs after approval."""
    return {"status": "done", "stage": "financials"}


@workflow
def test_hitl_workflow(wf):
    wf.timeline(step_1_identity >> step_2_financials)
EOF

# 2. Deploy
curl -s -X POST http://localhost:4001/api/v1/workflows/deploy \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"test_hitl\", \"code\": \"$(cat /tmp/test_hitl.py | sed 's/"/\\"/g' | tr '\n' '\\n')\", \"language\": \"python\"}"

# 3. Execute (no auth en local)
EXEC_ID=$(curl -s -X POST http://localhost:4001/api/v1/executions \
  -H "Content-Type: application/json" \
  -d '{"workflow": "test_hitl", "input": {}}' | jq -r '.data.id')

echo "Execution: $EXEC_ID"

# 4. Verificar estado — DEBE estar waiting_for_approval, NO completed
sleep 2
STATUS=$(curl -s http://localhost:4001/api/v1/executions/$EXEC_ID)
echo "$STATUS" | jq '.state'
# Esperado: "waiting_for_approval"  ← si dice "completed", el bug sigue

# 5. Aprobar
curl -s -X POST http://localhost:4001/api/v1/executions/$EXEC_ID/approve \
  -H "Content-Type: application/json" \
  -d '{"approved_by": "tester", "notes": "looks good"}'

# 6. Verificar estado final
sleep 2
curl -s http://localhost:4001/api/v1/executions/$EXEC_ID | jq '{state, results}'
# Esperado: state=completed, results contiene step_1_identity y step_2_financials
```

### 3.2 Test: Sleep via REST API

```bash
cat > /tmp/test_sleep.py << 'EOF'
from cerebelum import step, workflow, sleep


@step
async def fetch_data(context, **kwargs):
    return {"data": "initial"}


@step
async def wait_a_bit(context, fetch_data=None, **kwargs):
    await sleep(2000)  # 2 seconds
    return {"status": "awake"}


@step
async def finalize(context, fetch_data=None, wait_a_bit=None, **kwargs):
    return {"done": True}


@workflow
def test_sleep_workflow(wf):
    wf.timeline(fetch_data >> wait_a_bit >> finalize)
EOF

# Deploy + execute + verify
curl -s -X POST http://localhost:4001/api/v1/workflows/deploy \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"test_sleep\", \"code\": \"...\", \"language\": \"python\"}"

EXEC_ID=$(curl -s -X POST http://localhost:4001/api/v1/executions \
  -H "Content-Type: application/json" \
  -d '{"workflow": "test_sleep", "input": {}}' | jq -r '.data.id')

# Inmediatamente después — debe estar sleeping
sleep 1
curl -s http://localhost:4001/api/v1/executions/$EXEC_ID | jq '.state'
# Esperado: "sleeping"

# Esperar a que termine
sleep 3
curl -s http://localhost:4001/api/v1/executions/$EXEC_ID | jq '{state, results}'
# Esperado: state=completed
```

---

## Nivel 4: E2E CLI Test

```bash
# 1. Crear proyecto
npx @zea.cl/create-cerebelum test-hitl-e2e
cd test-hitl-e2e

# 2. Crear workflow con wait_for_approval
cat > workflow.py << 'EOF'
from cerebelum import step, workflow, wait_for_approval


@step
async def review(context, **kwargs):
    await wait_for_approval(
        approval_type="manual",
        data={"step": "review", "message": "Please approve"},
        timeout_ms=120_000
    )
    return {"status": "approved"}


@step
async def done(context, review=None, **kwargs):
    return {"message": "Workflow completed after approval"}


@workflow
def hitl_demo(wf):
    wf.timeline(review >> done)
EOF

# 3. Run — debe pausar en review
cerebelum run workflow.py
# Output esperado:
#   🚀 hitl_demo
#   [14:15:02] ExecutionStarted
#   [14:15:03] StepExecuted [review] → waiting for approval
#   ⏸️  Waiting for approval (timeout: 120s)

# 4. En otra terminal, aprobar
EXEC_ID=$(cerebelum status --json | jq -r '.last_execution_id')
cerebelum execution approve $EXEC_ID --response '{"approved_by":"tester"}'

# 5. Verificar en la primera terminal que continuó
#   [14:16:00] ApprovalReceived
#   [14:16:01] StepExecuted [done] → Workflow completed
#   [14:16:01] ExecutionCompleted ✅
```

---

## Checklist

| # | Test | Nivel | Comando |
|---|---|---|---|
| 1 | Engine: detecta `"status": "waiting_for_approval"` | Unit | `mix test test/cerebelum/infrastructure/worker_service_server_test.exs` |
| 2 | Engine: detecta `"status": "sleep"` | Unit | ↑ |
| 3 | Engine: legacy markers siguen funcionando | Unit | ↑ |
| 4 | Engine: native APPROVAL/SLEEP protobuf | Unit | ↑ |
| 5 | Engine: `{:approval, data}` → waiting_for_approval | Unit | `mix test test/cerebelum/execution/engine_test.exs` |
| 6 | Engine: `{:sleep, dur, data}` → sleeping | Unit | ↑ |
| 7 | Python: `wait_for_approval()` raises ApprovalMarker | Unit | `pytest tests/test_async_helpers.py` |
| 8 | Python: native protobuf APPROVAL status | Unit | `pytest tests/test_distributed.py` |
| 9 | Python: native protobuf SLEEP status | Unit | ↑ |
| 10 | Integration: HITL via REST API | Docker | Script Nivel 3.1 |
| 11 | Integration: Sleep via REST API | Docker | Script Nivel 3.2 |
| 12 | E2E: CLI `cerebelum run` + approval | Cloud | Script Nivel 4 |

---

## Rollback Plan

Si el fix causa regresiones:

```bash
# Revertir engine
cd cerebelum && git revert <commit>

# Revertir SDK  
cd cerebelum-python && git revert <commit>
```

Los marcadores legacy (`__cerebelum_approval_request__`, `__cerebelum_sleep_request__`) se mantienen como fallback, así que workflows existentes que los usen no se rompen.
