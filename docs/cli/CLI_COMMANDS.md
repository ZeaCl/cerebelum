# ZEA Cerebelum CLI — Command Reference

> **Status**: v1.0.0 — 100% API coverage
> **Última actualización**: 2025-07-24

---

## Arquitectura

Cerebelum CLI sigue el patrón `zea <servicio> <recurso> <verbo>`, alineado con
el ecosistema ZEA. La autenticación se delega a **Thalamus (IAM única)** —
no tiene login propio. Usa el token del shared config `~/.config/zea/config.json`.

```
zea cerebelum
├── config           Configuración local
├── health           Health check (público)
├── doctor           Diagnóstico completo
├── workflow         list | show | code | run
├── deploy           Desplegar blueprint
├── execution        list | status | events | stop | resume | approve
├── worker           list
├── logs             Stream de eventos
├── dev-certs        create | status
└── run              Flujo local end-to-end
```

---

## 1. Configuración

### `config set-env <local|prod>`

Configura URLs de todos los servicios para desarrollo local o producción.

```bash
zea cerebelum config set-env local   # → http://cerebelum.zea.localhost
zea cerebelum config set-env prod    # → https://cerebelum.zea.cl
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 1.1 | `set-env local` | `✅ Cerebelum environment set to LOCAL` | 0 |
| 1.2 | `set-env prod` | `✅ Cerebelum environment set to PROD` | 0 |
| 1.3 | `set-env invalid` | `Unknown environment. Use "local" or "prod".` | 0 |

### `config set|get|list|unset|path`

```bash
zea cerebelum config set cerebelumUrl http://localhost:4000
zea cerebelum config get cerebelumUrl
zea cerebelum config list
zea cerebelum config unset cerebelumUrl
zea cerebelum config path
```

| # | Expected Output | Exit |
|---|---|---|
| 1.4 | `list` — muestra todas las keys, token enmascarado `••••abcd` | 0 |
| 1.5 | `path` — `/Users/.../.config/zea/config.json` | 0 |

---

## 2. Health & Doctor

### `health`

```bash
zea cerebelum health
zea cerebelum health --output json
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 2.1 | Cerebelum OK | `🧠 Cerebelum 0.1.0 | Status: ✅ OK | Database: ✅ ok | gRPC: ✅ ok` | 0 |
| 2.2 | Cerebelum caído | `❌ Cannot reach Cerebelum at ...` | 1 |
| 2.3 | `--output json` | `{"status":"ok","version":"0.1.0","services":{"database":"ok","grpc":"ok"}}` | 0 |

### `doctor`

```bash
zea cerebelum doctor
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 2.4 | Todo OK | `✅ 5  ⚠️ 0  ❌ 0  (5 checks)  🎉 All systems operational!` | 0 |
| 2.5 | Sin token | `⚠️ No token found  💡 Run: zea login` | 0 |
| 2.6 | Sin workflows | `✅ 0 workflows registered` | 0 |

---

## 3. Workflows

### `workflow list`

```bash
zea cerebelum workflow list
zea cerebelum workflow list --output json
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 3.1 | 2+ workflows | Tabla: name, version, steps, language | 0 |
| 3.2 | 0 workflows | `No workflows registered. Deploy one: zea cerebelum deploy workflow.py` | 0 |

### `workflow show <id>`

```bash
zea cerebelum workflow show mi_workflow
zea cerebelum workflow show mi_workflow --output json
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 3.3 | Existe | ID, version, worker, steps con nombres | 0 |
| 3.4 | No existe | `❌ Workflow not found: xyz` | 1 |

### `workflow code <id>`

```bash
zea cerebelum workflow code mi_workflow
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 3.5 | Existe con código | Source code del blueprint | 0 |
| 3.6 | No disponible | `⚠️ Source code not available` | 0 |

### `workflow run <module>`

