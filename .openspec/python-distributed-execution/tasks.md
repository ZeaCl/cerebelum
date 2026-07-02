# Implementation Plan — Python Distributed Workflow Execution

- [ ] 1. **Blueprint context en DelegatingWorkflow**
  - Leer `blueprint` y `blueprint_name` del contexto de ejecución
  - Exponer timeline, diverges, branches del blueprint como metadata
  - Validar que el blueprint existe en BlueprintRegistry antes de ejecutar
  - _Requirements: R1.1, R4.1, R4.2_

- [ ] 2. **StepExecutor — detección de modo remoto**
  - [ ] 2.1 Agregar `step_mode/1` que retorna `:local` | `:remote` según tipo de workflow
  - [ ] 2.2 Si `:remote`, delegar a `DelegatingWorkflow.execute_step/3` en vez de `apply/3`
  - [ ] 2.3 Pasar blueprint_name a `execute_step` para TaskRouter routing
  - _Requirements: R1.1, R4.3_

- [ ] 3. **DelegatingWorkflow.execute_step — implementación real**
  - [ ] 3.1 Crear task en `TaskRouter` con step_name, inputs, execution_id, blueprint_name
  - [ ] 3.2 Registrar callback `{:awaiting_task, execution_id, task_id}` en Execution.Registry
  - [ ] 3.3 Esperar resultado con timeout de 5 minutos (state_timeout)
  - [ ] 3.4 Emitir `StepStartedEvent` al crear task y `StepExecutedEvent` al recibir resultado
  - _Requirements: R1.2, R1.3, R2.1, R3.1_

- [ ] 4. **Engine — nuevo estado waiting_for_worker**
  - [ ] 4.1 Agregar estado `:waiting_for_worker` al gen_statem
  - [ ] 4.2 Transición `executing_step → waiting_for_worker` al delegar
  - [ ] 4.3 Manejar mensaje `{:step_completed, step_name, result}` para despertar
  - [ ] 4.4 State timeout de 5 minutos → `:step_timeout`
  - _Requirements: R1.3, R3.1, R3.2, R3.3_

- [ ] 5. **Worker polling loop (Python SDK)**
  - [ ] 5.1 Implementar `Worker.poll_and_execute()` con loop de 500ms
  - [ ] 5.2 Ejecutar step localmente vía `LocalExecutor`
  - [ ] 5.3 Enviar resultado con `SubmitResult`
  - [ ] 5.4 Manejar errores de conexión con reconnect
  - _Requirements: R2.1, R2.2_

- [ ] 6. **Event sourcing para modo distribuido**
  - [ ] 6.1 Emitir `StepStartedEvent` con metadata `executor: :worker`
  - [ ] 6.2 Emitir `StepExecutedEvent` con `duration_ms` real (desde dispatch hasta resultado)
  - [ ] 6.3 `ExecutionStartedEvent` incluir `blueprint_version` y `mode: :distributed`
  - [ ] 6.4 `ExecutionCompletedEvent` con resultados finales
  - _Requirements: R5.1, R5.2, R5.3, R5.4_

- [ ] 7. **Error handling + diverge rules**
  - [ ] 7.1 Worker error → DelegatingWorkflow retorna `{:error, reason}`
  - [ ] 7.2 Engine evalúa diverge rules del blueprint (reusar DivergeHandler)
  - [ ] 7.3 Soporte para `back_to(:step)` en workflows distribuidos
  - [ ] 7.4 Task timeout después de 3 reintentos → DLQ
  - _Requirements: R6.1, R6.2, R6.3, R2.4, R6.4_

- [ ] 8. **Workers sin workers disponibles**
  - [ ] 8.1 Si `WorkerRegistry.list()` está vacío → `StepFailedEvent` con `:no_workers_available`
  - [ ] 8.2 Si worker asignado falla → reintentar con otro worker disponible
  - [ ] 8.3 Evento `WorkerDisconnectedEvent` cuando worker se va
  - _Requirements: R1.4_

- [ ] 9. **E2E integration test**
  - [ ] 9.1 Test: Python SDK → SubmitBlueprint → ExecuteWorkflow → Worker ejecuta → resultado
  - [ ] 9.2 Verificar event sourcing completo (todos los eventos emitidos)
  - [ ] 9.3 Verificar que workflows Elixir nativos no se rompen (regression)
  - [ ] 9.4 Test con worker caído a mitad de ejecución
  - _Requirements: R1-R6_
