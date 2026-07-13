# HITL — Human-in-the-Loop Approval

Workflows pueden pausar y esperar aprobación humana usando `wait_for_approval()`.

## Flujo completo

```
Python step → wait_for_approval() → ApprovalMarker exception
  → Worker SDK lo atrapa → envía TaskStatus.APPROVAL via gRPC
  → Engine (worker_service_server.ex) → {:approval, data}
  → Engine (state_handlers.ex) → :waiting_for_approval state
  → POST /executions/:id/approve → Engine re-ejecuta el step con datos
  → Step recibe inputs → valida → OK → avanza
```

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/infrastructure/worker_service_server.ex` | Detecta APPROVAL/SLEEP del worker |
| `lib/cerebelum/execution/engine/state_handlers.ex` | Maneja `{:approval, data}`, transiciona a `:waiting_for_approval` |
| `lib/cerebelum/execution/approval.ex` | API pública: `approve/2`, `approve_by_id/2` |
| `lib/cerebelum/api/controllers/execution_controller.ex` | Endpoint `POST /executions/:id/approve` |
| `lib/cerebelum/execution/engine/data.ex` | `json_safe_results/1`, `build_step_inputs` |

## API

```bash
# Approbar step
POST /api/v1/executions/:id/approve
Body: {"decision": "approved", ...}
```

## Estados

- **waiting_for_approval** — Esperando input humano
- Timeout configurable (`:timeout_ms`, `:timeout_seconds`, `:timeout_minutes`)
- Al recibir approve → re-ejecuta el step con los datos de aprobación

## Debugging

| Síntoma | Causa probable | Fix |
|---|---|---|
| Steps se completan instantáneamente | `@step` decorator traga ApprovalMarker | SDK >= 0.3.1 |
| Step recibe `previous_results` inesperado | Falta `**kwargs` en step function | Agregar `**kwargs` |
| Approve no pasa datos al step | `build_step_inputs` no encuentra resultado | Verificar `Map.get(data.results, step_name)` |
