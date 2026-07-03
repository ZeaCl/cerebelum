defmodule Cerebelum.API.Plugs.JWTAuth do
  @moduledoc """
  JWT Authentication plug using Thalamus Token Introspection.

  Validates Bearer tokens by calling Thalamus `/oauth/introspect` endpoint
  and extracts user_id and organization_id from the response.

  ## Configuration

      config :cerebelum, :thalamus,
        introspection_url: "http://thalamus:4000/oauth/introspect"
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- introspect_token(token) do
      conn
      |> assign(:user_id, claims["user_id"] || claims["sub"])
      |> assign(:organization_id, claims["organization_id"] || claims["org_id"])
      |> assign(:claims, claims)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  # Validate token via Thalamus introspection endpoint
  defp introspect_token(token) do
    introspection_url =
      Application.get_env(:cerebelum, :thalamus, [])
      |> Keyword.get(:introspection_url, "http://thalamus:4000/oauth/introspect")

    body = Jason.encode!(%{token: token})

    case :httpc.request(
           :post,
           {String.to_charlist(introspection_url),
            [{~c"content-type", ~c"application/json"}],
            ~c"application/json",
            String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"active" => true} = claims} ->
            {:ok, claims}

          {:ok, %{"active" => false}} ->
            Logger.warning("Token introspection returned inactive")
            :error

          _ ->
            :error
        end

      {:ok, {{_, status, _}, _, _}} ->
        Logger.warning("Token introspection failed with status #{status}")
        :error

      {:error, reason} ->
        Logger.error("Token introspection HTTP error: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.error("JWT validation exception: #{Exception.message(e)}")
      :error
  end
end
