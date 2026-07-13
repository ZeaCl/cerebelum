# AGENTS.md — Cerebelum AI Agent Guide

> Para cualquier agente de IA que tome la posta. **El board es la única fuente de verdad.**
> Este archivo no cambia — el estado del proyecto vive en el board, no acá.
>
> 📝 **Memoria persistente**: Leer `.wiki/log.md` al iniciar una sesión para conocer el
> historial reciente. Al terminar una feature o fix, escribir una entrada en `.wiki/log.md`
> con timestamp, tipo (feat/fix/docs/infra), issue #, descripción breve y archivos tocados.
> Usar `.wiki/rules.md` para consultar patrones y convenciones antes de implementar.

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

## HITL — Human-in-the-Loop

Workflows pueden pausar y esperar aprobación humana usando `wait_for_approval()`.

### Flujo completo

```
Python step → wait_for_approval() → ApprovalMarker exception
  → Worker SDK lo atrapa → envía TaskStatus.APPROVAL via gRPC
  → Engine (worker_service_server.ex) → {:approval, data}
  → Engine (state_handlers.ex) → :waiting_for_approval state
  → POST /executions/:id/approve → Engine re-ejecuta el step con datos
  → Step recibe inputs → valida → OK → avanza
```

### Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/infrastructure/worker_service_server.ex` | Detecta APPROVAL/SLEEP del worker |
| `lib/cerebelum/execution/engine/state_handlers.ex` | Maneja `{:approval, data}`, transiciona a `:waiting_for_approval`, re-ejecuta post-approve |
| `lib/cerebelum/execution/approval.ex` | API pública: `approve/2`, `approve_by_id/2` |
| `lib/cerebelum/api/controllers/execution_controller.ex` | Endpoint `POST /executions/:id/approve` |
| `lib/cerebelum/execution/engine/data.ex` | `json_safe_results/1`, `build_step_inputs` |
| `lib/cerebelum/execution/results_cache.ex` | Acepta atoms y strings en step names |
| `lib/cerebelum/context.ex` | `update_step/2` acepta atoms y strings |

### SDK (cerebelum-python)

| Archivo | Rol |
|---|---|
| `cerebelum/dsl/async_helpers.py` | `wait_for_approval()` — lanza `ApprovalMarker` |
| `cerebelum/dsl/decorators.py` | `@step` wrapper — NO debe tragar `WorkflowMarker` |
| `cerebelum/dsl/workflow_markers.py` | `ApprovalMarker`, `SleepMarker` |
| `cerebelum/distributed.py` | Worker atrapa markers → envía APPROVAL/SLEEP vía gRPC |

### Debugging

- **"Los steps se completan instantáneamente"**: probablemente el `@step` decorator se traga la excepción. Verificar SDK >= 0.3.1.
- **"Step recibe unexpected keyword argument 'previous_results'"**: agregar `**kwargs` al final de cada step function.
- **"El approve no le pasa datos al step"**: verificar que `build_step_inputs` en `state_handlers.ex` recibe `Map.get(data.results, step_name)` con valor `{:ok, %{...}}`.
- **"El worker no se conecta"**: verificar `CEREBELUM_CORE_URL`. En Docker compose local es `cerebelum:50051` (red interna).
- **Logs no aparecen en el container**: `docker compose build` cachela capas. Borrar imágenes (`docker rmi -f zea-cerebelum`) y usar `docker build --no-cache` directo desde el directorio del repo.
- **Dos workers compiten por las tareas**: matar workers viejos (`docker stop`, `pkill`). El TaskRouter usa sticky routing.

### Entorno local

```bash
# Build directo (más confiable que docker compose build)
cd cerebelum && docker build --no-cache -t zea-cerebelum -f Dockerfile --target runtime .
cd zea && docker compose -f docker-compose.local.yml up -d --no-build cerebelum

# SDK local
cd cerebelum-python && pip install -e .

# Limpiar todo
cd zea && docker compose -f docker-compose.local.yml down -v
```
