# Executions API

Create, monitor, and control workflow executions.

---

## List Executions

```http
GET /api/v1/executions
Authorization: Bearer <JWT>
```

### Parameters

| Query | Type | Description |
|---|---|---|
| `status` | string | Filter: `running`, `completed`, `failed` |
| `limit` | integer | Max results (default 50, max 200) |
| `offset` | integer | Pagination offset |

### Response

```json
{
  "executions": [
    {
      "execution_id": "exec_abc123",
      "status": "completed",
      "workflow": "Elixir.OrderWorkflow",
      "events_count": 6
    },
    {
      "execution_id": "exec_def456",
      "status": "running",
      "workflow": "analisis_ventas",
      "events_count": 3
    }
  ],
  "total": 2
}
```

---

## Start Execution

```http
POST /api/v1/executions
Authorization: Bearer <JWT>
Content-Type: application/json
```

### Request

```json
{
  "workflow": "analisis_ventas",
  "input": {
    "periodo": "Q4-2025",
    "region": "LATAM"
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `workflow` | string | **Yes** | Workflow name (Elixir module or blueprint name) |
| `input` | object | No | Initial inputs for the workflow |

### Response

```http
HTTP/1.1 201 Created
```

```json
{
  "data": {
    "id": "exec_abc123",
    "status": "started",
    "workflow": "analisis_ventas"
  }
}
```

### Error Codes

| Status | Error | Description |
|---|---|---|
| 404 | `workflow_not_found` | Workflow not registered |
| 500 | `execution_failed` | Engine failed to start |

---

## Get Execution Status

```http
GET /api/v1/executions/:id
Authorization: Bearer <JWT>
```

### Response (running)

```json
{
  "execution_id": "exec_abc123",
  "state": "executing_step",
  "progress": "2/5",
  "current_step": "process_payment",
  "results": {
    "validate_order": {"id": "ORD-1", "valid": true},
    "check_inventory": {"available": true}
  },
  "error": null
}
```

### Response (completed)

```json
{
  "execution_id": "exec_abc123",
  "state": "completed",
  "results": {
    "validate_order": {"id": "ORD-1", "valid": true},
    "check_inventory": {"available": true},
    "process_payment": {"amount": 1500, "status": "paid"},
    "ship_order": {"tracking": "TRACK-123456"},
    "notify_customer": {"sent": true}
  }
}
```

### Response (not found)

```http
HTTP/1.1 404 Not Found
```

```json
{
  "error": "not_found",
  "message": "Execution exec_abc123 not found"
}
```

---

## Get Execution Events

Returns the full event sourcing audit trail for an execution.

```http
GET /api/v1/executions/:id/events
Authorization: Bearer <JWT>
```

### Response

```json
{
  "execution_id": "exec_abc123",
  "events": [
    {
      "version": 1,
      "type": "ExecutionStartedEvent",
      "data": {
        "workflow_module": "analisis_ventas",
        "workflow_version": "abc123...",
        "inputs": {"periodo": "Q4-2025"}
      },
      "timestamp": "2026-07-09T14:15:00Z"
    },
    {
      "version": 2,
      "type": "StepExecutedEvent",
      "data": {
        "step_name": "obtener_datos",
        "result": {"usuarios": 1250, "ventas": 34500000}
      },
      "timestamp": "2026-07-09T14:15:01Z"
    },
    {
      "version": 3,
      "type": "ExecutionCompletedEvent",
      "data": {},
      "timestamp": "2026-07-09T14:15:05Z"
    }
  ],
  "count": 3
}
```

---

## Stop Execution

```http
POST /api/v1/executions/:id/stop
Authorization: Bearer <JWT>
```

### Response

```json
{
  "execution_id": "exec_abc123",
  "status": "stopped"
}
```

### Error

```http
HTTP/1.1 404 Not Found
```

```json
{
  "error": "not_found"
}
```

---

## Resume Execution

Resumes a paused or hibernated execution.

```http
POST /api/v1/executions/:id/resume
Authorization: Bearer <JWT>
```

### Response

```json
{
  "execution_id": "exec_abc123",
  "status": "resumed"
}
```

### Error

```http
HTTP/1.1 422 Unprocessable Entity
```

```json
{
  "error": "already_running"
}
```

---

## Approve Step (Human-in-the-Loop)

Approves a workflow step waiting for human input.

```http
POST /api/v1/executions/:id/approve
Authorization: Bearer <JWT>
Content-Type: application/json
```

### Request

```json
{
  "approved_by": "Alice",
  "notes": "Looks good, proceed"
}
```

### Response

```json
{
  "execution_id": "exec_abc123",
  "status": "approved"
}
```

---

## cURL Examples

```bash
# Start a workflow
curl -X POST https://cerebelum.zea.cl/api/v1/executions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"workflow": "analisis_ventas", "input": {"periodo": "Q4"}}'

# Check status
curl https://cerebelum.zea.cl/api/v1/executions/exec_abc123 \
  -H "Authorization: Bearer $TOKEN"

# View audit trail
curl https://cerebelum.zea.cl/api/v1/executions/exec_abc123/events \
  -H "Authorization: Bearer $TOKEN"

# Stop execution
curl -X POST https://cerebelum.zea.cl/api/v1/executions/exec_abc123/stop \
  -H "Authorization: Bearer $TOKEN"
```

---

## See Also

- [Workflows API](workflows.md) — Deploy and list workflows
- [Events API](events.md) — Event sourcing deep dive
- [REST API Overview](rest.md) — Auth, pagination, rate limits
