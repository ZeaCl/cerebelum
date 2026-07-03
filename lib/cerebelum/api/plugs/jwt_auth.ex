defmodule Cerebelum.API.Plugs.JWTAuth do
  @moduledoc """
  JWT Authentication plug using Thalamus JWKS.

  Validates Bearer tokens against Thalamus JWKS endpoint and
  extracts user_id and organization_id from claims.

  ## Configuration

      config :cerebelum, :thalamus,
        jwks_url: "http://thalamus:4000/.well-known/jwks.json"
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- validate_token(token) do
      conn
      |> assign(:user_id, claims["sub"])
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

  # Validate JWT signature against Thalamus JWKS
  defp validate_token(token) do
    jwks_url = Application.get_env(:cerebelum, :thalamus, [])
               |> Keyword.get(:jwks_url, "http://thalamus:4000/.well-known/jwks.json")

    jwks = fetch_jwks(jwks_url)

    case JOSE.JWT.verify_strict(jwks, ["RS256", "HS256"], token) do
      {true, %JOSE.JWT{fields: claims}, _} ->
        {:ok, claims}
      {false, _, _} ->
        Logger.warning("JWT verification failed")
        :error
      {:error, reason} ->
        Logger.warning("JWT verification error: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.error("JWT validation exception: #{Exception.message(e)}")
      :error
  end

  defp fetch_jwks(url) do
    # Use simple HTTP get via :httpc (no extra deps)
    case :httpc.request(:get, {String.to_charlist(url), []}, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(body) do
          {:ok, jwks_map} -> jwks_map
          _ -> %{}
        end
      _ -> %{}
    end
  end
end
