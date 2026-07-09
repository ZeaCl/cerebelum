# Tutorial: Error Handling Patterns

Practical error handling with diverge, retry, back_to, and DLQ. **Time: 10 minutes**.

---

## Pattern 1: Retry on Transient Errors

Network timeouts, rate limits, and temporary unavailability:

```elixir
defmodule MyApp.RetryWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      call_payment_gateway() |> process_payment()
    end

    diverge from: call_payment_gateway() do
      :timeout -> :retry                     # Network timeout → try again
      {:error, :rate_limited} -> :retry      # API limit → back off
      {:error, :gateway_down} -> :retry      # Transient → retry
      {:error, :auth_failed} -> :failed      # Permanent → fail
    end
  end

  def call_payment_gateway(ctx) do
    case PaymentGateway.charge(ctx.inputs[:amount]) do
      {:ok, charge} -> {:ok, charge}
      :timeout -> :timeout
      {:error, reason} -> {:error, reason}
    end
  end

  def process_payment(_ctx, {:ok, charge}) do
    {:ok, %{status: :paid, charge_id: charge.id}}
  end
end
```

---

## Pattern 2: Graceful Degradation with skip_to

When an optional step fails, skip ahead instead of failing:

```elixir
defmodule MyApp.AnalyticsWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_core_data() |> [enrich_from_ai(), enrich_from_cache()] |> generate_report()
    end

    diverge from: enrich_from_ai() do
      {:error, _} -> skip_to(:generate_report)  # AI down? Skip enrichment
    end

    diverge from: enrich_from_cache() do
      {:error, _} -> skip_to(:generate_report)  # Cache miss? Skip
    end
  end

  def fetch_core_data(ctx) do
    {:ok, Database.query(ctx.inputs[:query])}
  end

  def enrich_from_ai(_ctx, {:ok, data}) do
    case AIService.enrich(data) do
      {:ok, enriched} -> {:ok, enriched}
      {:error, _} -> {:error, :ai_unavailable}
    end
  end

  def enrich_from_cache(_ctx, {:ok, data}) do
    case Cache.get(data.id) do
      {:ok, cached} -> {:ok, cached}
      {:error, _} -> {:error, :cache_miss}
    end
  end

  def generate_report(_ctx, {:ok, data}, enrich_ai, enrich_cache) do
    # Handle potentially nil results from skipped steps
    ai_data = case enrich_ai do
      {:ok, d} -> d
      _ -> %{}
    end
    cache_data = case enrich_cache do
      {:ok, d} -> d
      _ -> %{}
    end

    report = ReportBuilder.build(data, ai_data, cache_data)
    {:ok, report}
  end
end
```

---

## Pattern 3: Saga with Compensation

Multi-step changes that need rollback on failure:

```elixir
defmodule MyApp.OrderSaga do
  use Cerebelum.Workflow

  workflow do
    timeline do
      reserve_inventory() |> charge_card() |> confirm_order()
    end

    diverge from: charge_card() do
      {:error, :declined} -> back_to(:release_inventory)
    end
  end

  def reserve_inventory(ctx) do
    reservation = Inventory.reserve(ctx.inputs[:items])
    {:ok, %{reservation_id: reservation.id, items: ctx.inputs[:items]}}
  end

  def release_inventory(_ctx, {:ok, reservation}) do
    # Compensation: release reserved items
    Inventory.release(reservation.reservation_id)
    {:error, :order_cancelled_insufficient_funds}
  end

  def charge_card(_ctx, {:ok, reservation}) do
    total = Enum.sum(reservation.items, &(&1.price))
    case PaymentGateway.charge(total) do
      {:ok, charge} -> {:ok, charge}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm_order(_ctx, _reservation, {:ok, charge}) do
    {:ok, OrderService.confirm(charge.id)}
  end
end
```

---

## Pattern 4: Exhaustive Error Handling

Handle every known error case explicitly:

```elixir
defmodule MyApp.RobustETL do
  use Cerebelum.Workflow

  workflow do
    timeline do
      extract() |> transform() |> load()
    end

    diverge from: extract() do
      :timeout -> :retry
      {:error, :source_unavailable} -> :failed
      {:error, :credentials_expired} -> :failed
      {:error, :empty_dataset} -> :failed
    end

    diverge from: transform() do
      {:error, :invalid_schema} -> :failed
      {:error, :type_mismatch} -> :failed
      {:error, :row_too_large} -> skip_to(:load)  # Skip bad row
    end

    diverge from: load() do
      {:error, :target_full} -> :failed
      {:error, :connection_lost} -> :retry
      {:error, :duplicate_key} -> continue()  # Already loaded, safe to continue
    end
  end

  # ... step implementations
end
```

---

## Pattern 5: Python Error Handling

```python
from cerebelum import step, workflow


@step
async def call_api(context, **kwargs):
    """Step with comprehensive error handling."""
    endpoint = context.inputs.get("endpoint")
    max_retries = context.inputs.get("max_retries", 3)

    for attempt in range(max_retries + 1):
        try:
            response = await external_api_call(endpoint)
            return {"status": "ok", "data": response}
        except TimeoutError:
            if attempt == max_retries:
                return {"status": "timeout", "attempts": attempt + 1}
            await asyncio.sleep(2 ** attempt)  # Exponential backoff
        except AuthError:
            return {"status": "auth_failed"}  # Don't retry auth errors
        except Exception as e:
            if attempt == max_retries:
                return {"status": "failed", "error": str(e)}
            await asyncio.sleep(1)

    return {"status": "exhausted"}


@step
async def process_result(context, call_api=None, **kwargs):
    result = call_api or {}
    status = result.get("status", "unknown")

    if status == "ok":
        return {"success": True, "data": result["data"]}
    elif status == "timeout":
        return {"success": False, "error": "timeout_after_retries"}
    elif status == "auth_failed":
        return {"success": False, "error": "authentication"}
    else:
        return {"success": False, "error": status}


@workflow
def resilient_api_workflow(wf):
    wf.timeline(call_api >> process_result)
```

---

## Best Practices Summary

| Situation | Technique |
|---|---|
| Network timeout | Diverge with `:retry` |
| API rate limit | Diverge with `:retry` + backoff in step |
| Optional service down | Diverge with `skip_to` |
| Multi-step rollback | Diverge with `back_to` + compensation step |
| Permanent error | Diverge with `:failed` |
| Unknown error | Catch-all `{:error, _}` → `:failed` |

---

## See Also

- [Diverge DSL](../workflow-dsl/diverge.md) — Full diverge syntax
- [Error Handling Guide](../guides/error-handling.md) — Patterns reference
- [Cycles & Jumps](../workflow-dsl/cycles.md) — back_to, skip_to, continue
