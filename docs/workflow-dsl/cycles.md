# Cycles & Jumps

Cerebelum supports **non-linear execution** via flow actions: `back_to`, `skip_to`, and `continue`. These enable retry loops, fast-forward, and cycle patterns — something Temporal and DAG-based engines cannot do natively.

---

## Flow Actions Reference

```elixir
# Continue to the next step (no-op, explicit)
FlowAction.continue()

# Jump back to a previous step
FlowAction.back_to(:step_name)

# Jump forward to a later step
FlowAction.skip_to(:step_name)

# Terminate immediately with error
FlowAction.failed(:reason)
```

Flow actions can be returned from any step or diverge/branch clause.

---

## back_to — Retry Loops

Jump back to a previous step. Useful for retry loops with backoff:

```elixir
defmodule MyApp.RetryWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_data() |> validate_data() |> process()
    end

    diverge from: validate_data() do
      {:error, :transient} -> back_to(:fetch_data)   # Refetch and try again
      {:error, :permanent} -> :failed
    end
  end

  def fetch_data(ctx) do
    data = ExternalAPI.fetch(ctx.inputs[:url])
    {:ok, data}
  end

  def validate_data(_ctx, {:ok, data}) do
    if valid_format?(data) do
      {:ok, data}
    else
      # Transient — maybe API returned stale format
      {:error, :transient}
    end
  end

  def process(_ctx, _fetch, {:ok, data}) do
    {:ok, Database.insert(data)}
  end
end
```

---

## skip_to — Fast-Forward

Skip ahead to a later step, bypassing intermediate ones:

```elixir
defmodule MyApp.CacheWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      check_cache() |> fetch_from_api() |> transform_data() |> store_cache()
    end

    diverge from: check_cache() do
      {:ok, %{hit: true, data: data}} -> skip_to(:store_cache)  # Skip fetch+transform
      {:ok, %{hit: false}} -> continue()
    end
  end

  def check_cache(ctx) do
    case Cache.get(ctx.inputs[:key]) do
      nil -> {:ok, %{hit: false}}
      data -> {:ok, %{hit: true, data: data}}
    end
  end

  def fetch_from_api(ctx, {:ok, %{hit: false}}) do
    {:ok, ExternalAPI.fetch(ctx.inputs[:key])}
  end

  def transform_data(_ctx, _cache, {:ok, raw}) do
    {:ok, DataTransformer.process(raw)}
  end

  def store_cache(ctx, cache_result, api, transformed) do
    data =
      case cache_result do
        {:ok, %{hit: true, data: d}} -> d               # Cache hit
        {:ok, _} -> case transformed do                  # Cache miss
          {:ok, d} -> d
          _ -> api |> elem(1)  # Use raw if no transform executed
        end
      end

    Cache.put(ctx.inputs[:key], data)
    {:ok, %{cached: true}}
  end
end
```

⚠️ **Important**: When using `skip_to`, skipped steps still appear in the timeline, but their functions are never called. The step function for the target step must handle potentially `nil` values from skipped dependencies.

---

## Cycle Detection

Cerebelum performs **compile-time cycle detection** on the DSL. Infinite loops are prevented:

```elixir
# ❌ This fails to compile: cycle detected
diverge from: step_b() do
  {:error, _} -> back_to(:step_c)
end

diverge from: step_c() do
  {:error, _} -> back_to(:step_b)
end
# Compile error: "Circular back_to detected: step_b ↔ step_c"
```

The validator builds a dependency graph and detects cycles across diverge/branch actions at compile time.

---

## Event Tracking

Every jump is tracked as a domain event:

| Action | Event |
|---|---|
| `back_to(:step_name)` | `JumpExecutedEvent` with `type: "back_to"` |
| `skip_to(:step_name)` | `JumpExecutedEvent` with `type: "skip_to"` |
| `continue()` | No separate event (continues to next step) |

These events form part of the event sourcing audit trail, enabling **complete replay** of non-linear workflows.

---

## Best Practices

| Do | Don't |
|---|---|
| Use `back_to` for bounded retries | Create unbounded retry loops without limits |
| Use `skip_to` for cache hits / early exits | Skip past steps with required side effects |
| Let compile-time validation catch cycles | Assume runtime will detect infinite loops |
| Check for `nil` results from skipped steps | Assume all previous results are present |
| Track retry count manually if needed | Rely on implicit retry limits for all cases |

---

## See Also

- [Diverge](diverge.md) — Where most `back_to`/`skip_to` are defined
- [Branch](branch.md) — Alternative routing for success cases
- [Error Handling Guide](../guides/error-handling.md) — Retry patterns
