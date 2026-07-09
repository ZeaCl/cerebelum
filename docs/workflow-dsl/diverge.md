# Diverge

Diverge handles **errors, timeouts, and retries** using pattern matching. It's the error-handling counterpart to `branch` (which handles conditional routing for successful results).

---

## Syntax

```elixir
workflow do
  timeline do
    step_a() |> step_b() |> step_c()
  end

  diverge from: step_a() do
    :timeout -> :retry
    {:error, :invalid_input} -> :failed
    {:error, _} -> :failed
  end
end
```

- `from: step_name()` — which step's errors to handle
- Each clause matches the step's return value
- Actions: `:retry`, `:failed`, `back_to(:step)`, `skip_to(:step)`, `continue()`

---

## Pattern Matching

Diverge clauses match against the **entire return value** of the step:

```elixir
diverge from: validate_order() do
  :timeout -> :retry                              # Match timeout atom
  {:error, :out_of_stock} -> back_to(:restock)    # Match specific error
  {:error, :payment_declined} -> :failed          # Fail immediately
  {:error, _} -> :failed                          # Catch-all for errors
end
```

Patterns are evaluated **in order** — the first match wins.

---

## Diverge Actions

| Action | Effect |
|---|---|
| `:retry` | Re-execute the same step (step count tracked for retry limits) |
| `:failed` | Terminate workflow immediately (`ExecutionFailedEvent`) |
| `back_to(:step_name)` | Jump to a previous step in the timeline |
| `skip_to(:step_name)` | Jump forward to a later step |
| `continue()` | Continue to the next step as if nothing happened |

---

## Complete Example

```elixir
defmodule MyApp.PaymentWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_cart() |> charge_payment() |> confirm_order() |> send_receipt()
    end

    diverge from: validate_cart() do
      {:error, :empty_cart} -> :failed
    end

    diverge from: charge_payment() do
      :timeout -> :retry                       # Network timeout, try again
      {:error, :insufficient_funds} -> :failed # Can't fix, terminate
      {:error, :gateway_error} -> :retry       # Transient error, retry
    end

    diverge from: confirm_order() do
      {:error, :inventory_gone} -> back_to(:validate_cart)  # Restart
    end
  end

  def validate_cart(ctx) do
    cart = CartService.get(ctx.inputs[:cart_id])
    if cart.items == [], do: {:error, :empty_cart}, else: {:ok, cart}
  end

  def charge_payment(_ctx, {:ok, cart}) do
    case PaymentGateway.charge(cart.total) do
      {:ok, charge} -> {:ok, charge}
      {:error, :timeout} -> :timeout
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm_order(_ctx, _cart, {:ok, charge}) do
    case InventoryService.reserve(charge.items) do
      :ok -> {:ok, %{order_id: "ORD-#{charge.id}"}}
      {:error, :gone} -> {:error, :inventory_gone}
    end
  end

  def send_receipt(_ctx, _cart, _charge, {:ok, order}) do
    EmailService.send_receipt(order.order_id)
    {:ok, %{sent: true, order_id: order.order_id}}
  end
end
```

---

## Retry Behavior

When a diverge matches `:retry`:

1. The step is re-executed immediately
2. Each retry increments an internal counter
3. The `max_retries` limit (default: 3, configurable per workflow) prevents infinite loops
4. On exhausting retries, the workflow fails with `StepFailedEvent`

```elixir
# Configurable via workflow (Elixir on-prem)
defmodule MyWorkflow do
  use Cerebelum.Workflow

  workflow max_retries: 5 do
    # ...
  end
end
```

---

## Diverge vs Branch

| | Diverge | Branch |
|---|---|---|
| **When evaluated** | On error/timeout return | On successful return |
| **Matches against** | Step return value tuple | Result value fields |
| **Used for** | Error handling, retry, failover | Business logic routing |
| **Actions** | `:retry`, `:failed`, `back_to`, `skip_to` | Path names (atoms) |

---

## See Also

- [Branch](branch.md) — Conditional routing for success cases
- [Cycles & Jumps](cycles.md) — `back_to`, `skip_to` in depth
- [Error Handling Guide](../guides/error-handling.md) — Patterns and best practices
