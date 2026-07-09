# Workers API

Register and list Python/TypeScript workers that execute distributed workflow steps via gRPC.

---

## Register Worker

Called by worker processes on startup. **No JWT required** — internal endpoint only.

```http
POST /api/internal/workers/register
Content-Type: application/json
```

### Request

```json
{
  "worker_id": "worker-1",
  "url": "http://worker-host:9000",
  "workflows": ["fetch_data", "process_payment", "send_email"]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `worker_id` | string | **Yes** | Unique worker identifier |
| `url` | string | **Yes** | Worker gRPC callback URL |
| `workflows` | string[] | No | Step capabilities this worker can execute |

### Response

```json
{
  "ok": true
}
```

### Error

```http
HTTP/1.1 500 Internal Server Error
```

```json
{
  "error": "worker_already_registered"
}
```

### Worker Lifecycle

1. Worker starts → calls `POST /api/internal/workers/register`
2. Cerebelum stores worker in `WorkerRegistry` (ETS table)
3. When a distributed step needs execution → `TaskRouter` sends work to `worker_url`
4. Worker processes step → returns result via gRPC
5. Worker stops → removed from registry after heartbeat timeout

---

## List Workers

```http
GET /api/v1/workers
Authorization: Bearer <JWT>
```

### Response

```json
{
  "data": [
    {
      "worker_id": "worker-1",
      "url": "http://worker-host:9000",
      "capabilities": ["fetch_data", "process_payment"],
      "language": "python",
      "version": "0.1.0",
      "registered_at": "2026-07-09T14:15:00Z"
    }
  ]
}
```

### Fields

| Field | Type | Description |
|---|---|---|
| `worker_id` | string | Worker identifier |
| `url` | string | gRPC endpoint |
| `capabilities` | string[] | Steps this worker can execute |
| `language` | string | `python` or `typescript` |
| `version` | string | Worker version |
| `registered_at` | string | ISO 8601 timestamp |

---

## Dev Certificates

Generate client certificates for worker mTLS. Idempotent — same user always gets the same certificate.

```http
POST /api/v1/dev-certs
Authorization: Bearer <JWT>
```

### Response

```json
{
  "ca_crt": "-----BEGIN CERTIFICATE-----\n...",
  "client_crt": "-----BEGIN CERTIFICATE-----\n...",
  "client_key": "-----BEGIN RSA PRIVATE KEY-----\n..."
}
```

### Details

- Certificate signed by engine's CA (`priv/certs/ca.crt`)
- 4096-bit RSA key
- 365-day validity
- CN based on SHA256 hash of `user_id` (idempotent)
- Rate limited: 5 requests per minute per user

### Error

```http
HTTP/1.1 503 Service Unavailable
```

```json
{
  "error": "certs_not_available"
}
```

---

## cURL Examples

```bash
# Register a worker (internal)
curl -X POST http://cerebelum:4001/api/internal/workers/register \
  -H "Content-Type: application/json" \
  -d '{"worker_id": "worker-1", "url": "http://worker:9000", "workflows": ["fetch_data"]}'

# List workers
curl https://cerebelum.zea.cl/api/v1/workers \
  -H "Authorization: Bearer $TOKEN"

# Generate dev certs
curl -X POST https://cerebelum.zea.cl/api/v1/dev-certs \
  -H "Authorization: Bearer $TOKEN"
```

---

## See Also

- [Executions API](executions.md) — Execute workflows with distributed workers
- [REST API Overview](rest.md) — Auth, pagination, rate limits