```bash
zea cerebelum workflow run mi_workflow
zea cerebelum workflow run mi_workflow --inputs '{"name":"ZEA","limit":10}'
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 3.7 | Workflow existe | `✅ Workflow started! ID: exec_abc... Status: started` | 0 |
| 3.8 | Workflow no existe | `❌ workflow_not_found` | 1 |
| 3.9 | JSON inputs inválido | `❌ Invalid JSON inputs: ...` | 1 |

---

## 4. Deploy

### `deploy <file>`

```bash
zea cerebelum deploy workflow.py
zea cerebelum deploy workflow.py --name custom-name
zea cerebelum deploy workflow.py --dry-run
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 4.1 | Archivo válido | `✅ Blueprint deployed! Workflow: mi_workflow` | 0 |
| 4.2 | Archivo no existe | `❌ File not found: xyz.py` | 1 |
| 4.3 | Dry-run | `⚠️ DRY RUN — would deploy: POST ... Name: mi_workflow (1234 bytes)` | 0 |

---

## 5. Executions

### `execution list`

```bash
zea cerebelum execution list
zea cerebelum execution list --status running
zea cerebelum execution list --workflow mi_workflow --limit 10
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 5.1 | Hay ejecuciones | Tabla: status, workflow, events count | 0 |
| 5.2 | Sin ejecuciones | `No executions found.` | 0 |
| 5.3 | Filtro por status | Solo ejecuciones con ese status | 0 |

### `execution status <id>`

```bash
zea cerebelum execution status exec_abc123
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 5.4 | Existe | Status, workflow, step actual, progress, duración | 0 |
| 5.5 | No existe | `❌ Execution not found` | 1 |
| 5.6 | Waiting for approval | `⏸️ Waiting for human approval` + comando approve | 0 |

### `execution events <id>`

```bash
zea cerebelum execution events exec_abc123
```

| # | Expected Output | Exit |
|---|---|---|
| 5.7 | Timeline con N eventos: version, type, timestamp, data | 0 |

### `execution stop|resume <id>`

```bash
zea cerebelum execution stop exec_abc123
zea cerebelum execution resume exec_abc123
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 5.8 | Stop OK | `✅ Execution stopped` | 0 |
| 5.9 | Resume OK | `✅ Execution resumed: running` | 0 |
| 5.10 | Ya running | `⚠️ Already running` | 0 |

### `execution approve <id>`

```bash
zea cerebelum execution approve exec_abc123
zea cerebelum execution approve exec_abc123 --response '{"decision":"approved","comment":"LGTM"}'
```

| # | Expected Output | Exit |
|---|---|---|
| 5.11 | Approved | `✅ Approved — status: resumed` | 0 |

---

## 6. Workers

### `worker list`

```bash
zea cerebelum worker list
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 6.1 | 1+ workers | Tabla: worker_id, url, workflows | 0 |
| 6.2 | 0 workers | `No Python workers registered (Elixir-native only).` | 0 |

---

## 7. Logs

### `logs <id> [--follow]`

```bash
zea cerebelum logs exec_abc123
zea cerebelum logs exec_abc123 --follow
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 7.1 | Ejecución completada | Timeline con timestamps y resultados de cada step | 0 |
| 7.2 | `--follow` | Streaming en tiempo real, termina en `ExecutionCompleted ✅` | 0 |
| 7.3 | No existe | `❌ Execution not found` | 1 |

---

## 8. Dev Certs

### `dev-certs create`

```bash
zea cerebelum dev-certs create
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 8.1 | Auth OK | `✅ mTLS certificates generated! Saved to: ~/.cerebelum/certs` | 0 |
| 8.2 | Sin auth | `❌ Not authenticated. Run: zea login` | 1 |

### `dev-certs status`

```bash
zea cerebelum dev-certs status
```

| # | Expected Output | Exit |
|---|---|---|
| 8.3 | Certs OK | `✅ mTLS certificates ready` | 0 |
| 8.4 | Faltan certs | `❌ mTLS certificates missing | Missing: ca.crt, client.crt, client.key` | 0 |

---

## 9. Run (local end-to-end)

### `run [file]`

```bash
zea cerebelum run
zea cerebelum run workflow.py --inputs '{"user_id":42}'
zea cerebelum run workflow.py --no-follow
```

