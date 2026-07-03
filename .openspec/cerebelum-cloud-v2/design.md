# Design — Cerebelum Cloud

## Developer Journey (Día 1)

```mermaid
graph LR
    A[pip install cerebelum-sdk] --> B[Escribir workflow.py]
    B --> C{Local o Cloud?}
    C -->|Local| D[python workflow.py<br/>sin engine, sin auth]
    C -->|Cloud| E[cerebelum login]
    E --> F[cerebelum deploy workflow.py]
    F --> G[cerebelum run MiWorkflow --input '...']
    G --> H[cerebelum logs exec_id --follow]
```

## Architecture — Cerebelum en ZEA Platform

```mermaid
graph TB
    subgraph "Developer Machine"
        CLI[npx @zea.cl/cerebelum-cli]
        SDK[cerebelum-sdk Python]
    end

    subgraph "ZEA Cloud (docker-compose)"
        CADDY[Caddy :80/:443]
        THAL[Thalamus :4000]
        ZEA[ZEA Platform :4084]
        CER[Cerebelum Engine]
        DB[(PostgreSQL :5432)]
    end

    CLI -->|JWT| CADDY
    SDK -->|JWT| CADDY
    CADDY -->|cerebelum.zea.localhost| CER
    CADDY -->|auth.zea.localhost| THAL
    CER -->|validate JWT| THAL
    CER --> DB
    ZEA --> DB
```

## Components

### 1. JWTAuth Plug (reimplementar sin `Req`)
```elixir
defmodule Cerebelum.API.Plugs.JWTAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- validate_jwt(token) do
      assign(conn, :user_id, claims["sub"])
      |> assign(:organization_id, claims["organization_id"])
    else
      _ -> conn |> put_status(401) |> json(%{error: "unauthorized"}) |> halt()
    end
  end
end
```

### 2. Multi-tenancy
- `organization_id` via `conn.assigns` → `Context.new` → `Engine.Data` → `EventStore`
- Migración: `ALTER TABLE events ADD COLUMN organization_id VARCHAR(255)`
- Queries: `WHERE organization_id = ^org_id`

### 3. Caddy routing
```caddyfile
cerebelum.zea.localhost {
    reverse_proxy cerebelum:4001
}
```

### 4. Docker — cerebelum service
```yaml
cerebelum:
  build: ../cerebelum-core
  environment:
    DATABASE_URL: postgresql://postgres:pass@postgres:5432/cerebelum
    THALAMUS_URL: http://thalamus:4000
    PORT: 4001
```

### 5. `cerebelum init` template
```
my-project/
├── workflow.py        ← template con @step + @workflow
├── requirements.txt   ← cerebelum-sdk
└── README.md          ← quickstart
```

## Testing Strategy
1. Unit: JWTAuth plug, org scoping
2. Integration: Engine con org_id en ZEA docker-compose
3. E2E: `pip install` → `cerebelum deploy` → `cerebelum run` → verificar eventos
