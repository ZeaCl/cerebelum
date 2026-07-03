# Agent Prompt — Cerebelum Production Deploy

## Context

Cerebelum is ZEA's workflow orchestration engine (Elixir/OTP). It provides deterministic workflow execution with event sourcing, a REST API, gRPC for Python workers, and multi-tenancy via Thalamus JWT.

We just completed a major refactor:
- Merged cerebelum-community API into core → unified `ZeaCl/cerebelum` repo
- Renamed from `:cerebelum_core` to `:cerebelum`
- Added JWT auth (Thalamus), organization_id scoping, rate limiting
- Added multi-stage Dockerfile, GitHub Container Registry publishing
- Added cerebelum to ZEA's docker-compose.prod.yml, Caddyfile, Watchtower
- Created SDK repos: cerebelum-python, cerebelum-js, cerebelum-demo-cloud
- Python distributed mode: engine → DelegatingWorkflow → TaskRouter → Worker ✅

## What needs to happen NOW

1. **Build & push Docker image** to `ghcr.io/zeacl/cerebelum:latest`
2. **Add cerebelum DB user** to ZEA's `init_aws.sh` (like thalamus_user, cranium_user)
3. **Deploy** via `docker compose -f docker-compose.prod.yml up -d` on the production EC2 instance
4. **Validate** the full cloud experience using `cerebelum-demo-cloud`

## Key files to check/modify

| File | What |
|------|------|
| `ZeaCl/cerebelum/Dockerfile` | Multi-stage (deps→build→runtime alpine) |
| `ZeaCl/cerebelum/.github/workflows/publish.yml` | Auto-build on push to main |
| `ZeaCl/zea/docker-compose.prod.yml` | Cerebelum service (migrate + app) |
| `ZeaCl/zea/Caddyfile` | `cerebelum.zea.cl` route |
| `ZeaCl/zea/init_aws.sh` | Needs cerebelum_user + cerebelum_prod DB |
| `ZeaCl/infra/terraform/main.tf` | Secrets + DNS for cerebelum |
| `ZeaCl/infra/terraform/userdata.tftpl` | Env vars for cerebelum |

## Agent Instructions

**Plan path**: `ZeaCl/cerebelum/.plan/20260702-213331-2d8809e/`

**CRITICAL**: As you complete each item, mark it `[x]` in `PLAN.md` and push the change. This is how we track progress. Never leave an item unmarked after working on it.

**Work order**: A → B → C → D → E → F → G → H. Don't skip phases.

## Repos involved

```
ZeaCl/cerebelum            ← Engine (this one)
ZeaCl/cerebelum-python      ← Python SDK
ZeaCl/cerebelum-demo-cloud  ← Demo + template
ZeaCl/zea                   ← Platform (docker-compose, Caddy, docs)
ZeaCl/infra                 ← Terraform + AWS
```

## Target state

```bash
# Dev experience:
pip install cerebelum-sdk
cerebelum init my-project
cerebelum login                     # OAuth2 Thalamus
cerebelum deploy workflow.py        # → cerebelum.zea.cl
cerebelum run MyWorkflow --input '{"name":"ZEA"}'
cerebelum logs <id> --follow

# Production:
curl https://cerebelum.zea.cl/health                     # 200
curl https://cerebelum.zea.cl/api/v1/executions          # 401
curl -H "Authorization: Bearer <JWT>" .../executions     # 200 + org scoped
```

## Plan file

See `PLAN.md` for the complete checklist. Mark items as done.
