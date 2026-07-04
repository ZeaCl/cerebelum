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
    port = Application.get_env(:cerebelum, :grpc_port, 50051)
    # Try connecting to the gRPC port locally to verify it's listening
    case :gen_tcp.connect('localhost', port, [], 100) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        "running"
      {:error, _} ->
        "stopped"
    end
  end
end
