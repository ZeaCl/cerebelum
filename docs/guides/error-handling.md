# Error Handling

Cerebelum provides layered error handling: **diverge** for pattern-matched recovery, **retries**, and **Dead Letter Queue (DLQ)** for unrecoverable failures.

---

## Error Types

| Type | Return Value | Diverge Match | Typical Response |
|---|---|---|---|
| **Validation error** | `{:error, :invalid_input}` | Exact match | `:failed` |
| **Transient error** | `{:error, :gateway_timeout}` | Exact match | `:retry` or `back_to(:step)` |
| **Business error** | `{:error, :out_of_stock}` | Exact match | `back_to(:restock)` |
| **Timeout** | `:timeout` | Atom match | `:retry` |
| **Unknown error** | `{:error, _}` | Catch-all | `:failed` |

---

## Pattern: Retry with Backoff

For transient errors (network, API rate limits):

```elixir
defmodule MyApp.ResilientWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      call_external_api() |> process_response()
    end

    diverge from: call_external_api() do
      :timeout -> :retry                   # Network timeout, try again
      {:error, :rate_limited} -> :retry    # API limit, back off and retry
      {:error, :auth_failed} -> :failed    # Can't fix, terminate
    end
  end

  def call_external_api(ctx) do
    case ExternalAPI.request(ctx.inputs[:endpoint]) do
      {:ok, data} -> {:ok, data}
      {:error, :timeout} -> :timeout
      {:error, reason} -> {:error, reason}
    end
  end

  def process_response(_ctx, {:ok, data}) do
    {:ok, transform(data)}
  end
end
```

---

## Pattern: Graceful Degradation

When a step can fail but the workflow should continue:

```elixir
defmodule MyApp.DegradingWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_primary() |> fallback_on_error() |> continue_processing()
    end

    diverge from: fetch_primary() do
      {:error, _} -> skip_to(:continue_processing)  # Skip to post-fallback
    end
  end

  def fetch_primary(ctx) do
    case PrimaryDB.query(ctx.inputs[:query]) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :primary_down}
    end
  end

  def fallback_on_error(_ctx, {:ok, data}) do
    # Only runs when primary succeeds
    {:ok, data}
  end

  def continue_processing(ctx, fetch_result, _fallback) do
    data = case fetch_result do
      {:ok, d} -> d                    # Primary succeeded
      {:error, _} -> BackupDB.query(ctx.inputs[:query])  # Use backup
    end
    {:ok, process(data)}
  end
end
```

---

## Pattern: Multi-Step Saga with Compensation

For workflows that need to undo partial work on failure:

```elixir
defmodule MyApp.SagaWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      reserve_inventory() |> charge_payment() |> confirm_order()
    end

    diverge from: charge_payment() do
      {:error, :declined} -> back_to(:compensate_reservation)
    end
  end

  def reserve_inventory(ctx) do
    {:ok, Inventory.reserve(ctx.inputs[:items])}
  end

  # Compensation step (called on payment failure)
  def compensate_reservation(ctx, {:ok, reservation}) do
    Inventory.release(reservation.id)
    {:error, :payment_declined_and_compensated}
  end

  def charge_payment(_ctx, _reservation) do
    # ...
  end
end
```

---

## Dead Letter Queue (DLQ)

When a step exhausts its retries or matches `:failed` in a diverge, it goes to the DLQ:

```elixir
# Engine configuration
config :cerebelum,
  dlq_enabled: true,
  dlq_max_retries: 3,
  dlq_retry_delay_ms: 60_000   # 1 minute between retries
```

### DLQ Flow

```
Step fails
  → Diverge matches :retry → retry (up to max_retries)
  → Retries exhausted → DLQ
  → DLQ retries after delay (up to dlq_max_retries)
  → Still failing → ExecutionFailedEvent emitted
```

### Monitoring

```bash
# Check DLQ via API
curl https://cerebelum.zea.cl/api/v1/executions?status=failed \
  -H "Authorization: Bearer $TOKEN"
```

---

## Best Practices

| Do | Don't |
|---|---|
| Match specific errors before catch-all | Use `{:error, _}` as first clause |
| Use `:retry` only for transient errors | Retry validation errors |
| Implement compensation for multi-step changes | Assume partial work is safe to abandon |
| Set `max_retries` explicitly | Rely on defaults for critical workflows |
| Log diverge matches for observability | Silently swallow errors without audit trail |
| Let diverge match errors from `with` chains | Match on `{:error, reason}` directly |

---

## See Also

- [Diverge DSL](workflow-dsl/diverge.md) — Full diverge syntax and actions
- [Cycles & Jumps](workflow-dsl/cycles.md) — `back_to` and `skip_to` for error recovery
- [Event Sourcing Guide](event-sourcing.md) — Error events in the audit trail
