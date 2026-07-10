# Long-Running Workflows

Cerebelum supports workflows that run for **days or weeks** through `sleep`, **hibernation** (terminate process + save to DB), and **resurrection** (reconstruct + resume on restart).

---

## Sleep

Pause execution within a step:

```elixir
defmodule MyApp.DripCampaign do
  use Cerebelum.Workflow

  workflow do
    timeline do
      send_welcome_email() |> wait_3_days() |> send_followup()
    end
  end

  def send_welcome_email(ctx) do
    EmailService.send(:welcome, ctx.inputs[:user_email])
    {:ok, %{sent: true}}
  end

  def wait_3_days(_ctx, _prev) do
    # Sleep for 72 hours
    Cerebelum.sleep(3 * 24 * 60 * 60 * 1000)
    {:ok, :awake}
  end

  def send_followup(ctx, _welcome, _awake) do
    EmailService.send(:followup, ctx.inputs[:user_email])
    {:ok, %{sent: true}}
  end
end
```

### Sleep Behavior

| Duration | Mode |
|---|---|
| < 1 hour | In-memory process sleep |
| > 1 hour (threshold) | May trigger **hibernation** |

---

## Hibernation

When hibernation is enabled, workflows sleeping beyond the threshold will:

1. **Save state** to PostgreSQL (all step results, context, events)
2. **Terminate process** to free memory (no idle BEAM process for weeks)
3. **Be resurrected** automatically by `WorkflowScheduler`

### Configuration

```elixir
config :cerebelum,
  enable_workflow_hibernation: true,      # Enable hibernation
  hibernation_threshold_ms: 3_600_000,    # Hibernate after 1 hour
  enable_workflow_resurrection: true,     # Auto-resurrect on boot
  resurrection_scan_interval_ms: 30_000,  # Scan every 30s
  max_resurrection_attempts: 3            # Max retry per workflow
```

### Hibernation Flow

```
Step calls Cerebelum.sleep(24h)
    ↓
Engine checks: duration > hibernation_threshold?
    ↓ YES
Emit SleepStartedEvent
Emit WorkflowHibernatedEvent
Save all state to PostgreSQL
Process terminates gracefully
    ... 24 hours pass ...
    ... system may restart ...
    ↓
WorkflowScheduler scans for paused workflows
    ↓
Finds hibernated exec_abc123
    ↓
Loads events from EventStore
StateReconstructor.reconstruct(events)
    ↓
Emit WorkflowAwakenedEvent
Emit SleepCompletedEvent
Continue from next step
```

---

## Resurrection

After a system restart (or crash), the `Resurrector` scans for hibernated workflows:

### Boot-Time Resurrection

```elixir
# In Cerebelum.Application.start/2
# The Resurrector is started as part of the supervision tree
{Cerebelum.Execution.Resurrector, []}
```

On boot:
1. Queries PostgreSQL for hibernated workflows
2. Loads their events
3. Reconstructs state
4. Resumes each execution

### Periodic Resurrection

```elixir
{Cerebelum.Infrastructure.WorkflowScheduler, []}
```

The `WorkflowScheduler` runs every `resurrection_scan_interval_ms` (default: 30s) to:

1. Scan for workflows whose sleep has ended
2. Reconstruct state from events
3. Resume execution

---

## Manual Resume

Resume a paused/hibernated workflow via API:

```bash
curl -X POST https://cerebelum.zea.cl/api/v1/executions/exec_abc123/resume \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "execution_id": "exec_abc123",
  "status": "resumed"
}
```

Or in Elixir:

```elixir
{:ok, pid} = Cerebelum.resume_execution("exec_abc123")
```

---

## Human-in-the-Loop (Approval)

Workflows can pause for human input:

```elixir
def review_document(_ctx, {:ok, document}) do
  {:wait_for_approval,
   [type: :manual, timeout_minutes: 60],
   %{document_id: document.id, reviewer: "manager"}}
end
```

### Approve via API

```bash
curl -X POST https://cerebelum.zea.cl/api/v1/executions/exec_abc123/approve \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"approved_by": "Alice", "notes": "Looks good"}'
```

### Reject via Code

```elixir
Cerebelum.Execution.Approval.reject(pid, "Document incomplete")
# => {:ok, :rejected}
```

### Approval Flow Events

```
ApprovalRequestedEvent → ApprovalReceivedEvent   (approved)
ApprovalRequestedEvent → ApprovalTimeoutEvent     (timed out)
ApprovalRequestedEvent → ApprovalRejectedEvent    (rejected)
```

---

## Best Practices

| Do | Don't |
|---|---|
| Set realistic `hibernation_threshold_ms` | Hibernate workflows that sleep < 5 min |
| Use approval for business-critical gates | Approval for every step (too slow) |
| Test resurrection after simulated crash | Assume resurrection works without tests |
| Configure `max_resurrection_attempts` | Let failed workflows retry forever |
| Monitor hibernated workflow count | Ignore growing hibernation queue |

---

## See Also

- [Event Sourcing Guide](event-sourcing.md) — How state is preserved for hibernation
- [Architecture Overview](../architecture/overview.md) — Resurrector + WorkflowScheduler in the supervision tree
- [Executions API](../api/executions.md) — Resume and approve endpoints
