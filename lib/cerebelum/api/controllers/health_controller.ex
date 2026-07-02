defmodule Cerebelum.API.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and load balancers.
  """

  use Cerebelum.API, :controller

  def health(conn, _params) do
    health_status = %{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "0.1.0",
      services: %{
        database: check_database(),
        grpc: check_grpc()
      }
    }

    json(conn, health_status)
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Cerebelum.Repo, "SELECT 1", []) do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  end

  defp check_grpc do
    # Check if gRPC server is running
    case Process.whereis(Cerebelum.Infrastructure.WorkerServiceServer) do
      nil -> "stopped"
      _pid -> "running"
    end
  end
end
