# AGENTS.md — Cerebelum AI Agent Guide

> Para cualquier agente de IA que tome la posta. **El board es la única fuente de verdad.**
> Este archivo no cambia — el estado del proyecto vive en el board, no acá.

## Cerebelum

Motor de orquestación de workflows determinístico. Elixir/OTP, event sourcing, REST + gRPC, SDKs Python/TypeScript. Corre on-premise (Elixir, sin infra) o en cloud (ZEA Platform, multi-tenant, JWT).

## Board — fuente de verdad

📋 **[GitHub Project](https://github.com/orgs/ZeaCl/projects/6)**

Todo lo que hay que hacer está ahí. Todo lo que ya se hizo, también. Antes de tocar código, mirá el board. Al terminar algo, reflejalo en el board.

### Reglas del board

1. **Al tomar una tarea** → movela a `In Progress`. No la dejes en `Todo`.
2. **Al terminar** → movela a `Done`. Si es un issue, cerrarlo con `gh issue close N --reason completed`.
3. **Si algo está bloqueado** → `Blocked`. Poné en el body por qué y qué se necesita.
4. **Nunca dejes tareas en `Todo` que ya empezaste.** Otros pueden estar mirando el board.
5. **El parent issue se cierra solo** cuando todos sus sub-issues están completos.

## Cómo arrancar

1. Abrí el [board](https://github.com/orgs/ZeaCl/projects/6)
2. Buscá issues en `Todo`
3. Agarrá uno, movelo a `In Progress`
4. Leé el código relevante (ver mapa abajo)
5. Implementá, probá, pusheá
6. Cerrá el issue, movelo a `Done`

## Repos

| Repo | Qué es |
|---|---|
| `ZeaCl/cerebelum` | Engine (este repo) |
| `ZeaCl/cerebelum-python` | Python SDK (`pip install cerebelum-sdk`) |
| `ZeaCl/cerebelum-demo-cloud` | Demo + template `cerebelum init` |
| `ZeaCl/zea` | ZEA Platform (docker-compose, Caddy, docs) |
| `ZeaCl/infra` | Terraform (AWS, Cloudflare, secrets) |

## Dónde está cada cosa

| Qué | Dónde |
|---|---|
| Estado del proyecto | [Board](https://github.com/orgs/ZeaCl/projects/6) |
| Spec activa | `.openspec/` |
| Plan de deploy | `.plan/` |
| Documentación | `docs/index.md` |
| Contributing | `CONTRIBUTING.md` |
| Seguridad | `SECURITY.md` |

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.

## Código

```bash
mix deps.get && mix compile
mix test && mix format && mix credo
```

Clean Architecture: Domain → Application → Infrastructure → Presentation.

## Deploy

1. Push a `main` → GitHub Actions build + push `ghcr.io/zeacl/cerebelum:latest`
2. Watchtower en EC2 auto-pull cada 5 min
3. O manual: `docker pull ghcr.io/zeacl/cerebelum:latest && docker compose -f docker-compose.prod.yml up -d cerebelum`

## Producción

```bash
curl https://cerebelum.zea.cl/health
```
