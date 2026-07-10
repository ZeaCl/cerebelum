# Thalamus Integration

Cerebelum integrates with [Thalamus](https://github.com/ZeaCl/thalamus) — ZEA's OAuth2 / OpenID Connect identity provider — for authentication, authorization, and multi-tenancy.

---

## Integration Points

```
┌──────────────┐                    ┌──────────────────┐
│  Cerebelum   │                    │     Thalamus     │
│              │                    │                  │
│  ┌────────┐  │  ① JWT Validation │  ┌────────────┐ │
│  │JwtAuth │──┼──────────────────→│  │  JWKS       │ │
│  │ Plug   │  │←── public keys ──│  │  /.well-known│ │
│  └────────┘  │                    │  └────────────┘ │
│              │                    │                  │
│  ┌────────┐  │  ② Step Auth      │  ┌────────────┐ │
│  │Engine  │──┼──────────────────→│  │  validate-  │ │
│  │        │  │←── authorized? ──│  │  step       │ │
│  └────────┘  │                    │  └────────────┘ │
│              │                    │                  │
│  ┌────────┐  │  ③ Agent Tokens   │  ┌────────────┐ │
│  │Worker  │──┼──────────────────→│  │  /oauth/    │ │
│  │Auth    │  │                    │  │  agent-token│ │
│  └────────┘  │                    │  └────────────┘ │
└──────────────┘                    └──────────────────┘
```

| # | Integration | Purpose |
|---|---|---|
| ① | **JWT Validation** | Authenticate API requests |
| ② | **Step Authorization** | Validate agent scopes per step |
| ③ | **Agent Tokens** | AI agents acting on user behalf |

---

## ① JWT Validation

### How It Works

Every authenticated Cerebelum API request includes a JWT from Thalamus:

```bash
curl -H "Authorization: Bearer <JWT>" \
  https://cerebelum.zea.cl/api/v1/executions
```

The `JwtAuth` plug:

1. Extracts the Bearer token from `Authorization` header
2. Validates JWT signature against Thalamus JWKS (`/.well-known/jwks.json`)
3. Extracts claims: `user_id`, `organization_id`, `scopes`
4. Attaches claims to `conn.assigns` for controller use

### Configuration

```elixir
# config/runtime.exs
config :cerebelum,
  thalamus_url: System.get_env("THALAMUS_URL", "http://thalamus:4000")
```

```elixir
# config/config.exs
config :cerebelum, Cerebelum.API.Plugs.JWTAuth,
  issuer: "thalamus",
  allowed_algorithms: ["RS256", "ES256"]
```

### Required JWT Claims

| Claim | Required | Description |
|---|---|---|
| `sub` | **Yes** | User ID |
| `organization_id` | **Yes** (cloud) | Multi-tenant scope |
| `scope` | No | OAuth2 scopes |
| `exp` | **Yes** | Expiration (validated automatically) |

---

## ② Step Authorization (Agent Tokens)

For AI agent workflows, Cerebelum validates each step's permissions against Thalamus:

### Flow

```
1. Agent obtains token from Thalamus
   POST /oauth/agent-token
   → { access_token: "at_xxx", scopes: ["email:send", "data:read"] }

2. Cerebelum receives workflow execution request with agent token

3. Before each step, Cerebelum calls Thalamus:
   POST /api/authorization/validate-step
   Authorization: Bearer at_xxx
   Body: { "step_name": "notify", "required_scopes": ["email:send"] }

4. Thalamus validates:
   ✓ Token not expired
   ✓ Token not revoked
   ✓ Token has required scopes
   → { authorized: true }

5. Cerebelum executes the step
```

### Implementation in Engine

The engine calls step authorization before executing each distributed step:

```elixir
# Internal: step authorization check
case validate_step(token, step_name, required_scopes) do
  {:ok, :authorized} ->
    execute_step(step, context)

  {:error, :insufficient_scopes} ->
    emit_event(%StepAuthorizationDenied{...})
    {:error, :unauthorized}
end
```

### Agent Token Details

See [Thalamus Agent Tokens docs](https://github.com/ZeaCl/thalamus/docs/agents/overview.md):

- **Token types**: `autonomous`, `supervisor`, `tool`
- **Delegation chains**: Up to 4 levels deep
- **Task scoping**: Scoped to specific task + duration
- **Compliance**: EU AI Act-ready audit trails

---

## ③ Agent Token Flow

### M2M Agent Token (Standard)

```bash
curl -X POST https://auth.zea.cl/oauth/agent-token \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "client_xxx",
    "client_secret": "secret_xxx",
    "organization_id": "org_abc123",
    "delegator_user_id": "user_xyz789",
    "agent_type": "autonomous",
    "task_description": "Analyze Q4 sales data",
    "scope": "data:read report:generate"
  }'
```

### Internal Agent Token (Microservices)

```bash
# Called from within internal network (no auth required)
curl -X POST http://thalamus:4000/api/internal/agent-token \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user_xyz789",
    "scopes": ["venture:read", "venture:write"],
    "organization_id": "org_abc123"
  }'
```

Returns a short-lived Personal Access Token scoped to the user.

---

## Example: End-to-End Agent Workflow

```bash
# 1. Agent gets token
AGENT_TOKEN=$(curl -s -X POST https://auth.zea.cl/oauth/agent-token \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "cerebelum_agent",
    "client_secret": "secret",
    "organization_id": "org_abc",
    "delegator_user_id": "user_xyz",
    "agent_type": "autonomous",
    "task_description": "Generate weekly report",
    "scope": "data:read email:send"
  }' | jq -r '.access_token')

# 2. Execute workflow with agent token
EXEC_ID=$(curl -s -X POST https://cerebelum.zea.cl/api/v1/executions \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"workflow": "weekly_report", "input": {"week": 27}}' \
  | jq -r '.data.id')

# 3. Check events for authorization audit
curl https://cerebelum.zea.cl/api/v1/executions/$EXEC_ID/events \
  -H "Authorization: Bearer $AGENT_TOKEN"
```

---

## See Also

- [Thalamus Documentation](https://github.com/ZeaCl/thalamus/docs/index.md) — Full auth service docs
- [Thalamus Agent Overview](https://github.com/ZeaCl/thalamus/docs/agents/overview.md) — Agent token details
- [REST API Overview](../api/rest.md) — Cerebelum auth endpoints
- [Architecture Overview](../architecture/overview.md) — JwtAuth plug in the system
