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

    jwks_map = fetch_jwks(jwks_url)

    with {:ok, header} <- peek_header(token),
         {:ok, jwk} <- find_key(jwks_map, header["kid"]) do
      case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
        {true, %JOSE.JWT{fields: claims}, _} ->
          {:ok, claims}
        {false, _, _} ->
          Logger.warning("JWT verification failed")
          :error
        {:error, reason} ->
          Logger.warning("JWT verification error: #{inspect(reason)}")
          :error
      end
    else
      _ -> :error
    end
  rescue
    e ->
      Logger.error("JWT validation exception: #{Exception.message(e)}")
      :error
  end

  # Parse JWT header without verifying to get 'kid'
  defp peek_header(token) do
    [header_b64 | _] = String.split(token, ".")
    padded = pad_b64(header_b64)
    header = padded |> Base.decode64!() |> Jason.decode!()
    {:ok, header}
  rescue
    _ -> :error
  end

  defp pad_b64(b64) do
    case rem(byte_size(b64), 4) do
      2 -> b64 <> "=="
      3 -> b64 <> "="
      _ -> b64
    end
  end

  # Find and build a JOSE JWK from JWKS by kid
  defp find_key(jwks_map, kid) do
    keys = jwks_map["keys"] || []
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> :error
      key_map -> {:ok, JOSE.JWK.from_map(key_map)}
    end
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
