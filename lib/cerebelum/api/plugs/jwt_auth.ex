defmodule Cerebelum.API.Plugs.JWTAuth do
  @moduledoc """
  JWT Authentication plug using Thalamus JWKS (local validation).

  Validates Bearer tokens by fetching Thalamus's JWKS endpoint and
  verifying the JWT signature locally. No introspection call needed.

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
         {:ok, claims} <- validate_jwt(token) do
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

  # ── JWT validation via JWKS ────────────────────────────────

  defp validate_jwt(token) do
    with {:ok, jwks} <- fetch_jwks(),
         {:ok, signer} <- build_signer(jwks, token) do
      # Joken verify_and_validate with no extra claims checks
      case Joken.verify_and_validate(%{}, token, signer) do
        {:ok, claims} ->
          {:ok, claims}

        {:error, reason} ->
          Logger.warning("JWT verification failed: #{inspect(reason)}")
          :error
      end
    else
      {:error, reason} ->
        Logger.warning("JWKS fetch/signer error: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.error("JWT validation exception: #{Exception.message(e)}")
      :error
  end

  defp fetch_jwks do
    jwks_url =
      Application.get_env(:cerebelum, :thalamus, [])
      |> Keyword.get(:jwks_url, "http://thalamus:4000/.well-known/jwks.json")

    case :httpc.request(
           :get,
           {String.to_charlist(jwks_url), []},
           [timeout: 5000, connect_timeout: 2000],
           []
         ) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(to_string(body)) do
          {:ok, jwks} -> {:ok, jwks}
          _ -> {:error, "Invalid JWKS response"}
        end

      {:ok, {{_, status, _}, _, _}} ->
        Logger.warning("JWKS fetch returned #{status}")
        {:error, "JWKS unavailable: #{status}"}

      {:error, reason} ->
        Logger.error("JWKS fetch error: #{inspect(reason)}")
        {:error, "JWKS fetch failed"}
    end
  end

  defp build_signer(jwks, token) do
    # Extract kid from JWT header
    [header_b64 | _] = String.split(token, ".")
    {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
    header = Jason.decode!(header_json)

    keys = jwks["keys"] || []

    key =
      if header["kid"],
        do: Enum.find(keys, fn k -> k["kid"] == header["kid"] end),
        else: List.first(keys)

    if key do
      pem = jwk_to_pem(key)
      {:ok, Joken.Signer.create("RS256", %{"pem" => pem})}
    else
      {:error, "No matching JWK found"}
    end
  end

  # Convert a JWK (RSA public key) to PEM format
  defp jwk_to_pem(%{"n" => n, "e" => e}) do
    n_int = :binary.decode_unsigned(Base.url_decode64!(n, padding: false))
    e_int = :binary.decode_unsigned(Base.url_decode64!(e, padding: false))
    pem_entry = :public_key.pem_entry_encode(:RSAPublicKey, {:RSAPublicKey, n_int, e_int})
    :public_key.pem_encode([pem_entry])
  end
end
