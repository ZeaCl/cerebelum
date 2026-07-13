# Wiki Index — Cerebelum

## Features

- [workflow-engine](features/workflow-engine.md) — Deterministic state machine, step executor, timeline
- [grpc-worker](features/grpc-worker.md) — gRPC server, Python Worker SDK, distributed execution
- [hitl-approval](features/hitl-approval.md) — Human-in-the-Loop, wait_for_approval, approval flow
- [event-store](features/event-store.md) — Append-only event sourcing, batching, partitioning
- [rest-api](features/rest-api.md) — REST endpoints, JWT auth, execution CRUD, blueprint deploy
- [multi-tenancy](features/multi-tenancy.md) — Organization isolation, rate limiting
- [resurrection](features/resurrection.md) — State reconstruction, crash recovery, workflow resumption
- [blueprint-registry](features/blueprint-registry.md) — Workflow deployment via gRPC, blueprint lifecycle

## Integrations

- [thalamus](integrations/thalamus.md) — JWT introspection, OAuth2, domain roles
- [cranium](integrations/cranium.md) — API backend, dynamic shell
- [fm_funds](integrations/fm_funds.md) — Fund management workflows
- [postgres](integrations/postgres.md) — Event store persistence, partitioned tables
- [redis](integrations/redis.md) — Caching, rate limiting
- [python-worker-sdk](integrations/python-worker-sdk.md) — Distributed step execution via gRPC
- [docker](integrations/docker.md) — Container build, GHCR, compose

## Reglas

- [rules](rules.md) — Convenciones, debugging, HITL patterns, deploy flow
