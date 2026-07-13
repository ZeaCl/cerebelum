# PostgreSQL — Persistence

- **Host**: `postgres` (interno, Docker network)
- **Puerto**: 5432
- **Usuario**: `cerebelum_user`
- **DB prod**: `cerebelum_prod`
- **DB dev**: `cerebelum_dev_79` (issues aislados)

## Tablas

| Tabla | Uso |
|---|---|
| `events` | Event store (particionada por execution_id hash) |
| `workflow_pauses` | Workflows hibernados (sleep/approval > threshold) |
| `schema_migrations` | Ecto migrations |

## Schema

Event store usa PostgreSQL nativo con Ecto para inserts. Las queries de listado
usan fragments SQL directo para performance con COALESCE y subqueries.

## Conexión

```elixir
config :cerebelum, Cerebelum.Repo,
  url: "ecto://cerebelum_user:PASSWORD@postgres:5432/cerebelum_prod"
```
