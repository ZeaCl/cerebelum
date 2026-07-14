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

## Debugging — Workflows distribuidos (gRPC + Python Worker)

### Token de autenticación
- **Solo tokens OAuth2 PKCE** emitidos por `/oauth/token` tienen `domain_roles` y pasan `/oauth/introspect`
- Tokens de `/api/public/login` tienen `domain_roles` pero NO pasan introspection (son tokens de sesión, no OAuth2)
- Tokens `client_credentials` (`internal_login`) pasan introspection pero NO tienen `domain_roles`
- Para probar en prod: flujo PKCE completo → abrir browser en `https://auth.zea.cl/oauth/authorize?...` → capturar code en callback → intercambiar por token

### Propagación de auth_token
- `execution_controller.ex`: extrae `Authorization` header → `get_req_header(conn, "authorization")`
- Solo se propaga para **blueprints** (no workflows Elixir compilados) → `execute_blueprint(workflow_name, inputs, auth_token)`
- El token viaja como `context.metadata.auth_token` → `state_handlers.ex` → `Map.put(step_inputs, "auth_token", token)`
- Verificar en logs: `"Propagating auth_token to step X (len=NNN)"` o `"No auth_token in context metadata for step X"`

### named_results — Atom vs String keys
- **`Data.new`** extrae la timeline del blueprint y convierte a átomos: `String.to_atom(name)` → `data.timeline`
- **`Data.store_result`** guarda con `step_name` que viene de `data.timeline` (átomo) → `data.results[atom]`
- **Siempre usar `data.timeline`** para leer resultados. NUNCA reconstruir desde `data.blueprint.definition.timeline` (strings)
- Si `build_step_inputs` muestra `prev_steps=["name"]` (strings), hay un mismatch → `Map.get` devuelve nil

### Deploy en VPS
- SSH: `ssh -i infra/keys/sao-paulo/llave-aws-zea.pem ubuntu@52.67.48.59`
- Directorio compose: `/home/ubuntu/zea-platform/`
- Comandos: `sudo docker compose -f docker-compose.prod.yml up -d cerebelum`
- Logs: `sudo docker logs zea_cerebelum --tail 100`
- Worker: `sudo docker logs zea_sudlich_worker --tail 50`
- fm_funds: `sudo docker logs zea_fm_funds --tail 50`
- Imagen: `ghcr.io/zeacl/cerebelum:latest` (Watchtower auto-pull cada 5 min)
- Forzar update: `sudo docker pull ghcr.io/zeacl/cerebelum:latest && sudo docker compose up -d cerebelum`

### Build multi-plataforma
- Build local (arm64): `docker build -t zea-cerebelum .`
- Build para VPS (amd64): `docker buildx build --platform linux/amd64 -t ghcr.io/... --push .`
- Si el VPS tira "no matching manifest for linux/amd64/v3", estás pusheando arm64 → reconstruir con `--platform linux/amd64`

### Test en prod sin romper nada
- Crear ejecución con nombre de fondo único para evitar 409 Conflict
- Usar token `internal_login` + `client_secret=internal_secret_do_not_expose` para pruebas de flujo HITL (no crea fondo pero valida todo el pipeline)
- Usar token OAuth2 PKCE de `c@zea.cl` / `GusVicentAnto1.` para prueba completa con creación de fondo
- El callback del PKCE se puede capturar con un server HTTP local en `localhost:4005`
