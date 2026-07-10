# Timeline

The timeline is the **only required** DSL block. It defines the ordered sequence of steps in your workflow.

---

## Syntax

```elixir
workflow do
  timeline do
    step_a() |> step_b() |> step_c() |> step_d()
  end
end
```

The `|>` (pipe) operator chains steps in order of execution.

---

## How It Works

Each step name in the timeline maps to a function in the workflow module. The Execution Engine calls them in sequence, passing results forward:

```elixir
defmodule MyApp.DataPipeline do
  use Cerebelum.Workflow

  workflow do
    timeline do
      fetch_data() |> transform() |> validate() |> store()
    end
  end

  # Step 1
  def fetch_data(ctx) do
    # Access inputs via ctx.inputs
    source = ctx.inputs[:source]
    data = ExternalAPI.fetch(source)
    {:ok, data}
  end

  # Step 2 — receives fetch_data result
  def transform(_ctx, {:ok, data}) do
    transformed = data |> Enum.map(&normalize/1)
    {:ok, transformed}
  end

  # Step 3 — receives previous 2 results
  def validate(_ctx, _fetch, {:ok, data}) do
    if Enum.all?(data, &valid?/1) do
      {:ok, data}
    else
      {:error, :invalid_data}
    end
  end

  # Step 4 — receives all previous results
  def store(_ctx, _fetch, _transform, {:ok, data}) do
    Database.insert_all(data)
    {:ok, %{stored: length(data)}}
  end
end
```

---

## Result Types

Each step must return one of these:

| Return | Meaning |
|---|---|
| `{:ok, value}` | Success, continue to next step |
| `{:error, reason}` | Error, triggers diverge or fails workflow |
| `:timeout` | Timeout, triggers diverge or fails workflow |
| `{:wait_for_approval, opts, data}` | Pause for human approval |
| `FlowAction.*` | Flow control action |

---

## Context

Every step receives the immutable `context` as the first argument:

```elixir
def my_step(context) do
  context.inputs        # Initial inputs map
  context.execution_id  # Unique execution ID
  context.organization_id  # Org scope (cloud mode)
  context.correlation_id   # Distributed tracing
  context.tags          # [] of tags
end
```

The context is **read-only** — steps cannot modify it. Produce new data via return values.

---

## Complete Example

```elixir
defmodule MyApp.OnboardingWorkflow do
  use Cerebelum.Workflow

  workflow do
    timeline do
      create_user() |> send_welcome_email() |> create_workspace() |> notify_admin()
    end
  end

  def create_user(ctx) do
    user = %{
      email: ctx.inputs[:email],
      name: ctx.inputs[:name],
      created_at: DateTime.utc_now()
    }
    {:ok, user}
  end

  def send_welcome_email(_ctx, {:ok, user}) do
    EmailService.send(:welcome, user.email, %{name: user.name})
    {:ok, user}
  end

  def create_workspace(_ctx, _create_user, {:ok, user}) do
    workspace = Workspace.create(user)
    {:ok, %{user: user, workspace: workspace}}
  end

  def notify_admin(_ctx, _cu, _swe, {:ok, %{user: user, workspace: ws}}) do
    Notification.send(:admin, "New user #{user.email} in #{ws.name}")
    {:ok, %{user_id: user.id, workspace_id: ws.id}}
  end
end
```

---

## See Also

- [Branch](branch.md) — Add conditional routing to your timeline
- [Diverge](diverge.md) — Handle errors in timeline steps
- [Cycles & Jumps](cycles.md) — Loop back or skip ahead
