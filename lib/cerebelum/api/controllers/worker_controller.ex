defmodule Cerebelum.API.WorkerController do
  @moduledoc """
  Controller for Python worker registration and health.

  Workers call POST /api/v1/workers/register on startup
  to register their workflows and URL.
  """

  use Cerebelum.API, :controller
  require Logger

  @doc """
  POST /api/v1/workers/register

  Register a Python worker with its workflows and callback URL.
  The Core will call this URL to execute workflow steps.
  """
  def register(conn, %{"worker_id" => worker_id, "url" => url} = params) do
    workflows = params["workflows"] || []

    # Store worker info
    case Cerebelum.WorkerRegistry.register_worker(worker_id, url, workflows) do
      :ok ->
        Logger.info("Worker registered: #{worker_id} at #{url} with #{length(workflows)} workflows")
        json(conn, %{ok: true})

      {:error, reason} ->
        Logger.error("Worker registration failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  GET /api/v1/workers
  List all registered workers.
  """
  def index(conn, _params) do
    workers = Cerebelum.WorkerRegistry.list_workers()
    json(conn, %{data: workers})
  end
end
