# Python SDK

Build and run Cerebelum workflows in Python. Uses decorators for step/workflow definition and runs as a gRPC worker in cloud mode.

---

## Installation

```bash
pip install cerebelum-sdk
```

---

## Core Concepts

### Step

A `@step` is an async function that performs one unit of work:

```python
from cerebelum import step

@step
async def fetch_user(context, **kwargs):
    user_id = context.inputs.get("user_id")
    user = await db.get_user(user_id)
    return user.to_dict()
```

- **First argument**: `context` (execution context with `.inputs`, `.execution_id`, etc.)
- **`**kwargs`**: Previous step results, keyed by step function name
- **Return**: A dict/object with step result data

### Workflow

A `@workflow` decorates a function that defines the step sequence:

```python
from cerebelum import workflow

@workflow
def user_onboarding(wf):
    wf.timeline(fetch_user >> validate >> send_email)
```

- **`>>` operator**: Chains steps sequentially
- **`[a, b, c]`**: Groups steps for parallel execution

---

## Timeline Operators

| Operator | Meaning | Example |
|---|---|---|
| `A >> B` | Sequential: A then B | `step1 >> step2 >> step3` |
| `[A, B, C]` | Parallel: A, B, C together | `[fetch_a, fetch_b, fetch_c] >> aggregate` |
| `[A, B] >> C` | Parallel then sequential | `[api_a, api_b] >> merge >> store` |

---

## Complete Example

```python
from cerebelum import step, workflow
import asyncio
from datetime import datetime


@step
async def obtener_datos(context, **kwargs):
    """Fetch data from external source."""
    await asyncio.sleep(0.8)
    return {
        "usuarios": 1_250,
        "ventas": 34_500_000,
        "periodo": context.inputs.get("periodo", "Q4")
    }


@step
async def enriquecer(context, obtener_datos=None, **kwargs):
    """Enrich with AI classification."""
    await asyncio.sleep(0.5)
    datos = obtener_datos or {}
    return {
        **datos,
        "clasificacion": "crecimiento",
        "timestamp": datetime.utcnow().isoformat()
    }


@step
async def generar_reporte(context, enriquecer=None, **kwargs):
    """Generate final report."""
    datos = enriquecer or {}
    return {
        "reporte": f"Ventas {datos.get('periodo')}: ${datos.get('ventas', 0):,}",
        "metricas": {
            "ticket_promedio": datos.get("ventas", 0) / max(datos.get("usuarios", 1), 1),
            "categoria": datos.get("clasificacion", "n/a")
        }
    }


@workflow
def analisis_ventas(wf):
    wf.timeline(obtener_datos >> enriquecer >> generar_reporte)
```

---

## Execution

### Local (Embedded)

```python
import asyncio
from analisis_ventas import analisis_ventas

async def main():
    result = await analisis_ventas.execute({"periodo": "Q4-2025"})
    print(f"Status: {result.status}")
    print(f"Results: {result.results}")

asyncio.run(main())
```

### Cloud (ZEA Platform)

```bash
# CLI handles everything
cerebelum run workflow.py
```

---

## Error Handling

Steps can return error statuses that the engine handles:

```python
@step
async def call_api(context, **kwargs):
    try:
        response = await external_api(context.inputs["url"])
        return {"status": "ok", "data": response}
    except TimeoutError:
        return {"status": "timeout"}
    except Exception as e:
        return {"status": "error", "message": str(e)}
```

The engine maps statuses to diverge actions on the Elixir side.

---

## Step Dependencies

Steps receive all previous results via `**kwargs`:

```python
@step
async def step_a(context, **kwargs):
    return {"value": 42}

@step
async def step_b(context, step_a=None, **kwargs):  # ← receives step_a result
    previous = step_a or {}
    return {"doubled": previous.get("value", 0) * 2}

@step
async def step_c(context, step_a=None, step_b=None, **kwargs):  # ← receives both
    a = step_a or {}
    b = step_b or {}
    return {"sum": a.get("value", 0) + b.get("doubled", 0)}
```

---

## Worker Mode

When running as a gRPC worker:

```bash
# Start worker process
python -m cerebelum.worker --port 9000

# Worker registers with Cerebelum engine automatically
# Engine dispatches step executions to this process
```

---

## See Also

- [TypeScript SDK](typescript.md) — TypeScript equivalent
- [First Python Workflow Tutorial](../tutorials/02-first-python-workflow.md) — Hands-on tutorial
- [CLI Reference](../cli.md) — `cerebelum run`, `deploy`, `logs`, etc.
