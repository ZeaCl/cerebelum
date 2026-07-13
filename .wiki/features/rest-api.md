# REST API

API REST para gestión de ejecuciones y blueprints.

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Health check (DB + gRPC) |
| GET | `/api/v1/executions` | Listar ejecuciones (filtros: status, workflow, limit, offset) |
| POST | `/api/v1/executions` | Crear ejecución (`{"workflow": "...", "inputs": {...}}`) |
| GET | `/api/v1/executions/:id` | Obtener estado de ejecución |
| GET | `/api/v1/executions/:id/events` | Obtener audit trail |
| POST | `/api/v1/executions/:id/stop` | Detener ejecución |
| POST | `/api/v1/executions/:id/resume` | Reanudar ejecución pausada |
| POST | `/api/v1/executions/:id/approve` | Aprobar step HITL |

## Auth

- JWT Bearer token validado vía Thalamus `/oauth/introspect`
- Plug: `Cerebelum.API.Plugs.JWTAuth`
- Extrae `user_id` y `organization_id` del token

## Creación de ejecuciones

Dos modos:
1. **Blueprint** — Busca en BlueprintRegistry, ejecuta vía WorkflowDelegatingWorkflow
2. **Compiled Elixir** — Busca el módulo por nombre, ejecuta directamente

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/api/router.ex` | Rutas y plugs |
| `lib/cerebelum/api/controllers/execution_controller.ex` | Endpoints CRUD |
| `lib/cerebelum/api/controllers/health_controller.ex` | Health check |
| `lib/cerebelum/api/plugs/jwt_auth.ex` | Validación JWT |
