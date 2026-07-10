# CLI Reference

The `cerebelum` CLI is the primary interface for cloud mode. It handles auth, deployment, execution, and monitoring.

---

## Installation

```bash
npm install -g @zea.cl/cerebelum-cli
```

---

## Commands

### Authentication

| Command | Description |
|---|---|
| `cerebelum login` | Authenticate with Thalamus (OAuth2 PKCE) |
| `cerebelum login --token <jwt>` | Authenticate with existing JWT |

```bash
# Interactive login (opens browser)
cerebelum login

# Login with existing token
cerebelum login --token "eyJhbGci..."
```

Auth state is stored in `~/.cerebelum/` and reused across commands.

---

### Workflow Management

| Command | Description |
|---|---|
| `cerebelum deploy <file>` | Deploy workflow blueprint to engine |
| `cerebelum workflow list` | List all registered workflows |
| `cerebelum workflow show <id>` | Show workflow details |
| `cerebelum workflow run <module> [--inputs '{...}']` | Execute a deployed workflow |

```bash
# Deploy from local file
cerebelum deploy workflow.py

# List available workflows
cerebelum workflow list

# Show details
cerebelum workflow show analisis_ventas

# Execute with inputs
cerebelum workflow run analisis_ventas --inputs '{"periodo": "Q4-2025"}'

# Same as:
cerebelum run workflow.py
```

---

### Execution

| Command | Description |
|---|---|
| `cerebelum run <module>` | Smart run: resolve everything + execute |
| `cerebelum run <file>` | Run from local file (auto-deploy + execute) |
| `cerebelum execution status <id>` | Get execution status |
| `cerebelum execution events <id>` | Get event timeline (audit trail) |
| `cerebelum execution stop <id>` | Stop running execution |
| `cerebelum execution resume <id>` | Resume paused execution |
| `cerebelum execution approve <id> [--response '{...}']` | Approve HITL step |

```bash
# Smart run — handles login, certs, deploy, worker, execute
cerebelum run workflow.py

# Run with custom inputs
cerebelum run workflow.py --inputs '{"user_id": 42}'

# Check execution status
cerebelum execution status exec_abc123

# View event timeline
cerebelum execution events exec_abc123

# Stop a running execution
cerebelum execution stop exec_abc123
```

---

### Logs

| Command | Description |
|---|---|
| `cerebelum logs <id>` | Get execution logs |
| `cerebelum logs <id> --follow` | Stream logs in real-time |
| `cerebelum logs` | Show logs for last execution |

```bash
# Get logs for specific execution
cerebelum logs exec_abc123

# Follow logs live (Ctrl+C to stop)
cerebelum logs exec_abc123 --follow

# Get logs for last execution
cerebelum logs
```

---

### Monitoring

| Command | Description |
|---|---|
| `cerebelum status` | Show overall system status |
| `cerebelum worker list` | List registered Python/TypeScript workers |
| `cerebelum doctor` | Run health checks |

```bash
# Full system status
cerebelum status

# List active workers
cerebelum worker list

# Run health checks
cerebelum doctor
```

---

## Smart Run Flow

`cerebelum run workflow.py` executes a complete checklist:

```
🧠 Cerebelum Run

  ✅ Login — JWT presente
  ✅ Certs — mTLS listos
  ✅ Blueprint — analisis_ventas v0.1.0
  ✅ Worker — python -m cerebelum.worker (PID 20727)

  🚀 analisis_ventas
  [14:15:02] ExecutionStarted
  [14:15:03] StepExecuted [obtener_datos] → usuarios=1250, ventas=34500000
  [14:15:04] StepExecuted [procesar_datos] → ticket_promedio=27600
  [14:15:05] StepExecuted [notificar] → slack#general
  [14:15:05] ExecutionCompleted ✅

  ⏱️ 7.4s
```

| Step | What happens |
|---|---|
| 1. Login | Checks `~/.cerebelum/token`, runs OAuth2 PKCE if missing |
| 2. Certs | `POST /api/v1/dev-certs`, generates mTLS client cert |
| 3. Blueprint | `POST /api/v1/workflows/deploy` (only if code changed) |
| 4. Worker | Starts `python -m cerebelum.worker` (or TS equivalent) |
| 5. Execute | `POST /api/v1/executions` |
| 6. Logs | Streams events in real-time |

---

## Global Options

| Option | Description |
|---|---|
| `--json` | Machine-readable JSON output |
| `--follow`, `-f` | Follow logs in real-time |
| `--token <token>` | API token for login |
| `--inputs '{...}'` | JSON workflow inputs |
| `--help` | Show help |

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CEREBELUM_API_URL` | `https://cerebelum.zea.cl` | API base URL |
| `CEREBELUM_API_KEY` | — | API key for auth |

---

## Examples

```bash
# Full workflow: edit → run → check
vim workflow.py
cerebelum run workflow.py
cerebelum status

# Debug a failed execution
cerebelum execution status exec_abc123
cerebelum execution events exec_abc123

# CI/CD: deploy and execute
cerebelum deploy workflow.py
EXEC_ID=$(cerebelum workflow run my_workflow --json | jq -r '.execution_id')
cerebelum execution status $EXEC_ID
```

---

## See Also

- [Getting Started](../getting-started.md) — First workflow walkthrough
- [REST API](../api/rest.md) — Direct API access
- [Deployment](../deployment.md) — Production setup
