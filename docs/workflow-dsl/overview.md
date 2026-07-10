# Workflow DSL — Overview

The Cerebelum Workflow DSL defines deterministic workflows using Elixir macros. Each workflow is a module that compiles into metadata (`__workflow_metadata__/0`) consumed by the Execution Engine.

---

## Anatomy of a Workflow

```elixir
defmodule MyApp.OrderWorkflow do
  use Cerebelum.Workflow

  workflow do
    # 1. Timeline — ordered steps
    timeline do
      validate_order() |> check_inventory() |> process_payment() |> ship_order() |> notify()
    end

    # 2. Diverge — error handling / retry
    diverge from: validate_order() do
      :timeout -> :retry
      {:error, :invalid_order} -> :failed
    end

    # 3. Branch — conditional routing
    branch after: process_payment(), on: result do
      result.amount > 1000 -> :high_value_path
      true -> :standard_path
    end
  end

  # Step implementations
  def validate_order(ctx), do: # ...
  def check_inventory(ctx, prev_result), do: # ...
  # ...
end
```

---

## DSL Blocks

| Block | Purpose | Required |
|---|---|---|
| `timeline do ... end` | Ordered sequence of steps | **Yes** |
| `diverge from: step() do ... end` | Error/pattern-matched branching | No |
| `branch after: step(), on: result do ... end` | Conditional routing by result | No |

---

## Step Dependency Injection

Cerebelum automatically injects previous step results. Step functions receive **context + all previous results**:

```elixir
# Step 1: receives only context
def step1(context), do: {:ok, compute(context.inputs)}

# Step 2: receives context + step1 result
def step2(context, step1_result), do: {:ok, process(step1_result)}

# Step 3: receives context + step1 + step2 results
def step3(context, step1_result, step2_result), do: {:ok, combine(step1_result, step2_result)}

# Step 4: receives context + all 3 previous results
def step4(context, step1, step2, step3), do: {:ok, finalize(step1, step2, step3)}
```

🔍 **Tip**: Pattern match on `{:ok, value}` tuples from previous steps to extract data.

---

## Flow Control Actions

Steps (or diverge/branch blocks) return **flow control actions** that instruct the engine what to do next:

| Action | Meaning | Use Case |
|---|---|---|
| `{:ok, result}` | Continue to next step (normal) | Every successful step |
| `{:error, reason}` | Fail with error | Validation failure, API error |
| `:timeout` | Timeout signal | External API timeout |
| `FlowAction.continue()` | Continue to next step | Explicit continue |
| `FlowAction.back_to(:step_name)` | Jump back to a previous step | Retry loops |
| `FlowAction.skip_to(:step_name)` | Jump forward to a step | Fast-forward |
| `FlowAction.failed(:reason)` | Terminate immediately | Unrecoverable error |

---

## Metadata

At compile time, the DSL produces this metadata structure:

```elixir
%{
  timeline: [:validate_order, :check_inventory, :process_payment, :ship_order, :notify],
  diverges: %{
    validate_order: [
      %{match: :timeout, action: :retry},
      %{match: {:error, :invalid_order}, action: :failed}
    ]
  },
  branches: %{
    process_payment: [
      %{condition: "result.amount > 1000", path: :high_value_path},
      %{condition: "true", path: :standard_path}
    ]
  },
  version: "abc123def456..."
}
```

The version is a SHA256 of the module bytecode — used for workflow versioning and event sourcing replay.

---

## Compile-Time Validation

The `Cerebelum.Workflow.Validator` checks at compile time:

- All steps in timeline have corresponding functions
- Diverge/branch reference steps that exist in the timeline
- No circular references in flow actions
- Pattern matches in diverge are exhaustive

Invalid workflows **fail to compile**.

---

## See Also

- [Timeline](timeline.md) — Step sequences in depth
- [Branch](branch.md) — Conditional routing
- [Diverge](diverge.md) — Error handling + retry
- [Cycles & Jumps](cycles.md) — `back_to`, `skip_to`, `continue`
- [Error Handling Guide](../guides/error-handling.md) — Patterns
