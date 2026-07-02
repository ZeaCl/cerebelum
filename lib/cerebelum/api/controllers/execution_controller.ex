defmodule Cerebelum.API.ExecutionController do
  @moduledoc """
  REST API Controller for execution endpoints.

  Provides REST API for querying, starting, stopping, and resuming workflow executions.
  """

  use Cerebelum.API, :controller
  require Logger

  alias Cerebelum.EventStore
  alias Cerebelum.Execution.StateReconstructor
  alias Cerebelum.Execution.PythonExecutionState
  alias Cerebelum.Workflow.Registry

  @doc """
  GET /api/v1/executions

  List all executions with pagination.
  """
  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    per_page = String.to_integer(params["per_page"] || "20")
    per_page = min(per_page, 100)
    offset = (page - 1) * per_page

    case EventStore.list_executions(limit: per_page, offset: offset) do
      {:ok, execution_ids, total} ->
        executions_data =
          Enum.map(execution_ids, fn exec_id ->
            events = EventStore.get_execution_events(exec_id)
            serialize_execution_summary(exec_id, events)
          end)

        response = %{
          data: executions_data,
          meta: %{
            pagination: %{
              page: page,
              per_page: per_page,
              total: total
            }
          }
        }

        json(conn, response)

      {:error, reason} ->
        Logger.error("Failed to list executions: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "Failed to list executions"})
    end
  end

  @doc """
  POST /api/v1/executions

  Execute a registered workflow with inputs.
  """
  def create(conn, params) do
    workflow_module_str = params["workflow_module"]
    inputs = params["inputs"] || %{}
    opts = params["opts"] || %{}

    if is_nil(workflow_module_str) or workflow_module_str == "" do
      conn
      |> put_status(400)
      |> json(%{error: "Missing required parameter: workflow_module"})
    else
      case find_registered_workflow(workflow_module_str) do
        {:ok, module} ->
          # Elixir-native workflow
          dispatch_elixir_workflow(conn, module, inputs, opts)

        {:python, worker_id, worker_url, workflow_meta} ->
          # Python worker workflow
          dispatch_python_workflow(conn, worker_id, worker_url, workflow_meta, inputs, opts)

        {:error, :not_found} ->
          conn
          |> put_status(400)
          |> json(%{error: "Unknown or unregistered workflow module: #{workflow_module_str}"})
      end
    end
  end

  @doc """
  GET /api/v1/executions/:id

  Get execution details with full state reconstruction.
  """
  def show(conn, %{"id" => execution_id}) do
    # Try Python execution first
    case PythonExecutionState.get(execution_id) do
      {:ok, py_state} ->
        show_python_execution(conn, py_state)

      {:error, :not_found} ->
        # Fall back to Elixir execution
        show_elixir_execution(conn, execution_id)
    end
  end

  defp show_python_execution(conn, state) do
    workflow_meta = state.workflow_meta || %{}
    visible_steps = Enum.reject(workflow_meta["steps"] || [], & &1["hidden"])
    current_step_name = state.current_step

    current_label =
      Enum.find_value(workflow_meta["steps"] || [], fn s ->
        if s["name"] == current_step_name, do: s["label"]
      end) || current_step_name || "unknown"

    current_idx =
      Enum.find_index(visible_steps, fn s -> s["name"] == current_step_name end)

    json(conn, %{
      data: %{
        id: state.execution_id,
        status: state.status,
        workflow_id: state.workflow_id,
        current_step: current_step_name,
        current_step_label: current_label,
        visible_step: (current_idx || 0) + 1,
        total_visible_steps: length(visible_steps),
        results: state.results || %{},
        started_at: state.started_at,
        worker_id: state.worker_id
      }
    })
  end

  defp show_elixir_execution(conn, execution_id) do
    case StateReconstructor.reconstruct(execution_id) do
      {:ok, state} ->
        workflow_meta = get_workflow_metadata(state)
        visible_steps = Enum.reject(workflow_meta["steps"] || [], & &1["hidden"])
        current_step_name = state.current_step && to_string(state.current_step)

        current_label =
          Enum.find_value(workflow_meta["steps"] || [], fn s ->
            if s["name"] == current_step_name, do: s["label"]
          end) || current_step_name || "unknown"

        current_idx =
          Enum.find_index(visible_steps, fn s -> s["name"] == current_step_name end)

        execution_data = %{
          id: state.execution_id,
          status: to_string(state.status),
          workflow_module: format_workflow_module(state.workflow_module),
          workflow_id: workflow_meta["id"],
          current_step: current_step_name,
          current_step_label: current_label,
          visible_step: (current_idx || 0) + 1,
          total_visible_steps: length(visible_steps),
          current_step_index: state.current_step_index,
          timeline_progress: state.timeline_progress,
          results: serialize_results(state.results),
          iteration: state.iteration,
          error: serialize_error(state.error),
          events_applied: state.events_applied,
          started_at: state.started_at,
          completed_at: state.completed_at,
          duration_ms: calculate_duration_from_state(state)
        }

        json(conn, %{data: execution_data})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Execution not found"})

      {:error, reason} ->
        Logger.error("Failed to reconstruct execution state: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "Failed to reconstruct state: #{inspect(reason)}"})
    end
  end

  @doc """
  GET /api/v1/executions/:id/events

  Get all events for an execution.
  """
  def events(conn, %{"id" => execution_id}) do
    case EventStore.get_execution_events(execution_id) do
      [] ->
        conn
        |> put_status(404)
        |> json(%{error: "Execution not found"})

      events ->
        serialized_events = Enum.map(events, &serialize_event/1)

        response = %{
          data: serialized_events,
          meta: %{
            execution_id: execution_id,
            count: length(serialized_events)
          }
        }

        json(conn, response)
    end
  end

  @doc """
  POST /api/v1/executions/:id/stop

  Stop/cancel a running execution.
  """
  def stop(conn, %{"id" => execution_id}) do
    case Cerebelum.stop_execution(execution_id) do
      :ok ->
        json(conn, %{data: %{id: execution_id, status: "stopped"}})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Execution not found or not running"})
    end
  end

  @doc """
  POST /api/v1/executions/:id/resume

  Resume a paused or hibernated execution.
  """
  def resume(conn, %{"id" => execution_id}) do
    case Cerebelum.resume_execution(execution_id) do
      {:ok, _pid} ->
        json(conn, %{data: %{id: execution_id, status: "running"}})

      {:error, :already_running} ->
        conn
        |> put_status(409)
        |> json(%{error: "Execution is already running"})

      {:error, :not_resumable} ->
        conn
        |> put_status(400)
        |> json(%{
          error: "Execution is not in a resumable state (already completed/failed)"
        })

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Execution not found in database"})

      {:error, reason} ->
        Logger.error("Failed to resume execution: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "Failed to resume execution: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/v1/executions/:id/approve

  Approve a workflow that is waiting for human approval (HITL).
  The workflow resumes from the step that requested approval.

  ## Request Body (JSON)
  {
    "response": {"decision": "approved", "comment": "Looks good"}
  }
  """
  def approve(conn, %{"id" => execution_id} = params) do
    approval_response = params["response"] || %{}

    # Try Python execution first
    case PythonExecutionState.get(execution_id) do
      {:ok, py_state} ->
        approve_python_execution(conn, py_state, approval_response)

      {:error, :not_found} ->
        # Fall back to Elixir execution
        case Cerebelum.approve_execution(execution_id, approval_response) do
          :ok ->
            json(conn, %{data: %{id: execution_id, status: "approved"}})

          {:error, :not_found} ->
            conn
            |> put_status(404)
            |> json(%{error: "Execution not found or not in waiting_for_approval state"})

          {:error, reason} ->
            Logger.error("Failed to approve execution: #{inspect(reason)}")
            conn
            |> put_status(500)
            |> json(%{error: "Failed to approve execution: #{inspect(reason)}"})
        end
    end
  end

  defp approve_python_execution(conn, state, approval_response) do
    workflow_meta = state.workflow_meta
    current_step = state.current_step

    # Find next step
    steps = workflow_meta["steps"] || []
    current_idx = Enum.find_index(steps, fn s -> s["name"] == current_step end)

    if current_idx && current_idx + 1 < length(steps) do
      next_step = Enum.at(steps, current_idx + 1)
      worker_url = Cerebelum.WorkerRegistry.get_worker(state.worker_id)

      # Accumulate results from previous steps
      results = state.results || %{}
      results = Map.put(results, current_step, approval_response)

      case call_worker_execute_step(worker_url, workflow_meta["id"], next_step["name"],
             state.execution_id, state[:inputs] || %{}, results, approval_response) do
        {:ok, result} ->
          # Persist to EventStore
          {:ok, new_state} = PythonExecutionState.append_step(
            state.execution_id, next_step, result, state
          )

          # Sync with Venture API if validated
          sync_venture_if_validated(next_step, result, new_state)

          new_status = if result["status"] == "waiting_for_approval", do: "waiting_for_approval", else: "running"

          conn
          |> put_status(200)
          |> json(%{data: %{id: state.execution_id, status: new_status,
                           next_step: next_step["name"]}})

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Failed to execute next step: #{inspect(reason)}"})
      end
    else
      # Workflow completed — append final event
      completed_event = %{
        "name" => "completed",
        "label" => "Completed",
      }
      PythonExecutionState.append_step(state.execution_id, completed_event, %{
        "status" => "completed"
      }, state)

      conn
      |> put_status(200)
      |> json(%{data: %{id: state.execution_id, status: "completed"}})
    end
  end

  # Private helpers

  defp find_registered_workflow(workflow_module_str) do
    # Check Python workers first
    normalized = String.replace(workflow_module_str, "Elixir.", "")

    case Cerebelum.WorkerRegistry.find_worker_for_workflow(normalized) do
      {:ok, worker_id, worker_url} ->
        wf_meta = Cerebelum.WorkerRegistry.get_workflow(normalized)
        {:python, worker_id, worker_url, wf_meta}

      {:error, :not_found} ->
        # Fall back to Elixir workflows
        workflows = Cerebelum.Workflow.Registry.list_all()

        matching =
          Enum.find(workflows, fn wf ->
            inspect(wf.module) == workflow_module_str or
              to_string(wf.module) == "Elixir." <> workflow_module_str or
              String.ends_with?(inspect(wf.module), "." <> workflow_module_str)
          end)

        if matching do
          {:ok, matching.module}
        else
          {:error, :not_found}
        end
    end
  end

  defp dispatch_elixir_workflow(conn, module, inputs, opts) do
    execute_opts =
      if cid = opts["correlation_id"],
        do: [{:correlation_id, cid}],
        else: []

    execute_opts =
      if tags = opts["tags"], do: [{:tags, tags} | execute_opts], else: execute_opts

    case Cerebelum.execute_workflow(module, inputs, execute_opts) do
      {:ok, execution} ->
        conn
        |> put_status(201)
        |> json(%{data: %{id: execution.id, status: "running"}})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to start execution: #{inspect(reason)}"})
    end
  end

  defp dispatch_python_workflow(conn, worker_id, worker_url, workflow_meta, inputs, opts) do
    execution_id =
      :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    first_step = get_first_step(workflow_meta)

    unless first_step do
      conn
      |> put_status(400)
      |> json(%{error: "Workflow has no steps"})
    else
      # Call worker to execute first step
      token = generate_worker_token()

      case call_worker_execute_step(worker_url, workflow_meta["id"], first_step["name"],
             execution_id, inputs, %{}, %{}) do
        {:ok, result} ->
          # Store execution state
          save_python_execution(execution_id, worker_id, workflow_meta, first_step, result)

          status = if result["status"] == "waiting_for_approval", do: "waiting_for_approval", else: "running"

          conn
          |> put_status(201)
          |> json(%{data: %{id: execution_id, status: status}})

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Worker execution failed: #{inspect(reason)}"})
      end
    end
  end

  defp get_first_step(workflow_meta) do
    steps = workflow_meta["steps"] || []
    Enum.at(steps, 0)
  end

  defp generate_worker_token do
    # Generate a simple token for worker API calls
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  defp call_worker_execute_step(worker_url, workflow_id, step_name, execution_id, inputs, results \\ %{}, approve_response \\ %{}, token \\ nil) do
    body = %{
      workflow_id: workflow_id,
      step_name: step_name,
      execution_id: execution_id,
      context: %{
        inputs: inputs,
        auth_token: token || generate_worker_token(),
        org_id: inputs["organization_id"] || ""
      },
      results: results,
      approve_response: approve_response
    }

    url = String.replace_trailing(worker_url, "/", "") <> "/execute-step"

    case Req.post(url, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "HTTP #{status}: #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_python_execution(execution_id, worker_id, workflow_meta, step, result) do
    {:ok, state} = PythonExecutionState.start(execution_id, worker_id, workflow_meta, step, result)

    # Sync with Venture API if step was validated successfully
    sync_venture_if_validated(step, result, state)

    state
  end

  defp sync_venture_if_validated(step, result, state) do
    # Only sync after validate steps (not show steps)
    step_name = step["name"] || ""
    step_label = step["label"] || ""
    step_status = result["status"] || result["data"] && result["data"]["status"] || ""

    if String.contains?(step_name, "validate") or String.contains?(step_name, "confirm") do
      if step_status == "ok" do
        sync_with_venture(state, step_name, step_label, result)
      end
    end
  end

  defp sync_with_venture(state, step_name, step_label, result) do
    # Get real token from Thalamus via service account
    token = generate_venture_token()
    org_id = "5fd11ea0-852c-44e5-aee1-a761ec76eaea"

    step_data = result["data"] || result

    cond do
      # After first validate → POST /gp/funds/draft
      String.contains?(step_name, "step_1_validate") ->
        body = extract_fund_data(state)
        Logger.info("Creating fund draft via Venture API: #{inspect(body["name"])}")

        case Cerebelum.Clients.VentureApiClient.post("/gp/funds/draft", body, token, org_id: org_id) do
          {:ok, %{"data" => %{"id" => fund_id}}} ->
            Logger.info("Fund draft created: #{fund_id}")
            # Store fund_id so subsequent steps can reference it
            state
            |> Map.put(:fund_id, fund_id)
            |> Map.update!(:results, fn r -> Map.put(r, "create_fund_draft_id", fund_id) end)

          {:ok, resp} ->
            Logger.info("Fund draft response: #{inspect(resp)}")

          {:error, reason} ->
            Logger.warning("Fund draft creation failed: #{inspect(reason)}")
        end

      # After review confirm with activate → POST /gp/funds/:id/activate
      String.contains?(step_name, "step_4_confirm") and step_data["action"] == "activate" ->
        fund_id = Map.get(state, :fund_id) || state.results["create_fund_draft_id"] || state.execution_id
        Logger.info("Activating fund: #{fund_id}")
        Cerebelum.Clients.VentureApiClient.post("/gp/funds/#{fund_id}/activate", %{}, token, org_id: org_id)

      # Other validates → PUT /gp/funds/:id
      true ->
        fund_id = Map.get(state, :fund_id) || state.results["create_fund_draft_id"] || state.execution_id
        update_data = extract_step_update(step_name, step_data)
        if map_size(update_data) > 0 do
          Cerebelum.Clients.VentureApiClient.put("/gp/funds/#{fund_id}", update_data, token, org_id: org_id)
        end
    end
  rescue
    e -> Logger.warning("Venture API sync failed (non-critical): #{inspect(e)}")
  end

  defp get_step_result(state, step_name) do
    Map.get(state.results, step_name, %{})
  end

  defp extract_fund_data(state) do
    step1 = get_step_result(state, "step_1_validate")
    step2 = get_step_result(state, "step_2_validate")

    name = step1["name"] || "New Fund"
    short = step1["short_name"] || name
    fund_code = short |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "_")
    fund_term_months = step2["fund_term_months"] || 120

    %{
      "name" => name,
      "short_name" => short,
      "type" => step1["type"] || "VENTURE_CAPITAL",
      "strategy" => step1["type"] || "VENTURE_CAPITAL",
      "vintage_year" => step1["vintage_year"],
      "currency" => step1["currency"] || "USD",
      "jurisdiction" => step1["jurisdiction"],
      "total_size" => step2["total_size"],
      "target_size" => step2["total_size"],
      "hard_cap" => step2["hard_cap"],
      "investment_period_months" => step2["investment_period_months"] || 60,
      "investment_period" => step2["investment_period_months"] || 60,
      "fund_term" => fund_term_months,
      "fund_term_years" => div(fund_term_months, 12),
      "fund_life_years" => div(fund_term_months, 12),
      "management_fee_rate" => step2["management_fee_rate"] || 2.0,
      "carried_interest_rate" => step2["carried_interest_rate"] || 20.0,
      "hurdle_rate" => step2["hurdle_rate"] || 8.0,
      "fund_code" => fund_code,
    }
  end

  defp extract_step_update(step_name, step_data) do
    cond do
      String.contains?(step_name, "step_2_validate") ->
        %{
          "total_size" => step_data["total_size"],
          "target_size" => step_data["total_size"],
          "hard_cap" => step_data["hard_cap"],
          "investment_period_months" => step_data["investment_period_months"],
          "fund_term" => step_data["fund_term_months"],
          "management_fee_rate" => step_data["management_fee_rate"],
          "carried_interest_rate" => step_data["carried_interest_rate"],
          "hurdle_rate" => step_data["hurdle_rate"],
        }

      true ->
        %{}
    end
  end

  defp generate_venture_token do
    case Cerebelum.Clients.ServiceAccountTokenProvider.get_token() do
      {:ok, token} -> token
      {:error, _reason} -> nil
    end
  end

  defp serialize_execution_summary(execution_id, events) do
    %{
      id: execution_id,
      status: determine_status(events),
      workflow_module: format_workflow_module(get_workflow_module(events)),
      started_at: get_started_at(events),
      completed_at: get_completed_at(events),
      events_count: length(events),
      duration_ms: calculate_duration(events)
    }
  end

  defp get_workflow_module(events) do
    start_event = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)

    if start_event do
      get_in(start_event.event_data, ["workflow_module"]) || "unknown"
    else
      "unknown"
    end
  end

  defp format_workflow_module(module) when is_atom(module) do
    inspect(module)
  end

  defp format_workflow_module(module_str) when is_binary(module_str) do
    if String.starts_with?(module_str, "Elixir.") do
      String.slice(module_str, 7..-1//1)
    else
      module_str
    end
  end

  defp format_workflow_module(nil), do: "unknown"
  defp format_workflow_module(_), do: "unknown"

  defp serialize_event(event) do
    %{
      id: event.id,
      version: event.version,
      type: event.event_type,
      execution_id: event.execution_id,
      data: event.event_data,
      timestamp: event.inserted_at
    }
  end

  defp determine_status(events) do
    last_event = List.last(events)

    if last_event do
      case last_event.event_type do
        "ExecutionCompletedEvent" -> "completed"
        "ExecutionFailedEvent" -> "failed"
        "WorkflowPausedEvent" -> "paused"
        _ -> "running"
      end
    else
      "unknown"
    end
  end

  defp get_started_at(events) do
    start_event = Enum.find(events, fn e -> e.event_type == "ExecutionStartedEvent" end)
    if start_event, do: start_event.inserted_at, else: nil
  end

  defp get_completed_at(events) do
    completed_event =
      Enum.find(events, fn e ->
        e.event_type in ["ExecutionCompletedEvent", "ExecutionFailedEvent"]
      end)

    if completed_event, do: completed_event.inserted_at, else: nil
  end

  defp calculate_duration(events) do
    started = get_started_at(events)
    completed = get_completed_at(events)

    if started && completed do
      t1 = parse_datetime(started)
      t2 = parse_datetime(completed)

      if t1 && t2 do
        DateTime.diff(t2, t1, :millisecond)
      else
        nil
      end
    else
      nil
    end
  end

  defp calculate_duration_from_state(state) do
    if state.started_at && state.completed_at do
      t1 = parse_datetime(state.started_at)
      t2 = parse_datetime(state.completed_at)

      if t1 && t2 do
        DateTime.diff(t2, t1, :millisecond)
      else
        nil
      end
    else
      nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp get_workflow_metadata(state) do
    wf_id =
      (state.workflow_module && inspect(state.workflow_module)) ||
        to_string(state.workflow_module || "")

    # Try Python worker registry first, then Elixir
    case Cerebelum.WorkerRegistry.get_workflow(wf_id) do
      nil ->
        case Cerebelum.WorkerRegistry.get_workflow(
               String.replace(wf_id, "Elixir.", "")
             ) do
          nil -> %{"steps" => []}
          wf -> wf
        end

      wf ->
        wf
    end
  end

  defp serialize_results(results) do
    Enum.into(results, %{}, fn {step, val} ->
      {to_string(step), serialize_value(val)}
    end)
  end

  defp serialize_value({:ok, val}), do: %{"status" => "ok", "value" => serialize_term(val)}
  defp serialize_value({:error, val}),
    do: %{"status" => "error", "value" => serialize_term(val)}

  defp serialize_value({:waiting_for_approval, val}) do
    %{"status" => "waiting_for_approval", "value" => serialize_term(val)}
  end

  defp serialize_value({:sleep, val}) do
    %{"status" => "sleeping", "value" => serialize_term(val)}
  end

  defp serialize_value(val), do: serialize_term(val)

  defp serialize_term(term) when is_tuple(term) do
    term |> Tuple.to_list() |> Enum.map(&serialize_term/1)
  end

  defp serialize_term(term) when is_map(term) do
    Enum.into(term, %{}, fn {k, v} -> {serialize_key(k), serialize_term(v)} end)
  end

  defp serialize_term(term) when is_list(term) do
    Enum.map(term, &serialize_term/1)
  end

  defp serialize_term(term) when is_atom(term), do: to_string(term)
  defp serialize_term(term), do: term

  defp serialize_key(k) when is_atom(k), do: to_string(k)
  defp serialize_key(k), do: to_string(k)

  defp serialize_error(nil), do: nil
  defp serialize_error(err), do: serialize_term(err)
end
