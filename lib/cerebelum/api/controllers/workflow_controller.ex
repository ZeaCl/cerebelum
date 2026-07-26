defmodule Cerebelum.API.WorkflowController do
  @moduledoc """
  REST API Controller for workflow definitions.

  Provides read-only access to available deterministic workflows registered in the system,
  and the ability to deploy new blueprint definitions.
  """

  use Cerebelum.API, :controller

  alias Cerebelum.Workflow.Registry
  alias Cerebelum.Infrastructure.BlueprintRegistry
  require Logger

  @doc """
  GET /api/v1/workflows

  List all registered workflows, their metadata, timeline steps, diverges, and branch structures.
  """
  def index(conn, _params) do
    # Elixir-native workflows (existing)
    elixir_workflows = Registry.list_all()

    elixir_data =
      Enum.map(elixir_workflows, fn wf ->
        %{
          id: inspect(wf.module),
          label: format_module_name(wf.module),
          version: wf.version,
          steps: [],
          language: "elixir"
        }
      end)

    # Python worker capabilities (via WorkerRegistry gRPC)
    # Workers return a list of maps with :worker_id, :capabilities, :language, etc.
    python_workers = Cerebelum.Infrastructure.WorkerRegistry.get_workers()

    python_data =
      Enum.flat_map(python_workers, fn worker ->
        worker_id = worker[:worker_id] || worker["worker_id"]
        capabilities = worker[:capabilities] || []
        language = worker[:language] || worker["language"] || "python"

        # Each capability is a step the worker can execute
        Enum.map(capabilities, fn cap ->
          %{
            id: "#{worker_id}/#{cap}",
            label: cap,
            version: worker[:version] || worker["version"] || "0.1.0",
            steps: [cap],
            language: language,
            worker_id: worker_id
          }
        end)
      end)

    # Deployed blueprints (via BlueprintRegistry)
    blueprints = BlueprintRegistry.list_blueprints()

    blueprint_data =
      Enum.map(blueprints, fn mod ->
        case BlueprintRegistry.get_blueprint(mod) do
          {:ok, bp} ->
            %{
              id: bp[:id] || mod,
              label: bp[:name] || mod,
              version: bp[:version] || "0.1.0",
              steps: bp[:steps] || [],
              language: bp[:language] || "python"
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    workflows = elixir_data ++ python_data ++ blueprint_data

    json(conn, %{data: workflows})
  end

  defp format_module_name(module) do
    name = inspect(module)

    name
    |> String.replace("Elixir.", "")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
  end

  @doc """
  GET /api/v1/workflows/:id

  Returns full metadata for a specific workflow, including steps, fields, and worker info.
  """
  def show(conn, %{"id" => workflow_id}) do
    # Search in workers registry
    python_workers = Cerebelum.Infrastructure.WorkerRegistry.get_workers()
    workflow = find_workflow_in_workers(python_workers, workflow_id)

    case workflow do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      wf ->
        json(conn, %{data: wf})
    end
  end

  @doc """
  GET /api/v1/workflows/:id/code

  Returns the Python source code for a workflow.
  """
  def code(conn, %{"id" => workflow_id}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Source code not available in production"})
  end

  @doc """
  POST /api/v1/workflows/deploy

  Deploy a workflow blueprint. Accepts Python source code and stores it
  as a registered workflow that can be executed.

  Body:
    {
      "name": "my_workflow",
      "module": "Elixir.MyWorkflow",
      "code": "from cerebelum import step, workflow\n...",
      "language": "python"
    }
  """
  def deploy(conn, params) do
    name = params["name"]
    module = params["module"]
    code = params["code"]
    language = params["language"] || "python"

    cond do
      is_nil(name) or name == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing 'name' field"})

      is_nil(code) or code == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing 'code' field"})

      true ->
        # Extract steps from the Python code
        steps = extract_steps(code)

        blueprint = %{
          id: name,
          name: name,
          module: module,
          code: code,
          language: language,
          steps: steps,
          deployed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        :ok = BlueprintRegistry.store_blueprint(name, blueprint)

        # Telemetry: blueprint deployed
        :telemetry.execute(
          [:cerebelum, :blueprints, :deployed],
          %{count: 1},
          %{name: name, steps: length(steps), language: language}
        )

        Logger.info("Blueprint deployed: #{name} with #{length(steps)} steps")

        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            id: name,
            name: name,
            language: language,
            steps: steps
          }
        })
    end
  end

  # Extract @step-decorated function names from Python source code
  defp extract_steps(code) do
    code
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {candidate, acc} ->
      cond do
        # Detect @step decorator followed by function definition
        String.trim(line) == "@step" ->
          {true, acc}

        candidate && String.match?(line, ~r/^\s*(async\s+)?def\s+(\w+)/) ->
          [_match, name] = Regex.run(~r/def\s+(\w+)/, line)
          {false, [name | acc]}

        true ->
          {candidate, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  @doc """
  GET /api/v1/workflows/:id/steps

  List all steps of a workflow with metadata.
  """
  def steps(conn, %{"id" => workflow_id}) do
    case BlueprintRegistry.get_blueprint(workflow_id) do
      {:ok, blueprint} ->
        step_names = blueprint[:steps] || []
        code = blueprint[:code] || ""

        steps_data =
          step_names
          |> Enum.with_index()
          |> Enum.map(fn {name, index} ->
            %{
              name: name,
              position: index,
              has_code: String.contains?(code, "def #{name}(")
            }
          end)

        json(conn, %{
          data: %{
            workflow: workflow_id,
            total: length(steps_data),
            steps: steps_data
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})
    end
  end

  @doc """
  GET /api/v1/workflows/:id/steps/:name

  Returns the source code of a single step.
  """
  def show_step(conn, %{"id" => workflow_id, "name" => step_name}) do
    case BlueprintRegistry.get_step(workflow_id, step_name) do
      {:ok, code} ->
        json(conn, %{
          data: %{
            name: step_name,
            workflow: workflow_id,
            code: code
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      {:error, :step_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Step '#{step_name}' not found in workflow '#{workflow_id}'"})
    end
  end

  @doc """
  PUT /api/v1/workflows/:id/steps/:name

  Update the source code of a single step.

  Body: { "code": "@step\ndef step_name(...):\n  ..." }
  """
  def update_step(conn, %{"id" => workflow_id, "name" => step_name} = params) do
    code = params["code"]

    cond do
      is_nil(code) or code == "" ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing 'code' field"})

      true ->
        case BlueprintRegistry.update_step(workflow_id, step_name, code) do
          :ok ->
            Logger.info("Step '#{step_name}' updated in workflow '#{workflow_id}'")

            # Telemetry: step updated
            :telemetry.execute(
              [:cerebelum, :blueprints, :steps, :updated],
              %{count: 1},
              %{workflow: workflow_id, step: step_name}
            )

            conn
            |> json(%{
              data: %{
                name: step_name,
                workflow: workflow_id,
                updated: true
              }
            })

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Workflow not found"})

          {:error, :invalid_step_code} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Invalid step code: must contain a function definition (def function_name)"
            })
        end
    end
  end

  @doc """
  DELETE /api/v1/workflows/:id/steps/:name

  Delete a single step from a workflow.
  """
  def delete_step(conn, %{"id" => workflow_id, "name" => step_name}) do
    case BlueprintRegistry.delete_step(workflow_id, step_name) do
      :ok ->
        Logger.info("Step '#{step_name}' deleted from workflow '#{workflow_id}'")

        # Telemetry: step deleted
        :telemetry.execute(
          [:cerebelum, :blueprints, :steps, :deleted],
          %{count: 1},
          %{workflow: workflow_id, step: step_name}
        )

        conn
        |> json(%{
          data: %{
            name: step_name,
            workflow: workflow_id,
            deleted: true
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      {:error, :step_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Step '#{step_name}' not found in workflow '#{workflow_id}'"})
    end
  end

  defp find_workflow_in_workers(workers, workflow_id) do
    Enum.find_value(workers, fn worker ->
      capabilities = worker[:capabilities] || []
      worker_id = worker[:worker_id] || worker["worker_id"]

      # Check if any capability matches the requested workflow_id
      case Enum.find(capabilities, fn cap -> cap == workflow_id end) do
        nil ->
          false

        cap ->
          %{
            id: cap,
            name: cap,
            label: cap,
            version: worker[:version] || worker["version"] || "0.1.0",
            steps: [cap],
            language: worker[:language] || worker["language"] || "python",
            worker_id: worker_id
          }
      end
    end)
  end
end
