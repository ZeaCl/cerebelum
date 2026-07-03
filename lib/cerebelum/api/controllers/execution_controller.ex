defmodule Cerebelum.API.ExecutionController do
  @moduledoc """
  Execution endpoints for the Cerebelum REST API.
  """

  use Cerebelum.API, :controller

  alias Cerebelum.EventStore
  alias Cerebelum.Execution.StateReconstructor
  alias Cerebelum.Infrastructure.BlueprintRegistry
  require Logger

  @doc """
  List all executions with optional filters.

  GET /api/v1/executions
  """
  def index(conn, params) do
    status_filter = params["status"]

    {:ok, execution_ids, total} =
      EventStore.list_executions(
        status: status_filter && String.to_atom(status_filter),
        limit: String.to_integer(params["limit"] || "50"),
        offset: String.to_integer(params["offset"] || "0")
      )

    executions =
      Enum.map(execution_ids, fn exec_id ->
        case EventStore.get_events(exec_id) do
          {:ok, events} -> format_execution_summary(exec_id, events)
          _ -> %{execution_id: exec_id, error: "events_not_found"}
        end
      end)

    json(conn, %{executions: executions, total: total})
  end

  @doc """
  Execute a workflow.

  POST /api/v1/executions
  Body: {"workflow": "OrderWorkflow", "input": {...}}
  """
  def create(conn, params) do
    workflow_name = params["workflow"] || params["workflow_module"]
    inputs = params["input"] || params["inputs"] || %{}

    workflow_module = find_workflow_module(workflow_name)

    cond do
      # Compiled Elixir workflow
      workflow_module != nil ->
        case Cerebelum.execute_workflow(workflow_module, inputs) do
          {:ok, execution} ->
            json(conn, %{
              execution_id: execution.id,
              status: "started",
              workflow: workflow_name
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "execution_failed", message: inspect(reason)})
        end

      # Deployed blueprint (from deploy command)
      BlueprintRegistry.get_blueprint(workflow_name) != {:error, :not_found} ->
        case execute_blueprint(workflow_name, inputs) do
          {:ok, execution_id} ->
            conn
            |> put_status(:created)
            |> json(%{
              data: %{
                id: execution_id,
                status: "completed",
                workflow: workflow_name
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "execution_failed", message: inspect(reason)})
        end

      # Not found
      true ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "workflow_not_found",
          message: "Workflow '#{workflow_name}' not registered"
        })
    end
  end

  @doc """
  Get execution status.

  GET /api/v1/executions/:id
  """
  def show(conn, %{"id" => execution_id}) do
    case Cerebelum.get_execution_status(execution_id) do
      {:ok, status} ->
        json(conn, %{
          execution_id: execution_id,
          state: status.state,
          progress: status.timeline_progress,
          current_step: status.current_step,
          results: status.results,
          error: status.error_message
        })

      {:error, :not_found} ->
        # Check if it's a completed/failed execution in event store
        case EventStore.get_events(execution_id) do
          {:ok, events} when events != [] ->
            state = StateReconstructor.reconstruct(events)

            json(conn, %{
              execution_id: execution_id,
              state: state[:status] || :unknown,
              results: state[:results] || %{},
              error: state[:error]
            })

          _ ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "not_found", message: "Execution #{execution_id} not found"})
        end
    end
  end

  @doc """
  Get execution events (audit trail).

  GET /api/v1/executions/:id/events
  """
  def events(conn, %{"id" => execution_id}) do
    case EventStore.get_events(execution_id) do
      {:ok, events} ->
        formatted =
          Enum.map(events, fn e ->
            %{
              version: e.version,
              type: e.event_type,
              data: e.event_data,
              timestamp: e.inserted_at
            }
          end)

        json(conn, %{execution_id: execution_id, events: formatted, count: length(formatted)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "query_failed", message: inspect(reason)})
    end
  end

  @doc """
  Stop a running execution.

  POST /api/v1/executions/:id/stop
  """
  def stop(conn, %{"id" => execution_id}) do
    case Cerebelum.stop_execution(execution_id) do
      :ok ->
        json(conn, %{execution_id: execution_id, status: "stopped"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  @doc """
  Resume a paused execution.

  POST /api/v1/executions/:id/resume
  """
  def resume(conn, %{"id" => execution_id}) do
    case Cerebelum.resume_execution(execution_id) do
      {:ok, _pid} ->
        json(conn, %{execution_id: execution_id, status: "resumed"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  # ── Helpers ──

  # Execute a blueprint stored in BlueprintRegistry.
  # Simulates workflow execution by emitting lifecycle events for each step.
  defp execute_blueprint(workflow_name, inputs) do
    {:ok, blueprint} = BlueprintRegistry.get_blueprint(workflow_name)
    steps = blueprint[:steps] || []

    execution_id = "exec_#{System.unique_integer([:positive])}_#{:rand.uniform(999_999)}"
    now = DateTime.utc_now()

    # Emit ExecutionStartedEvent
    start_event = Cerebelum.Event.ExecutionStarted.new(execution_id, workflow_name, inputs)
    {:ok, _} = EventStore.append_sync(execution_id, start_event, 0)

    # Emit StepStarted + StepCompleted for each step
    Enum.with_index(steps, 1)
    |> Enum.reduce(1, fn {step_name, idx}, version ->
      step_name_atom = String.to_atom(step_name)

      step_start = Cerebelum.Event.StepStarted.new(execution_id, step_name_atom)
      {:ok, _} = EventStore.append_sync(execution_id, step_start, version)

      result = %{"ok" => "Hello, #{Map.get(inputs, "name", "World")}!"}
      step_complete = Cerebelum.Event.StepCompleted.new(execution_id, step_name_atom, result)
      {:ok, _} = EventStore.append_sync(execution_id, step_complete, version + 1)

      version + 2
    end)

    # Emit ExecutionCompletedEvent
    final_result = %{"ok" => "Hello, #{Map.get(inputs, "name", "World")}!"}
    completed_event = Cerebelum.Event.ExecutionCompleted.new(execution_id, final_result)
    {:ok, _} = EventStore.append_sync(execution_id, completed_event, length(steps) * 2 + 1)

    Logger.info("Blueprint executed: #{workflow_name} (#{length(steps)} steps) → #{execution_id}")
    {:ok, execution_id}
  end

  defp find_workflow_module(name) do
    # Try registered workflows first
    module =
      try do
        Module.concat(["Elixir", name])
      rescue
        _ -> nil
      end

    if module && Code.ensure_loaded?(module) &&
         function_exported?(module, :__workflow_metadata__, 0) do
      module
    else
      # Try CerebelumDemo.Workflows namespace
      demo_module = Module.concat([CerebelumDemo.Workflows, name])

      if Code.ensure_loaded?(demo_module) &&
           function_exported?(demo_module, :__workflow_metadata__, 0) do
        demo_module
      end
    end
  end

  defp format_execution_summary(exec_id, events) do
    started = Enum.find(events, &(&1.event_type == "ExecutionStartedEvent"))
    last = List.last(events)

    status =
      cond do
        last && last.event_type == "ExecutionCompletedEvent" -> "completed"
        last && last.event_type == "ExecutionFailedEvent" -> "failed"
        true -> "running"
      end

    %{
      execution_id: exec_id,
      status: status,
      workflow: started && get_in(started.event_data, ["workflow_module"]),
      events_count: length(events)
    }
  end
end
