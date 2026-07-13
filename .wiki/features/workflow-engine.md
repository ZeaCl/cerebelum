# Workflow Engine

Motor determinístico de ejecución de workflows basado en `:gen_statem`.

## Arquitectura

```
Supervisor (DynamicSupervisor)
  └── Engine (:gen_statem)
        ├── StateHandlers (initializing, executing_step, completed, failed, sleeping, waiting_for_approval)
        ├── StepExecutor (local o remote)
        ├── EventEmitter (persistencia de eventos)
        ├── DivergeHandler / BranchHandler / JumpHandler
        └── ParallelExecutor
```

## Estados

| Estado | Descripción |
|---|---|
| `initializing` | Setup inicial, emite ExecutionStartedEvent |
| `executing_step` | Ejecuta step actual (local o gRPC) |
| `completed` | Timeline completo, emite ExecutionCompletedEvent |
| `failed` | Error irrecuperable, emite ExecutionFailedEvent |
| `sleeping` | Pausa temporal, emite SleepStartedEvent |
| `waiting_for_approval` | Espera input humano, emite ApprovalRequestedEvent |

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/execution/engine.ex` | Public API + gen_statem callbacks |
| `lib/cerebelum/execution/engine/data.ex` | Data struct, helpers, version tracking |
| `lib/cerebelum/execution/engine/state_handlers.ex` | State functions por estado |
| `lib/cerebelum/execution/step_executor.ex` | Ejecución de steps (local/remote) |
| `lib/cerebelum/execution/event_emitter.ex` | Persistencia de eventos sync/async |
| `lib/cerebelum/execution/supervisor.ex` | DynamicSupervisor, resume_execution |

## Step modes

- **:local** — Ejecuta step function de workflow Elixir directamente
- **:remote** — Delega al Python Worker vía gRPC (WorkflowDelegatingWorkflow)

## Resurrection

Workflows pausados (sleep, approval) o crasheados se pueden resucitar desde el EventStore:
```elixir
Cerebelum.Execution.Supervisor.resume_execution(execution_id)
```
