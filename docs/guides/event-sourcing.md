# Event Sourcing

Cerebelum uses **event sourcing** as its persistence and state management model. Every state change in a workflow execution is recorded as an immutable event in an append-only log.

---

## Why Event Sourcing?

| Benefit | How Cerebelum Uses It |
|---|---|
| **Complete audit trail** | Every step, branch, error, and decision is recorded |
| **Time-travel debugging** | Replay events to any point in execution |
| **Crash recovery** | Reconstruct state from events after restart |
| **Workflow resurrection** | Rebuild execution state from persisted events |
| **Compliance** | Immutable history for regulatory requirements |
| **Reproducibility** | Same events → same state, always |

---

## Event Store Architecture

```
┌──────────────┐     ┌───────────────┐     ┌─────────────┐
│  Engine      │ ──→ │  EventStore   │ ──→ │  PostgreSQL │
│  (gen_statem)│     │  (append-only)│     │  (events)   │
└──────────────┘     └───────────────┘     └─────────────┘
       │                      │
       │ ① emit_event()       │ ④ replay
       ▼                      ▼
┌──────────────┐     ┌───────────────┐
│ EventEmitter  │     │StateReconstruct│
└──────────────┘     └───────────────┘
```

1. **Engine** calls `EventEmitter.emit_event(event)` on each state transition
2. **EventEmitter** validates, assigns version, persists via `EventStore`
3. **EventStore** appends to PostgreSQL with optimistic concurrency
4. **StateReconstructor** replays events to rebuild full execution state

---

## Performance

The event store is optimized for high throughput:

```bash
mix run lib/mix/tasks/benchmark.ex
```

| Metric | Value |
|---|---|
| **Batch insert** | 640K+ events/sec |
| **Event replay** | Sub-ms per event |
| **Single insert** | ~0.1ms per event |

Batching is key — events are buffered and flushed in transactions for maximum throughput.

---

## Schema

```sql
CREATE TABLE cerebelum_events (
  id UUID PRIMARY KEY,
  execution_id UUID NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  event_data JSONB NOT NULL,
  version INTEGER NOT NULL,
  inserted_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(execution_id, version)
);

CREATE INDEX ON cerebelum_events (execution_id);
CREATE INDEX ON cerebelum_events (inserted_at);
```

The `UNIQUE(execution_id, version)` constraint provides **optimistic concurrency** — two concurrent writes with the same version will conflict, preventing data corruption.

---

## State Reconstruction

When a workflow resumes after hibernation or crash:

```elixir
# 1. Load all events for the execution
{:ok, events} = Cerebelum.EventStore.get_events("exec_abc123")

# 2. Reconstruct state
state = Cerebelum.Execution.StateReconstructor.reconstruct(events)
# => %{
#   status: :running,
#   current_step_index: 2,
#   results: %{step1: ..., step2: ...},
#   branch_paths: %{step1: :high_value},
#   error: nil
# }

# 3. Resume execution from reconstructed state
{:ok, pid} = Cerebelum.resume_execution("exec_abc123")
```

### What Gets Reconstructed

- Current step index (where to resume)
- All previous step results
- Branch paths taken
- Diverge matches
- Error state
- Context (inputs, tags, correlation_id)

---

## Event Immutability

Events are **append-only and immutable**:

```elixir
# ❌ Cannot update events
EventStore.update(event_id, new_data)  # Not implemented

# ❌ Cannot delete events
EventStore.delete(event_id)  # Not implemented

# ✅ Only append
EventStore.append(execution_id, event)  # Immutable log
```

This guarantees:
- Audit trail cannot be tampered with
- Replay always produces the same state
- Compliance with data retention policies

---

## Version Numbers

Events within an execution use monotonically increasing versions:

```
ExecutionStartedEvent    version: 1
StepExecutedEvent        version: 2
StepExecutedEvent        version: 3
BranchEvaluatedEvent     version: 4
ExecutionCompletedEvent  version: 5
```

Versions serve dual purpose:
1. **Ordering** — events are always replayed in version order
2. **Concurrency control** — `UNIQUE(execution_id, version)` prevents conflicts

---

## Querying Events

### All events for an execution

```bash
curl https://cerebelum.zea.cl/api/v1/executions/exec_abc123/events \
  -H "Authorization: Bearer $TOKEN"
```

### Filter by execution status

```bash
curl "https://cerebelum.zea.cl/api/v1/executions?status=completed" \
  -H "Authorization: Bearer $TOKEN"
```

### Programmatic access (Elixir)

```elixir
# Get all events for an execution
{:ok, events} = Cerebelum.EventStore.get_events("exec_abc123")

# Filter by type
execution_started = Enum.find(events, &(&1.event_type == "ExecutionStartedEvent"))

# Get the last event
last_event = List.last(events)

# Determine status from last event
status = case last_event.event_type do
  "ExecutionCompletedEvent" -> :completed
  "ExecutionFailedEvent" -> :failed
  _ -> :running
end
```

---

## See Also

- [Events API](../api/events.md) — Full list of event types
- [Long-Running Workflows](long-running-workflows.md) — How event sourcing enables hibernation
- [Architecture Overview](../architecture/overview.md) — Event store in the system
