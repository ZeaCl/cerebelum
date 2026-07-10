# REST API — Overview

Cerebelum exposes a REST API for executing workflows, querying state, deploying blueprints, and managing workers.

---

## Base URL

| Environment | URL |
|---|---|
| ZEA Cloud | `https://cerebelum.zea.cl` |
| Local / Docker | `http://localhost:4001` |

---

## Authentication

All authenticated endpoints require a JWT Bearer token issued by Thalamus:

```bash
curl -H "Authorization: Bearer <JWT_TOKEN>" \
  https://cerebelum.zea.cl/api/v1/executions
```

Token requirements:
- Issued by Thalamus (`auth.zea.cl`)
- Contains `organization_id` claim for multi-tenant scoping
- Contains appropriate scopes (`workflows:read`, `workflows:write`)

### Public Endpoints (no auth)

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Health check |
| `GET` | `/api/v1/workflows` | List workflows |
| `GET` | `/api/v1/workflows/:id` | Get workflow metadata |
| `GET` | `/api/v1/workflows/:id/code` | Get workflow source |

### Internal Endpoints (no auth, intra-network only)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/internal/workers/register` | Worker registration |

### Authenticated Endpoints (JWT required)

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/v1/workflows/deploy` | Deploy blueprint |
| `GET` | `/api/v1/executions` | List executions |
| `POST` | `/api/v1/executions` | Start execution |
| `GET` | `/api/v1/executions/:id` | Get execution status |
| `GET` | `/api/v1/executions/:id/events` | Get execution events |
| `POST` | `/api/v1/executions/:id/stop` | Stop execution |
| `POST` | `/api/v1/executions/:id/resume` | Resume execution |
| `POST` | `/api/v1/executions/:id/approve` | Approve HITL step |
| `GET` | `/api/v1/workers` | List workers |
| `POST` | `/api/v1/dev-certs` | Generate dev mTLS certs |

---

## Rate Limiting

Rate limits are applied per `organization_id`:

| Pipeline | Limit |
|---|---|
| Authenticated API | 1000 req/min per org |
| Dev Certs | 5 req/min per user |

Exceeding limits returns:

```json
HTTP/1.1 429 Too Many Requests
{
  "error": "rate_limit_exceeded",
  "message": "Too many requests"
}
```

---

## Response Format

All responses are JSON:

```json
// Success
{
  "execution_id": "exec_abc123",
  "status": "started",
  "workflow": "analisis_ventas"
}

// Error
{
  "error": "workflow_not_found",
  "message": "Workflow 'nonexistent' not registered"
}
```

---

## Pagination

List endpoints support pagination via query parameters:

```bash
GET /api/v1/executions?limit=50&offset=0
```

| Parameter | Default | Max |
|---|---|---|
| `limit` | 50 | 200 |
| `offset` | 0 | — |

---

## Health Check

```bash
curl https://cerebelum.zea.cl/health
```

```json
{
  "status": "ok",
  "timestamp": "2026-07-09T14:15:00Z",
  "version": "0.1.0",
  "services": {
    "database": "ok",
    "grpc": "running"
  }
}
```

---

## See Also

- [Executions API](executions.md) — Create, query, stop, resume workflows
- [Workflows API](workflows.md) — List, deploy, source code
- [Workers API](workers.md) — Register and list workers
- [Events API](events.md) — Query the event sourcing audit trail
