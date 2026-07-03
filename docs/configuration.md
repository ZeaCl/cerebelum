# Configuration

## Using Cerebelum as a Dependency

When adding Cerebelum to your Elixir application:

```elixir
# mix.exs
def deps do
  [{:cerebelum, "~> 0.1.0"}]
end
```

Cerebelum uses your application's Ecto repository. No separate database required.

### Database

```elixir
# config/config.exs
config :cerebelum, Cerebelum.Repo,
  database: "my_app_dev",
  username: "postgres",
  hostname: "localhost",
  pool_size: 10

config :cerebelum, ecto_repos: [Cerebelum.Repo]
```

If using an external database in production:

```elixir
# config/runtime.exs
config :cerebelum, Cerebelum.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))
```

### HTTP API

```elixir
config :cerebelum,
  http_enabled: true,
  http_port: 4001
```

### gRPC Server

```elixir
config :cerebelum,
  enable_grpc_server: true,
  grpc_port: 50051
```

---

## Workflow Resurrection

Cerebelum can resurrect hibernated workflows after system restarts.

```elixir
config :cerebelum,
  enable_workflow_resurrection: true,       # default: true
  resurrection_scan_interval_ms: 30_000,    # default: 30s
  enable_workflow_hibernation: false,       # default: false (safety)
  hibernation_threshold_ms: 3_600_000,      # default: 1 hour
  max_resurrection_attempts: 3              # default: 3
```

---

## Cloud Mode (ZEA Platform)

When running as a managed service, configure via environment variables:

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | Ecto connection string |
| `SECRET_KEY_BASE` | Yes | Phoenix secret key |
| `THALAMUS_URL` | Yes | JWT validation endpoint |
| `PHX_HOST` | No | `cerebelum.zea.cl` |
| `PORT` | No | HTTP port (default: 4001) |
| `GRPC_PORT` | No | gRPC port (default: 50051) |
| `POOL_SIZE` | No | DB connections (default: 10) |
| `CORS_ORIGINS` | No | Allowed origins |

### Rate Limiting

```elixir
config :cerebelum,
  rate_limit_per_minute: 1000   # per organization_id
```

---

## Phoenix Endpoint

```elixir
config :cerebelum, Cerebelum.API.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: Cerebelum.API.ErrorJSON]]

config :phoenix, :json_library, Jason
```
