# Getting Started

Cerebelum can be used in two modes: **on-premise** (Elixir, zero infra) and **cloud** (ZEA Platform, multi-tenant).

---

## Cloud Mode (Recommended)

3 comandos para empezar:

### 1. Create project

```bash
npx @zea.cl/create-cerebelum my-project
cd my-project
```

Esto crea un proyecto con `workflow.py` listo para ejecutar.

### 2. Run

```bash
cerebelum run workflow.py
```

El CLI hace todo automático:
- ✅ Login (OAuth2 vía Thalamus)
- ✅ Certs (mTLS generados por el engine)
- ✅ Deploy (blueprint al cloud)
- ✅ Worker (`python -m cerebelum.worker`)
- ✅ Ejecución + logs en vivo

```bash
🧠 Cerebelum Run

  ✅ Login — JWT presente
  ✅ Certs — mTLS listos
  ✅ Blueprint — analisis_ventas v0.1.0
  ✅ Worker — python -m cerebelum.worker (PID 20727)

  🚀 analisis_ventas
  [14:15:02] ExecutionStarted
  [14:15:03] StepExecuted [obtener_datos] → usuarios=1250, ventas=34500000
  [14:15:04] StepExecuted [procesar_datos] → ticket_promedio=27600
  [14:15:05] StepExecuted [notificar] → slack#general
  [14:15:05] ExecutionCompleted ✅

  ⏱️ 7.4s
```

### 3. Check status

```bash
cerebelum status
cerebelum logs
```

---

## Write Your Own Workflow

Edit `workflow.py`:

```python
from cerebelum import step, workflow
import asyncio

@step
async def obtener_datos(context, **kwargs):
    await asyncio.sleep(0.8)
    return {"usuarios": 1_250, "ventas": 34_500_000}

@step
async def procesar(context, obtener_datos=None, **kwargs):
    datos = obtener_datos or {}
    return {"ticket_promedio": datos["ventas"] / datos["usuarios"]}

@workflow
def mi_workflow(wf):
    wf.timeline(obtener_datos >> procesar)

import asyncio
async def main():
    result = await mi_workflow.execute({})
    print(f"Status: {result.status}")

asyncio.run(main())
```

```bash
cerebelum run workflow.py
```

---

## On-Premise Mode

Run the engine locally. No auth, no cloud, Elixir-native.

### 1. Install

```elixir
# mix.exs
def deps do
  [{:cerebelum, "~> 0.1.0"}]
end
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
```

---

## Next Steps

| Mode | Guide |
|---|---|
| Cloud | [CLI Reference](cli.md), [Python SDK](sdk/python.md), [REST API](api/rest.md) |
| On-prem | [Workflow DSL](workflow-dsl.md), [Configuration](configuration.md) |
| Both | [Installation](installation.md), [Error Handling](error-handling.md) |
