# ZEA Cerebelum CLI — Matriz de Testing End-to-End

> **Status**: Draft v0.1
> **Última actualización**: 2025-07-24

---

## Estrategia

Tests E2E contra una instancia **real y efímera** de Cerebelum + Thalamus.
Cada run crea los contenedores, ejecuta seeds, corre los tests, y destruye todo.

Mismo patrón que `thalamus` y `soma`:

```bash
docker compose -f docker-compose.test.yml up -d --wait
./scripts/test-cli.sh "02_workflow"
docker compose -f docker-compose.test.yml down -v
```

---

## Infraestructura

### `docker-compose.test.yml`

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: cerebelum_test
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "${TEST_DB_PORT:-5534}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 3s
      timeout: 3s
      retries: 10

  thalamus:
    build:
      context: ../thalamus
      dockerfile: Dockerfile
    environment:
      DATABASE_URL: ecto://postgres:postgres@postgres/thalamus_test
      SECRET_KEY_BASE: "test_secret_key_base_min_64_chars_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
      PHX_HOST: localhost
      PORT: 4001
      MIX_ENV: prod
      TEST_AUTH_ALLOWED: "true"
      SEED_ON_START: "true"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4001/api/public/health"]
      interval: 3s
      timeout: 3s
      retries: 30

  cerebelum:
    build:
      context: ..
      dockerfile: Dockerfile
      target: runtime
    environment:
      DATABASE_URL: ecto://postgres:postgres@postgres/cerebelum_test
      CEREBELUM_PORT: 4000
      MIX_ENV: prod
      THALAMUS_INTROSPECTION_URL: http://thalamus:4001/oauth/introspect
    ports:
      - "${TEST_PORT:-4000}:4000"
    depends_on:
      postgres:
        condition: service_healthy
      thalamus:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 3s
      timeout: 3s
      retries: 30
```

---

## Matriz de tests: 6 suites, 28 casos

### `test/cli/01_health.sh` — Health + Doctor

```bash
#!/bin/bash
# Test: health, doctor

# ── TC-01: Health OK ──────────────────────────────────
log_test "TC-01: health — Cerebelum healthy"
output=$($CLI_PATH cerebelum health --output json 2>&1)
exit_code=$?
assert_exit_code $exit_code 0 "TC-01: exit code 0"
assert_json_field "$output" '.status' '"ok"' "TC-01: status ok"

# ── TC-02: Health table output ────────────────────────
log_test "TC-02: health — table output"
output=$($CLI_PATH cerebelum health 2>&1)
assert_output_contains "$output" "OK" "TC-02: shows OK"

# ── TC-03: Doctor — all OK ────────────────────────────
log_test "TC-03: doctor — diagnóstico completo"
output=$($CLI_PATH cerebelum doctor 2>&1)
exit_code=$?
assert_exit_code $exit_code 0 "TC-03: exit 0"
assert_output_contains "$output" "Connectivity" "TC-03: connectivity checked"
assert_output_contains "$output" "Workflows" "TC-03: workflows checked"
```

### `test/cli/02_workflow.sh` — Deploy + Workflow CRUD

```bash
#!/bin/bash
# Test: deploy, workflow list, show, code, run

# Setup: login and create a test workflow file
setup() {
  $CLI_PATH thalamus auth login --email c@zea.cl --password "GusVicentAnto1." > /dev/null 2>&1
  cat > /tmp/test_workflow.py << 'PYEOF'
from cerebelum import workflow, step

@workflow
def test_workflow():
    pass

@step
def hello(inputs):
    return {"message": f"Hello {inputs.get('name', 'World')}"}
PYEOF
}

# ── TC-04: Deploy — archivo válido ────────────────────
log_test "TC-04: deploy — workflow.py válido"
setup
output=$($CLI_PATH cerebelum deploy /tmp/test_workflow.py --output json 2>&1)
assert_json_field "$output" '.data.name' '"test_workflow"' "TC-04: name correcto"
assert_json_field "$output" '.data.language' '"python"' "TC-04: language python"

