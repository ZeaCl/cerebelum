<div align="center">

# 🧠 Cerebelum

### Deterministic Workflow Orchestration Engine

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/ZeaCl/cerebelum/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-1.18-purple)](https://elixir-lang.org/)

**Build, run, and replay workflows with 100% determinism.** Event sourcing, graph-based DSL, multi-language SDKs.

**Two modes:** [On-premise](#on-premise) (Elixir) or [Cloud](#cloud-quickstart) (ZEA Platform).

[Cloud Quickstart](#cloud-quickstart) · [On-Premise](#on-premise) · [Docs](docs/index.md) · [CLI](docs/cli.md) · [SDK](docs/sdk/python.md)

</div>

---

## ✨ Why Cerebelum?

| Feature | Cerebelum | Temporal | Airflow | LangGraph |
|---|---|---|---|---|
| **Deterministic** | ✅ Always | ⚠️ Partial | ❌ | ⚠️ Manual |
| **Event Sourcing** | ✅ Built-in | ✅ | ❌ | ❌ |
| **Graph Cycles** | ✅ Native | ❌ | ✅ DAG | ✅ |
| **Multi-Language** | ✅ gRPC | ✅ | ⚠️ Python | ✅ Python |
| **Local Dev** | ✅ Zero setup | ⚠️ Docker | ⚠️ Complex | ✅ |
| **Throughput** | ✅ 640K/s | ✅ | ⚠️ | ❌ |

- **🎲 Deterministic** — Same inputs = same outputs, always. Time-travel debugging.
- **📚 Event Sourcing** — Complete audit trail. 18 event types, PostgreSQL.
- **🔀 Graph Workflows** — Cycles, branches, diverges, parallel, back_to, skip_to.
- **🌐 Multi-Language** — Elixir native + Python SDK + TypeScript SDK via gRPC.
- **🔄 Long-Running** — Workflow resurrection. Hibernate for days/weeks.

---

## On-Premise

Run the engine locally. No auth, no cloud.

```elixir
# 1. Add dependency
{:cerebelum, "~> 0.1.0"}

# 2. Define workflow
defmodule MyWorkflow do
  use Cerebelum.Workflow
  workflow do
    timeline do
      validate() |> process() |> notify()
    end
  end
  def validate(ctx), do: {:ok, ctx.inputs[:data]}
  def process(_ctx, data), do: {:ok, Map.put(data, :status, :done)}
  def notify(_ctx, _data, result), do: {:ok, %{sent: true}}
end

# 3. Execute
{:ok, exec} = Cerebelum.execute_workflow(MyWorkflow, %{data: %{id: 1}})
```

[Elixir docs →](docs/workflow-dsl.md)

---

## ☁️ Cloud Quickstart

3 comandos para empezar:

```bash
npx @zea.cl/create-cerebelum my-project
cd my-project
cerebelum run workflow.py
```

El CLI resuelve todo automático: auth → certs → deploy → worker → execute → logs.

```python
# workflow.py (generado por create-cerebelum)
from cerebelum import step, workflow
import asyncio

@step
async def obtener_datos(context, **kwargs):
    await asyncio.sleep(0.8)
    return {"usuarios": 1_250, "ventas": 34_500_000}

@step
async def procesar(context, obtener_datos=None, **kwargs):
    return {"ticket_promedio": 27_600}

@workflow
def analisis_ventas(wf):
    wf.timeline(obtener_datos >> procesar)
```

[Cloud docs →](docs/getting-started.md) · [CLI](docs/cli.md) · [Python SDK](docs/sdk/python.md) · [REST API](docs/api/rest.md)

---

## 🌐 SDKs

| Language | Package | Guide |
|---|---|---|
| **Elixir** | `{:cerebelum, "~> 0.1.0"}` | [Workflow DSL](docs/workflow-dsl.md) |
| **Python** | `pip install cerebelum-sdk` | [Python SDK](docs/sdk/python.md) |
| **TypeScript** | `npm i @zea.cl/cerebelum` | [TypeScript SDK](docs/sdk/typescript.md) |

## 🏗️ Architecture

```
┌─ Presentation ──────┐  REST API (Phoenix) + gRPC
├─ Infrastructure ─────┤  EventStore, Worker Registry, DLQ
├─ Application ────────┤  Execution Engine, State Reconstructor
├─ Domain ─────────────┤  Workflow DSL, Branch/Diverge, Context
└──────────────────────┘
```

[Architecture docs →](docs/architecture/overview.md)

## 📦 Deploy

```bash
# Docker standalone
docker pull ghcr.io/zeacl/cerebelum:latest

# ZEA Platform (recommended)
cd ZeaCl/zea && docker compose -f docker-compose.prod.yml up -d
```

[Deployment guide →](docs/deployment.md)

## 🤝 Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) — setup, code standards, PR workflow.

## 🔗 Links

- [Documentation](docs/index.md)
- [Changelog](CHANGELOG.md)
- [Security](SECURITY.md)
- [Board](https://github.com/orgs/ZeaCl/projects/6)

---

<div align="center">

Made with ❤️ using Elixir and OTP

</div>
