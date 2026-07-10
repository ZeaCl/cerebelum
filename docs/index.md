# Cerebelum Documentation

Cerebelum is a deterministic workflow orchestration engine. Use it **on-premise** (Elixir, zero infra) or in **cloud mode** (ZEA Platform, multi-tenant, JWT auth via Thalamus).

---

## What are you trying to do?

| I want to... | Start here |
|---|---|
| 🟦 **Build a workflow** (define steps, branching, error handling) | [Workflow DSL →](workflow-dsl/overview.md) |
| 🤖 **Execute from Python/TypeScript** | [SDK Overview →](sdk/overview.md) |
| 🟢 **Deploy Cerebelum on my infra** | [Deployment →](deployment.md) |
| 🟣 **Integrate with my app via API** | [REST API →](api/rest.md) |
| 🟡 **Understand the architecture** | [Architecture Overview →](architecture/overview.md) |

---

## Two Modes

| | On-Premise | Cloud (ZEA Platform) |
|---|---|---|
| **Setup** | `{:cerebelum, "~> 0.1.0"}` in mix.exs | `pip install cerebelum-sdk` |
| **Auth** | None (trusted env) | JWT via Thalamus OAuth2 |
| **Multi-tenancy** | No | Yes (`organization_id` scoping) |
| **API** | Direct Elixir calls | REST + gRPC |
| **Deploy** | Local mix / Docker | `docker compose up` on EC2 |

---

## Workflow DSL

| Guide | Description |
|---|---|
| [Overview](workflow-dsl/overview.md) | DSL concepts, pipes, step dependency injection |
| [Timeline](workflow-dsl/timeline.md) | Linear step sequences |
| [Branch](workflow-dsl/branch.md) | Conditional routing based on results |
| [Diverge](workflow-dsl/diverge.md) | Error handling, retry, pattern matching |
| [Cycles & Jumps](workflow-dsl/cycles.md) | `back_to`, `skip_to`, `continue` |

---

## API

| Guide | Endpoints |
|---|---|
| [Overview](api/rest.md) | Auth headers, pagination, rate limits, response format |
| [Executions](api/executions.md) | Create, status, events, stop, resume, approve |
| [Workflows](api/workflows.md) | List, deploy, code |
| [Workers](api/workers.md) | Register, list |
| [Events](api/events.md) | Audit trail, event sourcing |

---

## SDKs

| Guide | Package |
|---|---|
| [Python SDK](sdk/python.md) | `pip install cerebelum-sdk` |
| [TypeScript SDK](sdk/typescript.md) | `npm i @zea.cl/cerebelum` |

---

## Operations

| Guide | Description |
|---|---|
| [Getting Started](getting-started.md) | First workflow — on-prem and cloud |
| [CLI Reference](cli.md) | All `cerebelum` commands |
| [Configuration](configuration.md) | Env vars, database, gRPC, rate limiting |
| [Deployment](deployment.md) | Docker, ZEA Platform, self-hosted |

---

## Guides

| Guide | Description |
|---|---|
| [Error Handling](guides/error-handling.md) | Diverge, retries, DLQ patterns |
| [Event Sourcing](guides/event-sourcing.md) | Event store, replay, time-travel debugging |
| [Long-Running Workflows](guides/long-running-workflows.md) | Sleep, hibernation, resurrection |
| [Thalamus Integration](guides/thalamus-integration.md) | JWT auth, agent tokens, step authorization |

---

## Architecture

| Guide | Description |
|---|---|
| [Architecture Overview](architecture/overview.md) | Clean Architecture, supervision tree, event sourcing, resilience |

---

## Tutorials

Step-by-step walkthroughs:

| Tutorial | Description |
|---|---|
| [First Elixir Workflow](tutorials/01-first-elixir-workflow.md) | Define and run a workflow in Elixir |
| [First Python Workflow](tutorials/02-first-python-workflow.md) | Build a workflow with the Python SDK |
| [Parallel Execution](tutorials/03-parallel-execution.md) | Run steps concurrently |
| [Error Handling Patterns](tutorials/04-error-handling.md) | Diverge, retry, DLQ in practice |

---

## Links

- [GitHub](https://github.com/ZeaCl/cerebelum)
- [Board](https://github.com/orgs/ZeaCl/projects/6)
- [Contributing](../CONTRIBUTING.md)
- [Changelog](../CHANGELOG.md)
- [Security](../SECURITY.md)
