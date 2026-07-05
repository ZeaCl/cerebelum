defmodule Cerebelum.API.DevCertController do
  @moduledoc """
  Generates client certificates for worker mTLS.

  Uses the engine's CA to sign per-user client certificates.
  Idempotent: same user → same cert (based on user_id hash).
  """

  use Cerebelum.API, :controller
  require Logger

  @certs_dir "/app/certs"
  @tmp_dir "/tmp/cerebelum-certs"

  @doc """
  POST /api/v1/dev-certs

  Generates a client certificate signed by the engine's CA.
  Requires JWT authentication.

  Returns: { "ca_crt": "...", "client_crt": "...", "client_key": "..." }
  """
  def create(conn, _params) do
    user_id = conn.assigns[:user_id] || "anonymous"

    unless File.exists?(@certs_dir) do
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "certs_not_available"})
    else
      case generate_client_cert(user_id) do
        {:ok, ca_crt, client_crt, client_key} ->
          json(conn, %{ca_crt: ca_crt, client_crt: client_crt, client_key: client_key})

        {:error, reason} ->
          Logger.error("Dev cert failed for #{user_id}: #{inspect(reason)}")
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "cert_generation_failed"})
      end
    end
  end

  defp generate_client_cert(user_id) do
    user_hash =
      :crypto.hash(:sha256, user_id)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    File.mkdir_p!(@tmp_dir)

    client_key_path = Path.join(@tmp_dir, "client-#{user_hash}.key")
    client_crt_path = Path.join(@tmp_dir, "client-#{user_hash}.crt")
    ca_crt_path = Path.join(@certs_dir, "ca.crt")
    ca_key_path = Path.join(@certs_dir, "ca.key")

    # Idempotent: reuse existing VALID cert (not empty)
    if File.exists?(client_crt_path) and File.exists?(client_key_path)
       and File.stat!(client_crt_path).size > 0 do
      Logger.info("Dev cert reused for #{user_id}")
      {:ok, File.read!(ca_crt_path), File.read!(client_crt_path), File.read!(client_key_path)}
    else
      do_generate(user_id, user_hash, client_key_path, client_crt_path, ca_crt_path, ca_key_path)
    end
  end

  defp do_generate(user_id, user_hash, key_path, crt_path, ca_crt, ca_key) do
    with {_, 0} <- System.cmd("openssl", ["genrsa", "-out", key_path, "4096"], stderr_to_stdout: true),
         {_, 0} <- System.cmd("openssl", ["req", "-new", "-key", key_path, "-out", "#{crt_path}.csr", "-subj", "/CN=dev-#{user_hash}"], stderr_to_stdout: true),
         serial = :rand.uniform(999_999),
         {_, 0} <- System.cmd("openssl", ["x509", "-req", "-days", "365", "-in", "#{crt_path}.csr", "-CA", ca_crt, "-CAkey", ca_key, "-set_serial", "#{serial}", "-out", crt_path], stderr_to_stdout: true) do
      File.rm("#{crt_path}.csr")
      Logger.info("Dev cert generated for #{user_id}")
      {:ok, File.read!(ca_crt), File.read!(crt_path), File.read!(key_path)}
    else
      {err, code} ->
        # Clean up on failure
        File.rm_rf(key_path)
        File.rm_rf(crt_path)
        File.rm_rf("#{crt_path}.csr")
        {:error, "openssl failed (code=#{code}): #{err}"}
    end
  end
end
