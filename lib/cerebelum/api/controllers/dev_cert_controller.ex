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

  Returns:
    {
      "ca_crt": "...",
      "client_crt": "...",
      "client_key": "..."
    }
  """
  def create(conn, _params) do
    user_id = conn.assigns[:user_id] || "anonymous"

    # Check certs directory exists
    unless File.exists?(@certs_dir) do
      conn
      |> put_status(:service_unavailable)
      |> json(%{error: "certs_not_available", message: "CA not configured on this engine"})
      |> halt()
    else
      # Generate certs for this user (idempotent)
      case generate_client_cert(user_id) do
        {:ok, ca_crt, client_crt, client_key} ->
          json(conn, %{
            ca_crt: ca_crt,
            client_crt: client_crt,
            client_key: client_key
          })

        {:error, reason} ->
          Logger.error("Failed to generate dev cert for #{user_id}: #{inspect(reason)}")
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "cert_generation_failed", message: inspect(reason)})
      end
    end
  end

  # Generate a client certificate signed by the engine's CA.
  # Generates in /tmp to avoid read-only volume issues.
  defp generate_client_cert(user_id) do
    user_hash =
      :crypto.hash(:sha256, user_id)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    # Ensure tmp dir exists
    File.mkdir_p!(@tmp_dir)

    client_key_path = Path.join(@tmp_dir, "client-#{user_hash}.key")
    client_crt_path = Path.join(@tmp_dir, "client-#{user_hash}.crt")
    ca_crt_path = Path.join(@certs_dir, "ca.crt")
    ca_key_path = Path.join(@certs_dir, "ca.key")

    # If cert already exists for this user, return it (idempotent)
    if File.exists?(client_crt_path) and File.exists?(client_key_path) do
      Logger.info("Dev cert already exists for user #{user_id}, reusing")
      {:ok, File.read!(ca_crt_path), File.read!(client_crt_path), File.read!(client_key_path)}
    else
      # Generate new client key
      case System.cmd("openssl", ["genrsa", "-out", client_key_path, "4096"], stderr_to_stdout: true) do
        {_, 0} ->
          # Generate CSR
          subject = "/CN=dev-#{user_hash}"
          case System.cmd("openssl", [
            "req", "-new", "-key", client_key_path, "-out", "#{client_crt_path}.csr",
            "-subj", subject
          ], stderr_to_stdout: true) do
            {_, 0} ->
              # Sign with CA
              case System.cmd("openssl", [
                "x509", "-req", "-days", "365", "-in", "#{client_crt_path}.csr",
                "-CA", ca_crt_path, "-CAkey", ca_key_path, "-CAcreateserial",
                "-out", client_crt_path
              ], stderr_to_stdout: true) do
                {_, 0} ->
                  # Clean up CSR
                  File.rm("#{client_crt_path}.csr")
                  Logger.info("Dev cert generated for user #{user_id}")
                  {:ok, File.read!(ca_crt_path), File.read!(client_crt_path), File.read!(client_key_path)}

                {err, _} ->
                  {:error, "Failed to sign cert: #{err}"}
              end

            {err, _} ->
              {:error, "Failed to create CSR: #{err}"}
          end

        {err, _} ->
          {:error, "Failed to generate key: #{err}"}
      end
    end
  end
end
