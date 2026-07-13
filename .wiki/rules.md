# Reglas y Patrones — Cerebelum

## Arquitectura

### Clean Architecture
- **Domain** → `lib/cerebelum/execution/` (engine, context, events, error_info)
- **Application** → `lib/cerebelum.ex` (API pública), `lib/cerebelum/workflow/`
- **Infrastructure** → `lib/cerebelum/infrastructure/` (event_store, blueprint_registry, worker_service_server)
- **Presentation** → `lib/cerebelum/api/` (controllers, router, plugs)

### Event Sourcing
- Todos los cambios de estado son eventos inmutables en EventStore
- Eventos críticos (started, completed, failed) se persisten sync
- Eventos intermedios (steps, diverge, branch) se persisten async (batched, 100ms)
- Versionado optimista con unique constraint on (execution_id, version)

### State Machine
- Engine usa `:gen_statem` con estados: initializing, executing_step, completed, failed, sleeping, waiting_for_approval
- StateHandlers implementa callbacks por estado
- Cada step ejecuta local (Elixir) o remote (gRPC worker)

## Deploy

### CI/CD
- Push a `main` → GitHub Actions build → push `ghcr.io/zeacl/cerebelum:latest`
- Watchtower en EC2 auto-pull cada 5 min
- **NUNCA hacer deploy manual** al VPS

### Local
```bash
# Build + run con full environment
cd zea && docker compose -f docker-compose.local.yml up -d --build cerebelum

# Build directo (sin compose cache)
docker build --no-cache -t zea-cerebelum -f Dockerfile --target runtime .
```

### Puertos
| Puerto | Protocolo | Uso |
|---|---|---|
| 4001 | HTTP | REST API + Phoenix |
| 50051 | gRPC | Worker communication |

## HITL — Human-in-the-Loop

### Flujo
```
Python step → wait_for_approval() → ApprovalMarker
  → Worker SDK → TaskStatus.APPROVAL via gRPC
  → Engine → :waiting_for_approval
  → POST /executions/:id/approve → re-ejecuta step con datos
```

### Debugging HITL
- **Steps se completan instantáneamente**: `@step` decorator traga excepción. SDK >= 0.3.1.
- **Step recibe `previous_results` inesperado**: agregar `**kwargs` al final de cada step.
- **Approve no pasa datos**: `build_step_inputs` usa `Map.get(data.results, step_name)` con `{:ok, %{...}}`.
- **Worker no se conecta**: `CEREBELUM_CORE_URL=cerebelum:50051` en red interna.
- **Dos workers compiten**: TaskRouter usa sticky routing. Matar workers viejos.

## Docker

### Build
- Multi-stage Dockerfile con `mix release`
- `Release.migrate()` ejecuta migraciones
- Container ephemeral (`migrate_cerebelum`) ejecuta migraciones y sale

### Logs
- `docker compose build` cachela capas → borrar imágenes y usar `--no-cache` para cambios de código
- `docker logs zea_cerebelum_local` para ver output

## Multi-tenancy

### Organization isolation
- `execution_orgs` ETS table mapea execution_id → organization_id
- `GET /api/v1/executions` filtra por org del JWT
- Rate limit: 429 al exceder 1000 req/min

## Commits
- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`

## Código
```bash
mix deps.get && mix compile
mix test && mix format && mix credo
```
