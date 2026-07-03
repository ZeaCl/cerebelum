# Getting Started

Cerebelum can be used in two modes: **on-premise** (Elixir, zero infra) and **cloud** (ZEA Platform, multi-tenant).

---

## On-Premise Mode

Run the engine locally. No auth, no cloud, no external services needed beyond PostgreSQL.

### 1. Install

```elixir
# mix.exs
def deps do
  [{:cerebelum, "~> 0.1.0"}]
end
```

```bash
mix deps.get
mix ecto.create && mix ecto.migrate
```

### 2. Define a workflow

```elixir
defmodule MyApp.OrderWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate() |> process() |> notify()
    end
  end

  def validate(ctx), do: {:ok, ctx.inputs[:order]}
  def process(_ctx, order), do: {:ok, Map.put(order, :status, :done)}
  def notify(_ctx, _order, result), do: {:ok, %{sent: true}}
end
```

### 3. Execute

```elixir
{:ok, exec} = Cerebelum.execute_workflow(OrderWorkflow, %{order: %{id: "ORD-1"}})
Process.sleep(100)
{:ok, status} = Cerebelum.get_execution_status(exec.id)
# => %{state: :completed, results: %{...}, timeline_progress: "3/3"}
```

---

## Cloud Mode

Use Cerebelum as a managed service on ZEA Platform. JWT auth, multi-tenancy, REST API + gRPC.

### 1. Install SDK

```bash
pip install cerebelum-sdk
```

### 2. Authenticate

```bash
npx @zea.cl/cerebelum-cli login
# Opens browser → Thalamus OAuth2 → stores JWT
```

### 3. Create a workflow (Python)

```python
from cerebelum import step, workflow

@step
async def hello(ctx, _prev):
    name = ctx.get("inputs", {}).get("name", "World")
    return {"ok": f"Hello, {name}!"}

@workflow
def my_workflow(wf):
    wf.timeline(hello)
```

### 4. Deploy & Run

```bash
cerebelum deploy workflow.py
cerebelum run MyWorkflow --input '{"name":"ZEA"}'
cerebelum logs <exec_id> --follow
```

---

## Next Steps

| Mode | Guide |
|---|---|
| On-prem | [Workflow DSL](workflow-dsl.md), [Configuration](configuration.md) |
| Cloud | [CLI Reference](cli.md), [REST API](api/rest.md), [gRPC API](api/grpc.md) |
| Both | [Installation](installation.md), [Error Handling](error-handling.md), [Deployment](deployment.md) |
