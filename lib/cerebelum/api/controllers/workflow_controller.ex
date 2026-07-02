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
          steps: []
        }
      end)

    # Python worker workflows (new — via gRPC Register)
    python_workflows = Cerebelum.WorkerRegistry.list_all()

    workflows = elixir_data ++ python_workflows

    json(conn, %{data: workflows})
  end

  defp format_module_name(module) do
    name = inspect(module)
    # Elixir.FundCreateWorkflow -> "Fund Create Workflow"
    name
    |> String.replace("Elixir.", "")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
  end

  @doc """
  GET /api/v1/workflows/:id

  Returns full metadata for a specific workflow, including steps, fields, and worker info.
  """
  def show(conn, %{"id" => workflow_id}) do
    case Cerebelum.WorkerRegistry.get_workflow(workflow_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      workflow ->
        # Enrich with worker URL for code fetching
        case Cerebelum.WorkerRegistry.find_worker_for_workflow(workflow_id) do
          {:ok, _worker_id, worker_url} ->
            json(conn, %{data: Map.put(workflow, "worker_url", worker_url)})

          {:error, :not_found} ->
            json(conn, %{data: workflow})
        end
    end
  end

  @doc """
  GET /api/v1/workflows/:id/code

  Returns the Python source code for a workflow.
  Reads from the worker's filesystem path.
  """
  def code(conn, %{"id" => workflow_id}) do
    # Try to find the source file from the worker registry
    source_path = find_workflow_source(workflow_id)

    case source_path do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Source code not available"})

      path ->
        case File.read(path) do
          {:ok, content} ->
            json(conn, %{
              data: %{
                id: workflow_id,
                language: "python",
                source: content,
                path: path
              }
            })

          {:error, _reason} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Cannot read source file"})
        end
    end
  end

  defp find_workflow_source(workflow_id) do
    # Try common locations for workflow source files
    base_paths = [
      "/workspace/cerebelum-core/examples/python-sdk",
      "/app",
      System.get_env("WORKFLOW_SOURCES", "/workspace/cerebelum-core/examples/python-sdk")
    ]

    Enum.find_value(base_paths, fn base ->
      name = if String.ends_with?(workflow_id, ".py"), do: workflow_id, else: "#{workflow_id}.py"
      path = Path.join(base, name)
      if File.exists?(path), do: path
    end)
  end
end
