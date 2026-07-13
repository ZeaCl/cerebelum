# Multi-tenancy

Aislamiento de ejecuciones entre organizaciones.

## Organization isolation

- ETS table `:execution_orgs` mapea `execution_id → organization_id`
- Al crear ejecución vía REST, se registra la org del JWT
- `GET /api/v1/executions` filtra por `organization_id` del token
- Si el token no tiene org (M2M), no se filtra

## Rate limiting

- Hammer + Redis
- Límite: 1000 req/min
- Excedido → 429 Too Many Requests
- Configurable vía application env

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/api/controllers/execution_controller.ex` | `put_execution_org/2`, `get_execution_org/1` |
| `lib/cerebelum/api/plugs/jwt_auth.ex` | Extrae `organization_id` del JWT |
| `lib/cerebelum/event_store.ex` | `list_executions` no filtra por org (el controller lo hace) |