# ── TC-05: Deploy — archivo no existe ─────────────────
log_test "TC-05: deploy — archivo no existe"
output=$($CLI_PATH cerebelum deploy /tmp/no_existe.py 2>&1)
exit_code=$?
assert_exit_code $exit_code 1 "TC-05: exit 1"
assert_output_contains "$output" "File not found" "TC-05: error message"

# ── TC-06: Workflow list ──────────────────────────────
log_test "TC-06: workflow list"
output=$($CLI_PATH cerebelum workflow list --output json 2>&1)
assert_output_contains "$output" "test_workflow" "TC-06: aparece en lista"

# ── TC-07: Workflow show ──────────────────────────────
log_test "TC-07: workflow show"
output=$($CLI_PATH cerebelum workflow show test_workflow --output json 2>&1)
assert_json_field "$output" '.data.name' '"test_workflow"' "TC-07: name"

# ── TC-08: Workflow run — con inputs ──────────────────
log_test "TC-08: workflow run"
output=$($CLI_PATH cerebelum workflow run test_workflow --inputs '{"name":"ZEA"}' --output json 2>&1)
assert_json_field "$output" '.data.status' '"started"' "TC-08: status started"
EXEC_ID=$(echo "$output" | jq -r '.data.id')

# ── TC-09: Workflow run — JSON inválido ───────────────
log_test "TC-09: workflow run — inputs inválidos"
output=$($CLI_PATH cerebelum workflow run test_workflow --inputs 'not-json' 2>&1)
exit_code=$?
assert_exit_code $exit_code 1 "TC-09: exit 1"
assert_output_contains "$output" "Invalid JSON" "TC-09: error message"

# ── TC-10: Dry-run — no ejecuta ────────────────────────
log_test "TC-10: dry-run deploy"
output=$($CLI_PATH cerebelum deploy /tmp/test_workflow.py --dry-run 2>&1)
assert_output_contains "$output" "DRY RUN" "TC-10: dry run message"
```

### `test/cli/03_execution.sh` — Execution lifecycle

```bash
#!/bin/bash
# Test: execution list, status, events, stop, resume, approve

setup() {
  $CLI_PATH thalamus auth login --email c@zea.cl --password "GusVicentAnto1." > /dev/null 2>&1
  # Deploy a workflow that waits for approval
  cat > /tmp/test_hitl.py << 'PYEOF'
from cerebelum import workflow, step
from cerebelum.dsl.async_helpers import wait_for_approval

@workflow
def test_hitl():
    pass

@step
def pedir_aprobacion(inputs):
    return wait_for_approval({"pregunta": "¿Continuar?"})

@step
def paso_final(inputs, previous_results):
    return {"resultado": inputs.get("decision", "no_decision")}
PYEOF
  $CLI_PATH cerebelum deploy /tmp/test_hitl.py > /dev/null 2>&1
}

# ── TC-11: Execution list ─────────────────────────────
log_test "TC-11: execution list"
setup
# Start a couple executions
$CLI_PATH cerebelum workflow run test_hitl > /dev/null 2>&1
sleep 2
output=$($CLI_PATH cerebelum execution list --output json 2>&1)
count=$(echo "$output" | jq '.executions | length')
[ "$count" -ge 1 ] && log_pass "TC-11: 1+ executions" || log_fail "TC-11: no executions"

# ── TC-12: Execution list — filtro por status ────────
log_test "TC-12: execution list — filtro running"
output=$($CLI_PATH cerebelum execution list --status running --output json 2>&1)
assert_output_contains "$output" "running" "TC-12: running executions"

# ── TC-13: Execution status ───────────────────────────
log_test "TC-13: execution status"
EXEC_ID=$(echo "$output" | jq -r '.executions[0].execution_id')
output=$($CLI_PATH cerebelum execution status "$EXEC_ID" --output json 2>&1)
assert_output_contains "$output" "waiting_for_approval" "TC-13: HITL status"

