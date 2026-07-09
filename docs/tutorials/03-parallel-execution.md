# Tutorial: Parallel Execution

Run multiple steps concurrently to improve throughput. **Time: 8 minutes**.

---

## Why Parallel?

For independent operations (multiple API calls, database queries, file processing), parallel execution reduces total time from **sum of durations** to **max duration**.

```
Sequential:  A(1s) → B(2s) → C(0.5s)  = 3.5s
Parallel:    [A(1s), B(2s), C(0.5s)]   = 2.0s  (42% faster)
```

---

## Elixir: Parallel Execution

### Basic Parallel

```elixir
defmodule MyApp.ParallelPipeline do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_user() |> [enrich_profile(), check_eligibility()] |> process()
    end
  end

  # Sequential step
  def fetch_user(ctx) do
    {:ok, UserService.get(ctx.inputs[:user_id])}
  end

  # These run in parallel after fetch_user completes
  def enrich_profile(_ctx, {:ok, user}) do
    {:ok, ProfileService.enrich(user)}
  end

  def check_eligibility(_ctx, {:ok, user}) do
    {:ok, CreditService.check(user)}
  end

  # Runs after both parallel steps complete
  def process(_ctx, _fetch, {:ok, profile}, {:ok, eligibility}) do
    decision = if eligibility[:score] >= 700, do: :approved, else: :review
    {:ok, %{profile: profile, decision: decision}}
  end
end
```

### Parallel with Branch

```elixir
workflow do
  timeline do
    validate_inputs()
    |> [call_api_a(), call_api_b(), call_api_c()]
    |> aggregate_results()
  end

  branch after: aggregate_results(), on: result do
    result.total > 1000 -> :high_volume
    true -> :normal
  end
end
```

### Events for Parallel Execution

```
ParallelStartedEvent
ParallelTaskCompletedEvent [task: enrich_profile, duration: 1.2s]
ParallelTaskCompletedEvent [task: check_eligibility, duration: 0.8s]
ParallelCompletedEvent
```

---

## Python: Parallel Execution

### Basic Parallel

```python
from cerebelum import step, workflow
import asyncio


@step
async def fetch_user(context, **kwargs):
    await asyncio.sleep(0.3)
    return {"id": 42, "name": "Alice"}


@step
async def enrich_profile(context, fetch_user=None, **kwargs):
    await asyncio.sleep(1.0)  # Takes 1 second
    user = fetch_user or {}
    return {"profile": {**user, "score": 720}}


@step
async def check_eligibility(context, fetch_user=None, **kwargs):
    await asyncio.sleep(0.8)  # Takes 0.8 seconds
    user = fetch_user or {}
    return {"eligible": user.get("score", 0) >= 700}


@step
async def process(context, enrich_profile=None, check_eligibility=None, **kwargs):
    profile = enrich_profile or {}
    eligibility = check_eligibility or {}
    return {
        "user": profile.get("profile", {}),
        "decision": "approved" if eligibility.get("eligible") else "review"
    }


@workflow
def parallel_pipeline(wf):
    # enrich_profile and check_eligibility run concurrently (~1.0s total)
    wf.timeline(fetch_user >> [enrich_profile, check_eligibility] >> process)
```

### Fan-out / Fan-in

```python
@step
async def fetch_all_sources(context, **kwargs):
    # This step fans out to parallel API calls internally
    sources = ["users", "orders", "products"]
    results = await asyncio.gather(*[fetch_source(s) for s in sources])
    return {"sources": results}


@step
async def aggregate_all(context, fetch_all_sources=None, **kwargs):
    data = fetch_all_sources or {}
    sources = data.get("sources", [])
    return {"total_records": sum(s.get("count", 0) for s in sources)}


@workflow
def fan_out_workflow(wf):
    wf.timeline(fetch_all_sources >> aggregate_all)
```

---

## Performance Comparison

```bash
# Elixir benchmark
mix run lib/mix/tasks/benchmark.ex
```

| Pattern | Sequential | Parallel | Improvement |
|---|---|---|---|
| 2 steps (1s each) | 2.0s | 1.0s | 50% |
| 3 steps (1s, 2s, 0.5s) | 3.5s | 2.0s | 42% |
| 5 steps (0.5s each) | 2.5s | 0.5s | 80% |

---

## Best Practices

| Do | Don't |
|---|---|
| Parallelize independent I/O-bound steps | Parallelize CPU-bound steps (no benefit) |
| Clear dependency structure (A → [B, C] → D) | Nested parallel blocks exceeding 2 levels |
| Handle partial failures in `process()` | Assume all parallel steps succeed |
| Set timeouts for external calls | Unbounded parallel waits |

---

## Next Steps

- [First Elixir Workflow](01-first-elixir-workflow.md) — Sequential workflow tutorial
- [Error Handling Patterns](04-error-handling.md) — Handle failures in parallel steps
- [Workflow DSL Overview](../workflow-dsl/overview.md) — Full DSL reference
