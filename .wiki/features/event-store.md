# Event Store

Append-only event store con batching para alta throughput.

## Características

- **Append-only**: eventos inmutables, versionados
- **Batching**: 100ms window, max 1000 eventos por batch
- **Partitioning**: PostgreSQL particiona por hash de execution_id
- **Target**: 640K eventos/segundo

## Eventos

| Evento | Persistencia | Cuándo |
|---|---|---|
| ExecutionStartedEvent | Sync | Al iniciar ejecución |
| StepExecutedEvent | Async | Step completado |
| StepFailedEvent | Async | Step falló |
| DivergeTakenEvent | Async | Diverge evaluado |
| BranchTakenEvent | Async | Branch tomado |
| JumpExecutedEvent | Async | Jump ejecutado |
| SleepStartedEvent | Async | Workflow entra en sleep |
| SleepCompletedEvent | Async | Workflow despierta |
| ApprovalRequestedEvent | Async | HITL solicitado |
| ApprovalReceivedEvent | Async | Aprobación recibida |
| ApprovalRejectedEvent | Async | Aprobación rechazada |
| ApprovalTimeoutEvent | Async | Timeout de aprobación |
| ExecutionCompletedEvent | Sync | Ejecución completada |
| ExecutionFailedEvent | Sync | Ejecución falló |

## Query de listado

```sql
-- Por execution_id, obtiene el último evento y el workflow_name
SELECT COALESCE(event_data->>'blueprint_name', event_data->>'workflow_module')
FROM events
WHERE execution_id = ? AND event_type = 'ExecutionStartedEvent'
LIMIT 1
```

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/event_store.ex` | GenServer, batching, queries |
| `lib/cerebelum/persistence/event.ex` | Ecto schema |
| `lib/cerebelum/events.ex` | Structs de dominio |
| `lib/cerebelum/execution/event_emitter.ex` | Emisión de eventos |

## Debugging

- `EventStore.get_events(execution_id)` — recupera todos los eventos
- `EventStore.get_events_from_version(execution_id, 5)` — desde versión específica
- `EventStore.list_executions(workflow_name: "...", status: :running)` — listado filtrado
