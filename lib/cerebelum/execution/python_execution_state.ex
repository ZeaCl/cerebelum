defmodule Cerebelum.Execution.PythonExecutionState do
  @moduledoc """
  State management for Python workflow executions using Cerebelum EventStore.

  Replaces the temporary ETS-based PythonExecutions with proper
  event-sourced persistence.
  """

  alias Cerebelum.EventStore
  alias Cerebelum.Execution.PythonStepCompletedEvent
  require Logger

  @doc """
  Start a new Python workflow execution.
  Appends ExecutionStartedEvent to EventStore.
  """
  def start(execution_id, worker_id, workflow_meta, first_step, result) do
    started_event = %PythonStepCompletedEvent{
      execution_id: execution_id,
      step_name: first_step["name"],
      step_label: first_step["label"],
      status: result["status"] || "ok",
      result: result["data"] || result,
      worker_id: worker_id,
      workflow_id: workflow_meta["id"],
      timestamp: DateTime.utc_now()
    }

    EventStore.append_sync(execution_id, started_event, 0)
    
    {:ok, build_state(execution_id, workflow_meta, worker_id, [started_event])}
  end

  @doc """
  Append a step result to an existing execution.
  """
  def append_step(execution_id, step, result, current_state) do
    # Calculate next version
    existing_events = EventStore.get_execution_events(execution_id)
    next_version = length(existing_events)

    event = %PythonStepCompletedEvent{
      execution_id: execution_id,
      step_name: step["name"],
      step_label: step["label"],
      status: result["status"] || "ok",
      result: result["data"] || result,
      worker_id: current_state[:worker_id],
      workflow_id: current_state[:workflow_id],
      timestamp: DateTime.utc_now()
    }

    EventStore.append_sync(execution_id, event, next_version)

    updated_events = existing_events ++ [event]
    {:ok, build_state(execution_id, current_state[:workflow_meta], current_state[:worker_id], updated_events)}
  end

  @doc """
  Reconstruct execution state from EventStore events.
  """
  def get(execution_id) do
    events = EventStore.get_execution_events(execution_id)

    if events == [] do
      {:error, :not_found}
    else
      first = List.first(events)
      event_data = first.event_data
      worker_id = event_data["worker_id"]
      workflow_id = event_data["workflow_id"]

      # Reconstruct workflow metadata from worker registry (has full step list)
      workflow_meta =
        case CerebelumCommunity.WorkerRegistry.get_workflow(workflow_id) do
          nil ->
            %{"id" => workflow_id, "label" => workflow_id, "steps" => []}

          wf ->
            wf
        end

      state = build_state(execution_id, workflow_meta, worker_id, events)
      {:ok, state}
    end
  end

  defp build_state(execution_id, workflow_meta, worker_id, events) do
    acc = Enum.reduce(events, %{results: %{}, current_step: nil, status: "running"}, fn event, acc ->
      data = extract_event_map(event)

      step_name = data["step_name"]
      step_status = data["status"]
      step_result = data["result"] || %{}

      %{
        results: if(step_name, do: Map.put(acc.results, step_name, step_result), else: acc.results),
        current_step: step_name || acc.current_step,
        status: if(step_status == "waiting_for_approval", do: "waiting_for_approval", else: acc.status)
      }
    end)

    %{
      execution_id: execution_id,
      worker_id: worker_id,
      workflow_id: workflow_meta["id"],
      workflow_meta: workflow_meta,
      current_step: acc.current_step,
      results: acc.results,
      status: acc.status,
      started_at: get_timestamp(List.first(events))
    }
  end

  # ── Event format normalizers ─────────────────────────

  @doc """
  Extracts a plain string-keyed map from any event format.

  Handles three formats:
    - DB record: %Event{event_data: %{"step_name" => ..., "result" => ...}}
    - Fresh struct: %PythonStepCompletedEvent{step_name: ..., result: ...}
    - Plain map: %{"step_name" => ..., "result" => ...}
  """
  defp extract_event_map(event) do
    cond do
      # DB record (Ecto schema) — data lives in event_data JSONB field
      is_struct(event) and Map.has_key?(event, :event_data) and is_map(event.event_data) ->
        event.event_data

      # Fresh struct (in-memory) — convert atom keys to string keys
      is_struct(event) ->
        event |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), v} end)

      # Already a plain map — pass through
      is_map(event) ->
        event

      true ->
        %{}
    end
  end

  defp get_timestamp(%{timestamp: ts}), do: ts
  defp get_timestamp(%{inserted_at: ts}), do: ts
  defp get_timestamp(_), do: DateTime.utc_now()
end
