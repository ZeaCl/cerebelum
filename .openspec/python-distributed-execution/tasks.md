# Implementation Plan — Python Distributed Workflow Execution

## Contexto
El diseño y ~80% del código ya existe. `DelegatingWorkflow` es el bridge diseñado para esto. Solo falta integrarlo en el loop de ejecución del Engine.

- [ ] 1. **Pasar blueprint al Engine.Data**
  - Almacenar `blueprint` y `blueprint_name` del opts en `Engine.Data` struct
  - Exponer `Data.blueprint/1` y `Data.blueprint_name/1`
  - _Requirements: R4.1, R4.2_

- [ ] 2. **StepExecutor — detectar modo remoto**
  - [ ] 2.1 `StepExecutor.step_mode(data)` → `:local` | `:remote`
  - [ ] 2.2 Si workflow_module es `WorkflowDelegatingWorkflow` → `:remote`
  - [ ] 2.3 Si `:remote`, llamar `DelegatingWorkflow.execute_step` en vez de `apply/3`
  - _Requirements: R1.1, R4.3_

- [ ] 3. **DelegatingWorkflow — leer blueprint del Data**
  - [ ] 3.1 Recibir `data` (o `blueprint` + `blueprint_name`) como parámetro
  - [ ] 3.2 Usar `blueprint_name` para el TaskRouter (no `context.metadata`)
  - [ ] 3.3 Extraer `blueprint.definition.timeline` para metadata
  - _Requirements: R4.1, R4.2_

- [ ] 4. **DelegatingWorkflow.execute_step — timeout + eventos**
  - [ ] 4.1 Emitir `StepStartedEvent` con `executor: :worker`
  - [ ] 4.2 Timeout de 5 minutos usando `Process.send_after`
  - [ ] 4.3 Emitir `StepExecutedEvent` con `duration_ms` real
  - [ ] 4.4 Manejar sleep/approval responses del worker
  - _Requirements: R1.2, R1.3, R5.2, R5.3_

- [ ] 5. **Engine — sin estado nuevo** (DelegatingWorkflow ya bloquea)
  - `DelegatingWorkflow.execute_step` ya es bloqueante (usa `receive`)
  - `await_task_result` ya espera el callback del worker
  - No se necesita `:waiting_for_worker` — el flow es síncrono desde la perspectiva del Engine
  - _Requirements: R1.3, R3.1_

- [ ] 6. **Event sourcing parity**
  - [ ] 6.1 `ExecutionStartedEvent` incluir `mode: :distributed` y `blueprint_name`
  - [ ] 6.2 `StepExecutedEvent` con metadata de worker
  - [ ] 6.3 Diverge rules del blueprint evaluadas normalmente
  - _Requirements: R5.1, R5.4, R6.1_

- [ ] 7. **Error handling**
  - [ ] 7.1 Worker error → `{:error, reason}` → diverge rules
  - [ ] 7.2 Worker timeout → `{:error, :task_timeout}`
  - [ ] 7.3 No workers → `{:error, :no_workers_available}`
  - [ ] 7.4 3 retries antes de DLQ
  - _Requirements: R1.4, R2.4, R6.1-R6.4_

- [ ] 8. **E2E test**
  - [ ] 8.1 `python 01_local_workflow.py --distributed` → `Status: completed`
  - [ ] 8.2 Verificar eventos en `EventStore.get_events(exec_id)`
  - [ ] 8.3 Verificar que workflows Elixir no se rompen
  - _Requirements: R1-R6_