# ── TC-14: Execution events ───────────────────────────
log_test "TC-14: execution events"
output=$($CLI_PATH cerebelum execution events "$EXEC_ID" --output json 2>&1)
count=$(echo "$output" | jq '.events | length')
[ "$count" -ge 1 ] && log_pass "TC-14: 1+ events" || log_fail "TC-14: no events"

# ── TC-15: Execution approve ──────────────────────────
log_test "TC-15: execution approve"
output=$($CLI_PATH cerebelum execution approve "$EXEC_ID" --response '{"decision":"approved"}' --output json 2>&1)
assert_output_contains "$output" "approved" "TC-15: approved"

# ── TC-16: Execution status — not found ───────────────
log_test "TC-16: execution status — not found"
output=$($CLI_PATH cerebelum execution status "no_existe_123" 2>&1)
exit_code=$?
assert_exit_code $exit_code 1 "TC-16: exit 1"
```

### `test/cli/04_logs.sh` — Logs

```bash
#!/bin/bash
# Test: logs, logs --follow

setup() {
  $CLI_PATH thalamus auth login --email c@zea.cl --password "GusVicentAnto1." > /dev/null 2>&1
}

# ── TC-17: Logs — ejecución completada ────────────────
log_test "TC-17: logs"
setup
# Deploy + run a quick workflow
cat > /tmp/test_fast.py << 'PYEOF'
from cerebelum import workflow, step

@workflow
def test_fast():
    pass

@step
def quick_step(inputs):
    return {"ok": True}
PYEOF
$CLI_PATH cerebelum deploy /tmp/test_fast.py > /dev/null 2>&1
EXEC_ID=$($CLI_PATH cerebelum workflow run test_fast --output json 2>&1 | jq -r '.data.id')
sleep 3
output=$($CLI_PATH cerebelum logs "$EXEC_ID" 2>&1)
assert_output_contains "$output" "ExecutionCompleted" "TC-17: completed in logs"

# ── TC-18: Logs — execution not found ─────────────────
log_test "TC-18: logs — not found"
output=$($CLI_PATH cerebelum logs "no_existe_123" 2>&1)
exit_code=$?
assert_exit_code $exit_code 1 "TC-18: exit 1"
```

### `test/cli/05_devcerts.sh` — Dev Certs

```bash
#!/bin/bash
# Test: dev-certs create, status

setup() {
  $CLI_PATH thalamus auth login --email c@zea.cl --password "GusVicentAnto1." > /dev/null 2>&1
}

# ── TC-19: Dev-certs status — sin certs ───────────────
log_test "TC-19: dev-certs status — sin certs"
rm -rf ~/.cerebelum/certs 2>/dev/null
output=$($CLI_PATH cerebelum dev-certs status 2>&1)
assert_output_contains "$output" "missing" "TC-19: missing message"

# ── TC-20: Dev-certs create ───────────────────────────
log_test "TC-20: dev-certs create"
setup
output=$($CLI_PATH cerebelum dev-certs create 2>&1)
assert_output_contains "$output" "generated" "TC-20: generated message"

# ── TC-21: Dev-certs status — con certs ───────────────
log_test "TC-21: dev-certs status — con certs"
output=$($CLI_PATH cerebelum dev-certs status 2>&1)
assert_output_contains "$output" "ready" "TC-21: ready message"
```

### `test/cli/06_config.sh` — Configuración

```bash
#!/bin/bash
# Test: config set-env, set, get, list, path

# ── TC-22: Config set-env local ───────────────────────
log_test "TC-22: config set-env local"
output=$($CLI_PATH cerebelum config set-env local 2>&1)
assert_output_contains "$output" "LOCAL" "TC-22: set to local"

# ── TC-23: Config set + get ───────────────────────────
log_test "TC-23: config set + get"
$CLI_PATH cerebelum config set test_key test_value 2>&1 > /dev/null
output=$($CLI_PATH cerebelum config get test_key 2>&1)
assert_output_contains "$output" "test_value" "TC-23: value saved"
$CLI_PATH cerebelum config unset test_key 2>&1 > /dev/null

