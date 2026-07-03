# Design — Cerebelum Cloud

## Overview
Cerebelum Cloud extiende el engine on-premise con: capa de auth (Thalamus JWT), multi-tenancy (organization_id), SDKs públicos, y deploy cloud. La arquitectura sigue el patrón Thalamus — un servicio Elixir/Phoenix con JWT auth, organizaciones como tenant boundary, y SDKs multi-lenguaje.

## Architecture

```mermaid
graph TB
    subgraph "Developer Machine"
        DEV[Developer]
        CLI[CLI: npx cerebelum]
        SDK_PY[Python SDK]
        SDK_TS[TypeScript SDK]
    end

    subgraph "ZEA Cloud"
        THAL[Thalamus<br/>OAuth2 + JWT]
        CER[Cerebelum Engine]
        API[REST API :4001]
        GRPC[gRPC :50051]
        DB[(PostgreSQL)]
    end

    DEV -->|1. login| THAL
    THAL -->|2. JWT| DEV
    DEV -->|3. JWT Bearer| API
    DEV -->|3. JWT Bearer| GRPC
    CLI -->|JWT| API
    SDK_PY -->|JWT| GRPC
    SDK_TS -->|JWT| API
    API -->|validate JWT| THAL
    GRPC -->|validate JWT| THAL
    API --> CER
    GRPC --> CER
    CER --> DB
```

## Multi-Tenancy Flow

```mermaid
sequenceDiagram
    participant D as Developer
    participant T as Thalamus
    participant C as Cerebelum API
    participant E as Engine
    participant DB as PostgreSQL

    D->>T: POST /oauth/token
    T-->>D: JWT {sub, org_id, scopes}
    D->>C: POST /api/v1/executions<br/>Authorization: Bearer <JWT>
    C->>T: GET /.well-known/jwks.json
    T-->>C: JWKS
    C->>C: validate JWT signature
    C->>C: extract org_id = "org_123"
    C->>E: execute_workflow(org_id: "org_123", ...)
    E->>DB: INSERT events WITH org_id = "org_123"
    D->>C: GET /api/v1/executions
    C->>DB: SELECT WHERE org_id = "org_123"
    DB-->>C: only org_123's executions
```

## Data Models

```mermaid
erDiagram
    Organization {
        string id PK
        string name
        datetime created_at
    }
    Workflow {
        string id PK
        string org_id FK
        string name
        json definition
        string language
    }
    Execution {
        string id PK
        string org_id FK
        string workflow_id FK
        string status
        json inputs
        json results
    }
    Event {
        string id PK
        string execution_id FK
        string org_id FK
        string event_type
        json event_data
        int version
    }
    Organization ||--o{ Workflow : owns
    Organization ||--o{ Execution : scopes
    Execution ||--o{ Event : contains
```

## Components

### 1. JWTAuth Plug (existente, adaptar)
- Ya existe `Cerebelum.API.Plugs.JWTAuth` (requiere `Req` para JWKS)
- Reemplazar `Req` con `Finch` o `Tesla` (ya están en deps)
- Validar firma JWT contra Thalamus JWKS
- Extraer `organization_id` y guardarlo en `conn.assigns`

### 2. Organization Scoping
- Agregar `organization_id` a Context, Data, Event schemas
- Migración: `ALTER TABLE events ADD COLUMN organization_id`
- Todos los queries agregan `WHERE organization_id = ^org_id`

### 3. SDK Publishing
- Python: `pyproject.toml` ya existe → `pip publish`
- TypeScript: `package.json` ya existe → `npm publish`
- Ambos auto-publican en CI/CD con GitHub Actions

### 4. CLI Installable
- El CLI TypeScript se publica como `@zea.cl/cerebelum-cli` en npm
- `npx @zea.cl/cerebelum-cli` o `npm i -g @zea.cl/cerebelum-cli`
- Soporta `CEREBELUM_URL` y `CEREBELUM_TOKEN` env vars

## Error Handling

```
401 Unauthorized → JWT inválido o expirado
403 Forbidden    → Organización no autorizada  
429 Too Many     → Rate limit excedido
503 Unavailable  → Database o gRPC caído
```

## Testing Strategy
1. **Unit**: JWTAuth plug, organization scoping queries
2. **Integration**: Engine con org_id, eventos scoped
3. **E2E**: SDK Python → gRPC con JWT → workflow completado
4. **Load**: Rate limiting con 1000+ req/min
