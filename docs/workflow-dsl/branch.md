# Branch

Branch adds **conditional routing** to your timeline. After a step executes, the branch evaluates the result and can take different paths.

---

## Syntax

```elixir
workflow do
  timeline do
    step_a() |> step_b() |> step_c()
  end

  branch after: step_b(), on: result do
    result.amount > 1000 -> :high_value_path
    result.amount > 0 -> :standard_path
    true -> :free_path
  end
end
```

- `after: step_name()` — which step triggers the branch
- `on: result` — the variable name for the step's result
- Each clause: `condition -> :path_name`

The last clause should use `true -> :default_path` as a catch-all.

---

## How It Works

When `step_b()` completes with `{:ok, result}`, the branch evaluates each condition in order. The first matching condition determines the **path**. The path is stored in the context and emitted as a `BranchEvaluated` event.

The branch result is available in the execution status:

```elixir
{:ok, status} = Cerebelum.get_execution_status(exec.id)
# => %{state: :completed, branch_path: :high_value_path, ...}
```

---

## Complete Example

```elixir
defmodule MyApp.RiskAssessment do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_credit_score() |> calculate_risk() |> approve_or_deny()
    end

    branch after: calculate_risk(), on: result do
      result.score >= 750 -> :auto_approve
      result.score >= 600 -> :manual_review
      true -> :auto_deny
    end
  end

  def fetch_credit_score(ctx) do
    score = CreditAPI.score(ctx.inputs[:user_id])
    {:ok, score}
  end

  def calculate_risk(_ctx, {:ok, score}) do
    risk = %{
      score: score,
      debt_ratio: 0.35,
      history_years: 5
    }
    {:ok, risk}
  end

  def approve_or_deny(_ctx, _score, {:ok, risk}) do
    # This step can inspect the execution context
    # or the branch path from status to customize behavior
    case risk.score do
      s when s >= 750 -> {:ok, %{decision: :approved, limit: 10_000}}
      s when s >= 600 -> {:ok, %{decision: :pending_review, limit: 0}}
      _ -> {:ok, %{decision: :denied, limit: 0}}
    end
  end
end
```

---

## Multiple Branches

You can have multiple `branch` blocks for different steps:

```elixir
workflow do
  timeline do
    validate() |> process_payment() |> ship() |> notify()
  end

  branch after: process_payment(), on: result do
    result.amount > 1000 -> :high_value
    true -> :standard
  end

  branch after: ship(), on: result do
    result.carrier == "express" -> :priority_tracking
    true -> :standard_tracking
  end
end
```

---

## Use Cases

| Pattern | Example |
|---|---|
| **Risk-based routing** | High amount → manual review, low → auto-approve |
| **Feature flags** | Flag on → new flow, flag off → legacy flow |
| **A/B testing** | User in group A → variant_1, group B → variant_2 |
| **Region-based logic** | EU user → GDPR flow, US user → standard flow |
| **Error classification** | Specific error → retry, generic error → DLQ |

---

## Benchmark Branching

The `CondEvaluator` module handles branch condition evaluation. Benchmarks show sub-microsecond evaluation times:

```bash
mix run lib/mix/tasks/benchmark.ex
# Branch evaluation: 0.8μs avg
```

---

## See Also

- [Diverge](diverge.md) — Pattern-matched error handling (different from branch)
- [Timeline](timeline.md) — Linear step sequences
- [Error Handling Guide](../guides/error-handling.md) — When to use branch vs diverge