# ── TC-24: Config list ────────────────────────────────
log_test "TC-24: config list"
output=$($CLI_PATH cerebelum config list 2>&1)
assert_output_contains "$output" "cerebelumUrl" "TC-24: cerebelumUrl visible"

# ── TC-25: Config path ────────────────────────────────
log_test "TC-25: config path"
output=$($CLI_PATH cerebelum config path 2>&1)
assert_output_contains "$output" ".config/zea/config.json" "TC-25: path"

# ── TC-26: Config set-env prod ────────────────────────
log_test "TC-26: config set-env prod"
output=$($CLI_PATH cerebelum config set-env prod 2>&1)
assert_output_contains "$output" "PROD" "TC-26: set to prod"
```

### `test/cli/07_errors.sh` — Manejo de errores

```bash
#!/bin/bash
# Test: network errors, 401, dry-run

# ── TC-27: Cerebelum inalcanzable ─────────────────────
log_test "TC-27: error — Cerebelum caído"
CEREBELUM_API_URL="http://localhost:19999" $CLI_PATH cerebelum health 2>&1 > /dev/null
exit_code=$?
assert_exit_code $exit_code 1 "TC-27: exit 1 (network error)"

# ── TC-28: Dry-run execution ──────────────────────────
log_test "TC-28: dry-run workflow run"
output=$($CLI_PATH cerebelum workflow run test_workflow --dry-run 2>&1)
assert_output_contains "$output" "DRY RUN" "TC-28: dry run message"
```

---

## Matriz resumen

| Suite | # Tests | Comandos cubiertos |
|---|---|---|
| `01_health` | TC-01 a TC-03 | `health`, `doctor` |
| `02_workflow` | TC-04 a TC-10 | `deploy`, `workflow list`, `show`, `run` |
| `03_execution` | TC-11 a TC-16 | `execution list`, `status`, `events`, `approve` |
| `04_logs` | TC-17 a TC-18 | `logs` |
| `05_devcerts` | TC-19 a TC-21 | `dev-certs create`, `status` |
| `06_config` | TC-22 a TC-26 | `config set-env`, `set`, `get`, `list`, `path` |
| `07_errors` | TC-27 a TC-28 | Errores de red, dry-run |

---

## Ejecución local

```bash
# 1. Levantar contenedores efímeros
docker compose -f docker-compose.test.yml up -d --wait

# 2. Instalar CLI localmente
cd cli && npm install && npm link

# 3. Correr todos los tests
./scripts/test-cli.sh

# 4. Correr una suite específica
./scripts/test-cli.sh 02_workflow

# 5. Tear down
docker compose -f docker-compose.test.yml down -v
```

---

## CI Workflow (GitHub Actions)

```yaml
name: CLI E2E Tests
on:
  push:
    branches: [main]
    paths: ['cli/**', 'test/cli/**', 'docker-compose.test.yml']
  pull_request:
    branches: [main]
    paths: ['cli/**', 'test/cli/**']

jobs:
  cli-e2e:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        suite:
          - "01_health"
          - "02_workflow"
          - "03_execution"
          - "04_logs"
          - "05_devcerts"
          - "06_config"
          - "07_errors"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - name: Install CLI
        working-directory: cli
        run: npm ci && npm link
      - name: Start ephemeral services
        run: docker compose -f docker-compose.test.yml up -d --wait
      - name: Run tests
        run: ./scripts/test-cli.sh ${{ matrix.suite }}
        env:
          CLI_PATH: zea
      - name: Teardown
        if: always()
        run: docker compose -f docker-compose.test.yml down -v
```

---

## Principios

1. **Efímero**: cada run crea y destruye los contenedores
2. **Aislado**: no depende de servicios compartidos
3. **Determinista**: seeds garantizan el mismo estado inicial
4. **Legible**: tests en bash con assertions descriptivas
5. **CI-first**: matrix strategy para paralelismo