| # | Caso | Expected Output | Exit |
|---|---|---|---|
| 9.1 | workflow.py en cwd | Auth ✅ → Deploy ✅ → Execute 🚀 → Logs stream → `ExecutionCompleted ✅ ⏱️ 3.2s` | 0 |
| 9.2 | Archivo no existe | `❌ File not found: xyz.py` | 1 |
| 9.3 | Sin auth | `❌ Auth — no autenticado | Run: zea login` | 1 |
| 9.4 | `--no-follow` | Inicia ejecución, muestra ID, no streamea logs | 0 |

---

## Flags globales

| Flag | Tipo | Default | Descripción |
|---|---|---|---|
| `--output` | `json\|table\|text` | `table` | Formato de salida |
| `--debug` | `boolean` | `false` | Mostrar request/response HTTP |
| `--dry-run` | `boolean` | `false` | Validar sin ejecutar (create/delete) |
| `--quiet` | `boolean` | `false` | Suprimir output no esencial |
| `--no-color` | `boolean` | `false` | Desactivar colores ANSI |

---

## Environment Variables

| Variable | Default | Descripción |
|---|---|---|
| `CEREBELUM_API_URL` | `http://cerebelum.zea.localhost` | API base URL |
| `CEREBELUM_URL` | — | Alias de CEREBELUM_API_URL |
| `ZEA_PAT` | — | Personal Access Token (compartido con Thalamus) |
| `ZEA_TOKEN` | — | Alias de ZEA_PAT |
| `ZEA_API_URL` | `https://auth.zea.cl` | Thalamus / IAM URL |

### Prioridad de token

1. `ZEA_PAT` env var
2. `ZEA_TOKEN` env var
3. `~/.config/zea/config.json` → `token`
4. Sin token → error `Run: zea login`

---

## Flujos de integración

### Desarrollo local

```bash
# 1. Setup
zea cerebelum config set-env local
zea login

# 2. Desarrollar
vim workflow.py

# 3. Deploy + ejecutar + logs (un comando)
zea cerebelum run workflow.py --inputs '{"user_id":42}'

# 4. Monitorear
zea cerebelum execution list --status running
zea cerebelum execution status exec_abc123
zea cerebelum execution events exec_abc123
```

### CI/CD

```bash
# Setup
export ZEA_PAT=$CEREBELUM_TOKEN
export CEREBELUM_API_URL=https://cerebelum.zea.cl

# Deploy
zea cerebelum deploy workflow.py --output json

# Execute
EXEC_ID=$(zea cerebelum workflow run analisis_ventas --inputs '{"periodo":"Q4"}' --output json | jq -r '.id')

# Wait & verify
zea cerebelum execution status $EXEC_ID --output json | jq '.status'
```

### HITL — Human-in-the-Loop

```bash
# 1. Workflow pausa esperando aprobación
zea cerebelum execution status exec_abc123
# → ⏸️ Waiting for human approval

# 2. Revisar eventos para ver qué datos pide
zea cerebelum execution events exec_abc123

# 3. Aprobar
zea cerebelum execution approve exec_abc123 --response '{"decision":"approved","reason":"LGTM"}'
```

---

## Roadmap

### P0 — v1.0.0 (actual)
- [x] 100% cobertura de endpoints REST API
- [x] Commander + chalk + zeaFetch
- [x] `--zea-discover` + `--zea-manifest`
- [x] `run` end-to-end local
- [x] `dev-certs` para desarrollo con workers

### P1 — Próximo
- [ ] `step update/show/list` — CRUD de steps individuales (estilo Lambda)
- [ ] `workflow delete <id>` — eliminar blueprint
- [ ] `worker deregister <id>` — remover worker
- [ ] `--query` (JMESPath) para filtrar output

### P2 — Futuro
- [ ] `execution retry <id>` — re-ejecutar desde step fallido
- [ ] `dlq list|retry|purge` — gestión de Dead Letter Queue
- [ ] Paginación automática en listas grandes
- [ ] `--profile` multi-entorno
