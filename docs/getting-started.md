# Getting Started

Cerebelum can be used in different ways depending on what you're building. Pick your path:

---

## 🟦 Dev: Build Workflows (On-Premise)

You want to define and run workflows in your Elixir application. No cloud, no auth.

### Quickest path

#### 1. Install

```elixir
# mix.exs
def deps do
  [{:cerebelum, "~> 0.1.0"}]
end
```

```bash
mix deps.get
```

#### 2. Define your first workflow

```elixir
defmodule MyApp.HelloWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      greet() |> personalize() |> deliver()
    end
  end

  def greet(ctx), do: {:ok, "Hello"}
  def personalize(_ctx, {:ok, greeting}), do: {:ok, "#{greeting}, #{ctx.inputs[:name]}!"}
  def deliver(_ctx, _greet, {:ok, message}), do: {:ok, %{sent: true, message: message}}
end
```

#### 3. Execute

```elixir
{:ok, exec} = Cerebelum.execute_workflow(MyApp.HelloWorkflow, %{name: "World"})

{:ok, status} = Cerebelum.get_execution_status(exec.id)
# => %{state: :completed, results: %{deliver: %{sent: true, message: "Hello, World!"}}}
```

#### 4. Dive deeper

- [Workflow DSL Overview](workflow-dsl/overview.md) — All DSL features
- [Timeline](workflow-dsl/timeline.md) — Step sequences
- [Branch & Diverge](workflow-dsl/branch.md) — Conditional logic + error handling
- [Tutorial: First Elixir Workflow](tutorials/01-first-elixir-workflow.md)

---

## ☁️ Dev: Build Workflows (Cloud / ZEA Platform)

You want to run workflows in the managed cloud platform using Python or TypeScript.

### Quickest path

```bash
# 1. Create a project
npx @zea.cl/create-cerebelum my-project
cd my-project

# 2. Run the template workflow
cerebelum run workflow.py
```

The CLI resolves everything automatically:
- ✅ Login (OAuth2 via Thalamus)
- ✅ mTLS certs
- ✅ Deploy blueprint
- ✅ Start worker
- ✅ Execute + live logs

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

### Write your own

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
```

```bash
cerebelum run workflow.py
```

### Dive deeper

- [Python SDK](sdk/python.md) — Full guide
- [TypeScript SDK](sdk/typescript.md) — Full guide
- [CLI Reference](cli.md) — All `cerebelum` commands
- [REST API](api/rest.md) — Direct API access
- [Tutorial: First Python Workflow](tutorials/02-first-python-workflow.md)

---

## 🟢 DevOps: Deploy Cerebelum

You want to run Cerebelum in your own infrastructure or as part of ZEA Platform.

### Quickest path

#### 1. Docker (standalone)

```bash
docker pull ghcr.io/zeacl/cerebelum:latest
docker run -d \
  -e DATABASE_URL=ecto://user:pass@host:5432/cerebelum_prod \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e THALAMUS_URL=http://thalamus:4000 \
  -p 4001:4001 \
  -p 50051:50051 \
  cerebelum
```

#### 2. ZEA Platform (docker compose)

```yaml
# Part of ZeaCl/zea docker-compose.prod.yml
cerebelum:
  image: ghcr.io/zeacl/cerebelum:latest
  environment:
    DATABASE_URL: ecto://cerebelum_user:${CEREBELUM_DB_PASSWORD}@postgres:5432/cerebelum_prod
    MIX_ENV: prod
    PHX_HOST: cerebelum.zea.cl
    PORT: 4001
    SECRET_KEY_BASE: ${SECRET_KEY_BASE_CEREBELUM}
    THALAMUS_URL: http://thalamus:4000
```

#### 3. Elixir Release (from source)

```bash
MIX_ENV=prod mix release
_build/prod/rel/cerebelum/bin/cerebelum start
```

#### 4. Dive deeper

- [Deployment Guide](deployment.md) — Full production setup
- [Configuration](configuration.md) — All env vars and settings
- [Architecture Overview](architecture/overview.md) — System design

---

## 🟣 App Dev: Integrate via REST API

You have an application that needs to trigger or monitor Cerebelum workflows via HTTP.

### Quickest path

#### 1. Authenticate

All endpoints (except `/health` and workflow discovery) require a JWT from Thalamus:

```bash
# Get a token (Client Credentials grant)
curl -X POST https://auth.zea.cl/oauth/token \
  -H "Authorization: Basic $(echo -n 'client_id:client_secret' | base64)" \
  -d "grant_type=client_credentials&scope=workflows:read+workflows:write"

# Use the token
export TOKEN="at_xxx..."
```

#### 2. Execute a workflow

```bash
curl -X POST https://cerebelum.zea.cl/api/v1/executions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"workflow": "analisis_ventas", "input": {"periodo": "Q4-2025"}}'
```

#### 3. Check status

```bash
curl https://cerebelum.zea.cl/api/v1/executions/exec_abc123 \
  -H "Authorization: Bearer $TOKEN"
```

#### 4. Dive deeper

- [REST API Overview](api/rest.md) — Auth, pagination, rate limits
- [Executions API](api/executions.md) — All execution endpoints
- [Workflows API](api/workflows.md) — Deploy and manage workflows

---

## 🟡 Architect: Understand the System

You want to understand how Cerebelum is built, its design decisions, and how to extend it.

### Quickest path

1. [Architecture Overview](architecture/overview.md) — Clean Architecture, 4 layers, supervision tree, 18 event types
2. [Workflow DSL Overview](workflow-dsl/overview.md) — How the DSL compiles to metadata
3. [Event Sourcing](guides/event-sourcing.md) — Append-only log, replay, time-travel debugging
4. [Thalamus Integration](guides/thalamus-integration.md) — JWT validation, agent tokens, step authorization
5. [AGENTS.md](../AGENTS.md) — Coding agent instructions

---

## Environment Reference

| Environment | URL | Auth |
|---|---|---|
| ZEA Cloud (production) | `https://cerebelum.zea.cl` | JWT via Thalamus OAuth2 |
| Local development (on-prem) | Use as Elixir library | None (trusted env) |
| Docker standalone | `http://localhost:4001` | Optional JWT |
