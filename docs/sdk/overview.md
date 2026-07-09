# SDK Overview

Cerebelum provides SDKs for three languages, each adapted to the language's idioms.

---

## SDK Comparison

| | Elixir | Python | TypeScript |
|---|---|---|---|
| **Package** | `{:cerebelum, "~> 0.1.0"}` | `cerebelum-sdk` | `@zea.cl/cerebelum` |
| **Registry** | Hex | PyPI | npm |
| **DSL** | Macros (`workflow do`) | Decorators (`@step`, `@workflow`) | Decorators (`@Step`, `@Workflow`) |
| **Execution mode** | In-process (BEAM) | gRPC worker | gRPC worker |
| **Auth** | None (trusted env) | JWT + mTLS | JWT + mTLS |
| **Best for** | Full control, on-prem | Data science, scripting | Full-stack, web apps |

---

## Architecture: Cloud Mode

```
┌──────────────────┐
│  Python Worker   │── gRPC (mTLS) ──┐
│  (cerebelum-sdk) │                  │
└──────────────────┘                  ▼
                             ┌──────────────────┐
┌──────────────────┐        │    Cerebelum     │
│  TypeScript      │── gRPC │    Engine        │
│  Worker          │──────→│    (Elixir/OTP)  │
└──────────────────┘        └──────────────────┘
```

In cloud mode, Python and TypeScript workers connect via gRPC with mTLS. The engine dispatches steps to workers, which execute step functions and return results.

---

## Quick Start by Language

### Elixir (On-Premise)

```elixir
# mix.exs
{:cerebelum, "~> 0.1.0"}

# Define
defmodule MyWorkflow do
  use Cerebelum.Workflow
  workflow do
    timeline do
      step_a() |> step_b()
    end
  end
  def step_a(ctx), do: {:ok, ctx.inputs[:data]}
  def step_b(_ctx, {:ok, data}), do: {:ok, process(data)}
end

# Execute
{:ok, exec} = Cerebelum.execute_workflow(MyWorkflow, %{data: "hello"})
```

[Elixir Workflow DSL →](../workflow-dsl/overview.md)

### Python

```bash
pip install cerebelum-sdk
```

```python
from cerebelum import step, workflow

@step
async def step_a(context, **kwargs):
    return {"data": context.inputs.get("data")}

@step
async def step_b(context, step_a=None, **kwargs):
    return {"result": step_a.get("data", "").upper()}

@workflow
def my_workflow(wf):
    wf.timeline(step_a >> step_b)
```

[Python SDK →](python.md)

### TypeScript

```bash
npm i @zea.cl/cerebelum
```

```typescript
import { Step, Workflow, CerebelumContext } from '@zea.cl/cerebelum';

@Step()
async stepA(context: CerebelumContext): Promise<any> {
  return { data: context.inputs.data };
}

@Step()
async stepB(context: CerebelumContext, stepA: any): Promise<any> {
  return { result: (stepA.data as string).toUpperCase() };
}

@Workflow()
class MyWorkflow {
  build(wf: any) {
    wf.timeline(this.stepA.bind(this), this.stepB.bind(this));
  }
}
```

[TypeScript SDK →](typescript.md)

---

## Which SDK Should I Use?

| Your use case | SDK |
|---|---|
| Elixir/Phoenix app, full control, on-prem | **Elixir** |
| Data science, ML pipelines, quick scripts | **Python** |
| Full-stack TypeScript, web ecosystem | **TypeScript** |
| Mixed team, cloud mode | **Python or TS + REST API** |
