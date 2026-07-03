# Cerebelum Documentation

Cerebelum is a deterministic workflow orchestration engine. Use it **on-premise** (Elixir, zero infra) or in **cloud mode** (ZEA Platform, multi-tenant, JWT auth).

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

## Getting Started

| Guide | Description |
|---|---|
| [Getting Started](getting-started.md) | First workflow — on-prem and cloud |
| [Installation](installation.md) | Local, Docker, production setup |
| [Configuration](configuration.md) | Env vars, database, gRPC, rate limiting |

## Core Concepts

| Guide | Description |
|---|---|
| [Workflow DSL](workflow-dsl.md) | Timeline, branch, diverge, cycles |
| [Error Handling](error-handling.md) | Diverge, retries, DLQ |
| [CLI Reference](cli.md) | 16 commands for cloud mode |

## API

| Guide | Description |
|---|---|
| [REST API](api/rest.md) | Endpoints, auth, curl examples |
| [gRPC API](api/grpc.md) | Protobuf, worker protocol |

## SDKs

| Guide | Package |
|---|---|
| [Python SDK](sdk/python.md) | `pip install cerebelum-sdk` |
| [TypeScript SDK](sdk/typescript.md) | `npm i @zea.cl/cerebelum` |

## Operations

| Guide | Description |
|---|---|
| [Deployment](deployment.md) | Docker, ZEA Platform, self-hosted |

## Architecture

| Guide | Description |
|---|---|
| [Architecture Overview](architecture/overview.md) | Clean Architecture, supervision tree, event sourcing |

## Links

- [GitHub](https://github.com/ZeaCl/cerebelum)
- [Board](https://github.com/orgs/ZeaCl/projects/6)
- [Contributing](../CONTRIBUTING.md)
- [Changelog](../CHANGELOG.md)
- [Security](../SECURITY.md)
