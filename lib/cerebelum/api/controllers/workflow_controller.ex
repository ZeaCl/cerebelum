defmodule Cerebelum.API.WorkflowController do
  @moduledoc """
  REST API Controller for workflow definitions.

  Provides read-only access to available deterministic workflows registered in the system.
  """

  use Cerebelum.API, :controller

  alias Cerebelum.Workflow.Registry

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

    # Python worker workflows (via WorkerRegistry gRPC)
    python_workers = Cerebelum.Infrastructure.WorkerRegistry.get_workers()
    python_data =
      Enum.map(python_workers, fn {_worker_id, worker} ->
        workflows = worker[:workflows] || []
        Enum.map(workflows, fn wf ->
          %{
            id: wf[:id] || wf["id"],
            label: wf[:name] || wf["name"] || wf[:id] || wf["id"],
            version: wf[:version] || wf["version"] || "0.1.0",
            steps: wf[:steps] || wf["steps"] || [],
            language: "python",
            worker_id: worker[:id] || worker["id"]
          }
        end)
      end)
      |> List.flatten()

    workflows = elixir_data ++ python_data

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

  defp find_workflow_in_workers(workers, workflow_id) do
    Enum.find_value(workers, fn {_worker_id, worker} ->
      workflows = worker[:workflows] || []
      Enum.find(workflows, fn wf ->
        (wf[:id] || wf["id"]) == workflow_id or
        (wf[:name] || wf["name"]) == workflow_id
      end)
    end)
  end
end
