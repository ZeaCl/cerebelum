<div align="center">

# 🧠 Cerebelum

### Deterministic Workflow Orchestration Engine

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/ZeaCl/cerebelum/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-1.18-purple)](https://elixir-lang.org/)
[![CI](https://github.com/ZeaCl/cerebelum/actions/workflows/publish.yml/badge.svg)](https://github.com/ZeaCl/cerebelum/actions)

**Build, run, and replay workflows with 100% determinism.** Event sourcing, graph-based DSL, multi-language SDKs, and production-ready deployment.

[Quickstart](#rocket-quickstart) · [Docs](docs/index.md) · [CLI](docs/cli.md) · [API](docs/api/rest.md) · [SDKs](#globe_with_meridians-sdks) · [Deploy](docs/deployment.md)

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

- **🎲 100% Reproducible** — Same inputs = same outputs, always. Time-travel debugging.
- **📚 Complete Audit Trail** — Every state change is an event. 18 event types, PostgreSQL-backed.
- **🔀 Graph Workflows** — Cycles, branches, diverges, parallel execution, back_to, skip_to.
- **🌐 Multi-Language** — Elixir native + Python SDK + TypeScript SDK via gRPC.
- **🔄 Long-Running** — Workflow resurrection survives restarts. Hibernate for days/weeks.
- **🏗️ Clean Architecture** — SOLID, testable, maintainable. 40+ test files.

## 🚀 Quickstart

### Elixir (native)

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

### Python (SDK)

```bash
pip install cerebelum-sdk
```

```python
from cerebelum import step, workflow

@step
async def hello(ctx, _prev):
    return {"ok": f"Hello, {ctx.get('inputs', {}).get('name', 'World')}!"}

@workflow
def wf(w): w.timeline(hello)

import asyncio
asyncio.run(wf.execute({"name": "ZEA"}))  # → completed ✅
```

### Cloud (CLI)

```bash
npx @zea.cl/cerebelum-cli login
npx @zea.cl/cerebelum-cli init my-project
npx @zea.cl/cerebelum-cli deploy workflow.py
npx @zea.cl/cerebelum-cli run MyWorkflow --input '{"name":"ZEA"}'
npx @zea.cl/cerebelum-cli logs <id> --follow
```

## 🌐 SDKs

| Language | Package | Guide |
|---|---|---|
| **Elixir** | `{:cerebelum, "~> 0.1.0"}` | [Workflow DSL](docs/workflow-dsl.md) |
| **Python** | `pip install cerebelum-sdk` | [Python SDK](docs/sdk/python.md) |
| **TypeScript** | `npm i @zea.cl/cerebelum` | [TypeScript SDK](docs/sdk/typescript.md) |

## 📚 Documentation

| Section | Description |
|---|---|
| [Getting Started](docs/getting-started.md) | First workflow in 5 minutes |
| [Workflow DSL](docs/workflow-dsl.md) | Timeline, branch, diverge, cycles |
| [CLI Reference](docs/cli.md) | 16 commands: login, deploy, run, logs, doctor |
| [REST API](docs/api/rest.md) | Endpoints, auth, curl examples |
| [gRPC API](docs/api/grpc.md) | Protobuf, worker protocol |
| [Configuration](docs/configuration.md) | Env vars, database, gRPC |
| [Error Handling](docs/error-handling.md) | Diverge, retries, DLQ |
| [Deployment](docs/deployment.md) | Docker, ZEA Platform, self-hosted |
| [Architecture](docs/architecture/overview.md) | Clean Architecture, event sourcing |

## 🏗️ Architecture

```
┌─ Presentation ──────┐  REST API (Phoenix) + gRPC
├─ Infrastructure ─────┤  EventStore, Worker Registry, DLQ
├─ Application ────────┤  Execution Engine, State Reconstructor
├─ Domain ─────────────┤  Workflow DSL, Branch/Diverge, Context
└──────────────────────┘
```

[Full architecture docs →](docs/architecture/overview.md)

## 📦 Deploy

```bash
# Docker
docker pull ghcr.io/zeacl/cerebelum:latest
docker run -e DATABASE_URL=... -e SECRET_KEY_BASE=... -p 4001:4001 cerebelum

# ZEA Platform
cd ZeaCl/zea && docker compose -f docker-compose.prod.yml up -d
```

[Deployment guide →](docs/deployment.md)

## 🤝 Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) — setup, code standards, testing, PR workflow.

## 🔗 Links

- [Changelog](CHANGELOG.md)
- [Security](SECURITY.md)
- [Demo Cloud](https://github.com/ZeaCl/cerebelum-demo-cloud)
- [Board](https://github.com/orgs/ZeaCl/projects/6)

---

<div align="center">

**[Documentation](docs/index.md)** · **[Examples](examples/)** · **[Discussions](https://github.com/ZeaCl/cerebelum/discussions)**

Made with ❤️ using Elixir and OTP

</div>
