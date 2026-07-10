# Workflows API

List, inspect, and deploy workflow definitions (blueprints).

---

## List Workflows

Returns all registered workflows: Elixir-native, Python workers, and deployed blueprints.

```http
GET /api/v1/workflows
```

No authentication required.

### Response

```json
{
  "data": [
    {
      "id": "Elixir.OrderWorkflow",
      "label": "Order Workflow",
      "version": "abc123def456...",
      "steps": [],
      "language": "elixir"
    },
    {
      "id": "worker-1/fetch_data",
      "label": "fetch_data",
      "version": "0.1.0",
      "steps": ["fetch_data"],
      "language": "python",
      "worker_id": "worker-1"
    },
    {
      "id": "analisis_ventas",
      "label": "analisis_ventas",
      "version": "0.1.0",
      "steps": ["obtener_datos", "procesar_datos", "notificar"],
      "language": "python"
    }
  ]
}
```

### Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique workflow identifier |
| `label` | string | Human-readable name |
| `version` | string | Version hash or number |
| `steps` | string[] | Step names |
| `language` | string | `elixir`, `python`, `typescript` |
| `worker_id` | string | Worker ID (Python/TypeScript workers only) |

---

## Get Workflow

```http
GET /api/v1/workflows/:id
```

Returns metadata for a specific workflow found in the worker registry.

### Response

```json
{
  "data": {
    "id": "fetch_data",
    "name": "fetch_data",
    "label": "fetch_data",
    "version": "0.1.0",
    "steps": ["fetch_data"],
    "language": "python",
    "worker_id": "worker-1"
  }
}
```

### Error

```http
HTTP/1.1 404 Not Found
```

```json
{
  "error": "Workflow not found"
}
```

---

## Get Workflow Source Code

```http
GET /api/v1/workflows/:id/code
```

> **Note**: Source code retrieval is not available in production. Returns 404.

---

## Deploy Workflow

Deploy a workflow blueprint (Python code) that can be executed via the API.

```http
POST /api/v1/workflows/deploy
Authorization: Bearer <JWT>
Content-Type: application/json
```

### Request

```json
{
  "name": "analisis_ventas",
  "module": "Elixir.AnalisisVentas",
  "code": "from cerebelum import step, workflow\n...",
  "language": "python"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | **Yes** | Workflow identifier |
| `module` | string | No | Elixir module name (for routing) |
| `code` | string | **Yes** | Python source code |
| `language` | string | No | `python` (default) |

### Response

```http
HTTP/1.1 201 Created
```

```json
{
  "data": {
    "id": "analisis_ventas",
    "name": "analisis_ventas",
    "language": "python",
    "steps": ["obtener_datos", "procesar_datos", "notificar"]
  }
}
```

### Error Codes

| Status | Error | Description |
|---|---|---|
| 400 | `Missing 'name' field` | Name is required |
| 400 | `Missing 'code' field` | Source code is required |

---

## Step Extraction

On deploy, Cerebelum scans the Python code for `@step`-decorated functions to build the step list:

```python
@step
async def obtener_datos(context, **kwargs):  # ← detected
    ...

@step
async def procesar(context, **kwargs):       # ← detected
    ...
```

---

## cURL Examples

```bash
# List all workflows
curl https://cerebelum.zea.cl/api/v1/workflows

# Deploy a Python workflow
curl -X POST https://cerebelum.zea.cl/api/v1/workflows/deploy \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mi_workflow",
    "language": "python",
    "code": "from cerebelum import step, workflow\n\n@step\nasync def hello(ctx, **kwargs):\n    return {\"message\": \"Hello\"}\n\n@workflow\ndef main(wf):\n    wf.timeline(hello)\n"
  }'
```

---

## See Also

- [Executions API](executions.md) — Execute deployed workflows
- [REST API Overview](rest.md) — Auth, pagination, rate limits
