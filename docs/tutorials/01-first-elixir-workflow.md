# Tutorial: First Elixir Workflow

Build and run your first deterministic workflow in Elixir. **Time: 5 minutes**.

---

## Prerequisites

- Elixir 1.18+
- PostgreSQL running (for event store)
- Cerebelum dependency added

```elixir
# mix.exs
def deps do
  [{:cerebelum, "~> 0.1.0"}]
end
```

```bash
mix deps.get
```

---

## Step 1: Define a Workflow

Create `lib/my_app/hello_workflow.ex`:

```elixir
defmodule MyApp.HelloWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      greet() |> personalize() |> deliver()
    end
  end

  # Step 1: Generate greeting
  def greet(ctx) do
    # Access inputs from context
    name = ctx.inputs[:name] || "World"
    {:ok, "Hello, #{name}!"}
  end

  # Step 2: Add personalization
  def personalize(_ctx, {:ok, greeting}) do
    personalized = %{
      message: greeting,
      timestamp: DateTime.utc_now(),
      emoji: "👋"
    }
    {:ok, personalized}
  end

  # Step 3: Deliver the message
  def deliver(_ctx, _greet, {:ok, personalized}) do
    # In a real app, this would send email, push notification, etc.
    IO.puts("📨 Delivering: #{personalized.message}")
    {:ok, %{delivered: true, message: personalized.message}}
  end
end
```

### What's happening

1. `use Cerebelum.Workflow` — imports DSL macros and sets up metadata
2. `workflow do ... end` — the DSL block defining the workflow structure
3. `timeline do ... end` — ordered sequence of steps
4. `greet() |> personalize() |> deliver()` — pipe-chained steps
5. Each step function receives context + previous results (dependency injection)

---

## Step 2: Execute

In an `iex -S mix` session:

```elixir
# Execute the workflow
{:ok, exec} = Cerebelum.execute_workflow(MyApp.HelloWorkflow, %{name: "Alice"})

# Check status
{:ok, status} = Cerebelum.get_execution_status(exec.id)

IO.inspect(status.state)
# => :completed

IO.inspect(status.results)
# => %{
#   greet: {:ok, "Hello, Alice!"},
#   personalize: {:ok, %{message: "Hello, Alice!", emoji: "👋"}},
#   deliver: {:ok, %{delivered: true, message: "Hello, Alice!"}}
# }

IO.inspect(status.timeline_progress)
# => "3/3"
```

---

## Step 3: Add Error Handling

Enhance the workflow with a diverge to handle edge cases:

```elixir
defmodule MyApp.RobustHelloWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_name() |> greet() |> deliver()
    end

    # Add error handling for empty names
    diverge from: validate_name() do
      {:error, :empty_name} -> :failed
      {:error, :too_long} -> :failed
    end
  end

  def validate_name(ctx) do
    name = ctx.inputs[:name] || ""

    cond do
      name == "" -> {:error, :empty_name}
      String.length(name) > 100 -> {:error, :too_long}
      true -> {:ok, name}
    end
  end

  def greet(_ctx, {:ok, name}) do
    {:ok, "Hello, #{name}!"}
  end

  def deliver(_ctx, _validate, {:ok, greeting}) do
    IO.puts("📨 #{greeting}")
    {:ok, %{delivered: true}}
  end
end
```

Test the error path:

```elixir
{:ok, exec} = Cerebelum.execute_workflow(MyApp.RobustHelloWorkflow, %{name: ""})
{:ok, status} = Cerebelum.get_execution_status(exec.id)

IO.inspect(status.state)
# => :failed
```

---

## Step 4: Add Conditional Branching

Add a branch to customize behavior based on time of day:

```elixir
defmodule MyApp.TimeAwareHelloWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      check_time() |> greet() |> deliver()
    end

    branch after: check_time(), on: result do
      result.hour < 12 -> :morning
      result.hour < 18 -> :afternoon
      true -> :evening
    end
  end

  def check_time(_ctx) do
    {:ok, %{hour: DateTime.utc_now().hour}}
  end

  def greet(_ctx, {:ok, time}) do
    greeting = cond do
      time.hour < 12 -> "Good morning"
      time.hour < 18 -> "Good afternoon"
      true -> "Good evening"
    end
    {:ok, "#{greeting}, #{ctx.inputs[:name] || "friend"}!"}
  end

  def deliver(_ctx, _time, {:ok, greeting}) do
    {:ok, %{delivered: true, message: greeting}}
  end
end
```

---

## Next Steps

- [Timeline DSL](../workflow-dsl/timeline.md) — Step sequences in depth
- [Diverge DSL](../workflow-dsl/diverge.md) — Full error handling reference
- [Branch DSL](../workflow-dsl/branch.md) — Conditional routing patterns
- [Error Handling Guide](../guides/error-handling.md) — Best practices
