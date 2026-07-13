# Redis — Caching & Rate Limiting

- **Host**: `redis` (interno, Docker network)
- **Puerto**: 6379
- **Uso**: Rate limiting (Hammer)

## Rate Limiting

Usa Hammer con backend Redis para límites por organización:
- 1000 req/min por org
- Keys en Redis con TTL

## Configuración

```elixir
config :hammer,
  backend: {Hammer.Backend.Redis, [
    expiry_ms: 60_000,
    redis: [host: "redis", port: 6379, password: System.get_env("REDIS_PASSWORD")]
  ]}
```
