# Events API

Query the event sourcing audit trail. Every workflow execution produces an append-only sequence of domain events.

---

## Get Execution Events

Returns all events for a specific execution.

```http
GET /api/v1/executions/:id/events
Authorization: Bearer <JWT>
```

### Response

```json
{
  "execution_id": "exec_abc123",
  "events": [
    {
      "version": 1,
      "type": "ExecutionStartedEvent",
      "data": {
        "workflow_module": "analisis_ventas",
        "workflow_version": "sha256:abc123...",
        "inputs": {"periodo": "Q4-2025"},
        "correlation_id": null,
        "tags": []
      },
      "timestamp": "2026-07-09T14:15:00Z"
    },
    {
      "version": 2,
      "type": "StepExecutedEvent",
      "data": {
        "step_name": "obtener_datos",
        "result": {"usuarios": 1250, "ventas": 34500000},
        "duration_ms": 800
      },
      "timestamp": "2026-07-09T14:15:01Z"
    }
  ],
  "count": 2
}
```

### Event Ordering

Events are ordered by `version` (monotonically increasing integer). The version guarantees total ordering within an execution — no two events in the same execution share a version number. Optimistic concurrency prevents conflicts.

---

## Event Types

18 domain event types form the complete audit trail:

### Workflow Lifecycle

| Event | When |
|---|---|
| `ExecutionStartedEvent` | Workflow execution begins |
| `ExecutionCompletedEvent` | All steps complete successfully |
| `ExecutionFailedEvent` | Workflow fails (unhandled error) |

### Step Execution

| Event | When |
|---|---|
| `StepExecutedEvent` | Step completes successfully |
| `StepFailedEvent` | Step fails with error |

### Flow Control

| Event | When |
|---|---|
| `DivergeTakenEvent` | Error handler fires (retry, back_to, skip_to, failed) |
| `BranchTakenEvent` | Branch condition matches a path |
| `JumpExecutedEvent` | `back_to` or `skip_to` executed |

### Parallel Execution

| Event | When |
|---|---|
| `ParallelStartedEvent` | Parallel task group begins |
| `ParallelTaskCompletedEvent` | Single parallel task finishes |
| `ParallelTaskFailedEvent` | Single parallel task fails |
| `ParallelCompletedEvent` | All parallel tasks complete |

### Long-Running

| Event | When |
|---|---|
| `SleepStartedEvent` | Workflow enters sleep |
| `SleepCompletedEvent` | Workflow wakes from sleep |
| `WorkflowHibernatedEvent` | Process terminated to save memory |
| `WorkflowAwakenedEvent` | Workflow resurrected from DB |

### Human-in-the-Loop

| Event | When |
|---|---|
| `ApprovalRequestedEvent` | Step requests human approval |
| `ApprovalReceivedEvent` | Approval granted |
| `ApprovalRejectedEvent` | Approval rejected |
| `ApprovalTimeoutEvent` | Approval request timed out |

---

## Event Structure

Every event has:

| Field | Type | Description |
|---|---|---|
| `event_id` | UUID | Unique event identifier |
| `execution_id` | string | Parent execution ID |
| `version` | integer | Monotonic version number |
| `event_type` | string | One of the 18 event types |
| `event_data` | map | Type-specific payload |
| `inserted_at` | datetime | When stored in event store |
| `timestamp` | datetime | When the event occurred |

---

## State Reconstruction

Events are the **source of truth** for workflow state. The `StateReconstructor` replays events to rebuild the full execution state:

```elixir
# Engine replays events after resurrection
events = EventStore.get_events(execution_id)
state = StateReconstructor.reconstruct(events)
# => %{status: :running, current_step: 3, results: %{...}}
```

This enables:
- **Time-travel debugging** — replay to any point
- **Crash recovery** — resume exactly where it stopped
- **Audit compliance** — complete immutable history

---

## See Also

- [Executions API](executions.md) — Create and monitor executions
- [Event Sourcing Guide](../guides/event-sourcing.md) — Deep dive into event store
- [Long-Running Workflows Guide](../guides/long-running-workflows.md) — Hibernation + resurrection
