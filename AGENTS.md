# AGENTS.md — Cerebelum AI Agent Guide

> **Para agentes de IA que toman la posta del proyecto.**
> Leé esto primero. El estado en vivo está en el board, no acá.

## Qué es Cerebelum

Motor de orquestación de workflows determinístico. Elixir/OTP, event sourcing, REST + gRPC, SDKs Python/TypeScript, desplegado en ZEA Platform.

**Repos:**

| Repo | Rol |
|---|---|
| `ZeaCl/cerebelum` | Engine (este repo) |
| `ZeaCl/cerebelum-python` | Python SDK (`pip install cerebelum-sdk`) |
| `ZeaCl/cerebelum-demo-cloud` | Demo + template `cerebelum init` |
| `ZeaCl/zea` | ZEA Platform (docker-compose, Caddy, docs) |
| `ZeaCl/infra` | Terraform (AWS, Cloudflare, secrets) |

## Estado actual

**📋 Board**: https://github.com/orgs/ZeaCl/projects/6

El board SIEMPRE tiene la verdad. Usalo como fuente primaria:
- Issues organizados en **8 fases** (A→H), cada una es un parent issue con sub-issues
- **1 milestone**: `Cerebelum Production Deploy`
- El board se actualiza solo al cerrar issues

**Producción**: Cerebelum corre en `https://cerebelum.zea.cl` (EC2, Docker, Caddy, Watchtower).

**Lo completado**: Fases A, B, C, D → 19/30 sub-issues ✅
**Lo pendiente**: Fases E (4 items de demo-cloud), F (gRPC worker), G (multi-tenancy), H (docs finales)

## Cómo trabajar

### Commits

Usá [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: descripción     ← nueva funcionalidad
fix: descripción      ← bug fix
docs: descripción     ← documentación
refactor: descripción ← refactor sin cambio funcional
```

### Código — Engine (Elixir)

```bash
cd cerebelum-core
mix deps.get && mix compile
mix test                    # tests
mix format && mix credo     # calidad
```

Estructura: Clean Architecture. Domain → Application → Infrastructure → Presentation.
Nunca mezcles capas. Los plugs van en `lib/cerebelum/api/plugs/`.

### Código — Python SDK

```bash
cd cerebelum-python
pip install -e .
python examples/01_hello_world.py
```

### Código — ZEA Platform

El `docker-compose.prod.yml` en `ZeaCl/zea` tiene los servicios. Cerebelum sigue el patrón de Thalamus/Cranium: `migrate_X` + `X` + Caddy + Watchtower.

### Deploy

1. Push a `main` en `ZeaCl/cerebelum` → GitHub Actions build + push `ghcr.io/zeacl/cerebelum:latest`
2. Watchtower en EC2 hace auto-pull cada 5 min
3. O manual: `docker pull ghcr.io/zeacl/cerebelum:latest && docker compose -f docker-compose.prod.yml up -d cerebelum`

### Planes de deploy

Están en `.plan/YYYYMMDD-HHMMSS-<hash>/`. Cada plan tiene `PLAN.md` (checklist), `PROMPT.md` (contexto para agente), `GAPS.md` (lo que falta).

## Dónde está cada cosa

| Qué | Dónde |
|---|---|
| Estado del proyecto | [Board](https://github.com/orgs/ZeaCl/projects/6) |
| Spec actual | `.openspec/cerebelum-cloud-v2/` |
| Plan de deploy | `.plan/20260702-213331-2d8809e/` |
| Documentación | `docs/index.md` (hub) |
| API REST | `docs/api/rest.md` |
| gRPC | `docs/api/grpc.md` |
| Workflow DSL | `docs/workflow-dsl.md` |
| CLI | `docs/cli.md` |
| Contributing | `CONTRIBUTING.md` |
| Changelog | `CHANGELOG.md` |
| Seguridad | `SECURITY.md` |

## Convenciones

- **Issues**: parent = fase (A-H), sub-issues = tareas. Al completar un sub-issue → `gh issue close N --reason completed`
- **Labels**: `engine` (código), `platform` (ZEA), `infra` (Terraform), `sdk` (Python/TS)
- **Milestone**: solo uno — `Cerebelum Production Deploy`
- **No crees specs nuevas** sin approval. La spec activa es `.openspec/cerebelum-cloud-v2/`
- **Testeá en producción** cuando sea posible — `curl https://cerebelum.zea.cl/health`
- **No modifiques `docker-compose.prod.yml` de ZEA** sin revisar el patrón de Thalamus/Cranium primero
- **CLI está en este repo** (`cli/`), no en un repo separado

## Para producción

```bash
# Health check
curl https://cerebelum.zea.cl/health

# Auth check
curl https://cerebelum.zea.cl/api/v1/executions          # → 401
curl -H "Authorization: Bearer <JWT>" .../api/v1/executions  # → 200

# Doctor (si el CLI está instalado)
npx @zea.cl/cerebelum-cli doctor
```
