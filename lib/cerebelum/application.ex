defmodule Cerebelum.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Base children that always start
    base_children = [
      # HTTP API (Phoenix Endpoint)
      Cerebelum.API.Endpoint,

      # Database repo
      Cerebelum.Repo,

      # Workflow registry for managing workflow definitions
      Cerebelum.Workflow.Registry,

      # Event store for event sourcing
      Cerebelum.EventStore,

      # Execution registry for tracking active workflows
      Cerebelum.Execution.Registry,

      # Execution supervisor for managing workflow executions
      Cerebelum.Execution.Supervisor,

      # Worker registry for SDK worker pool management
      Cerebelum.Infrastructure.WorkerRegistry,

      # Task router for distributing work to SDK workers
      Cerebelum.Infrastructure.TaskRouter,

      # Blueprint registry for storing workflow definitions
      Cerebelum.Infrastructure.BlueprintRegistry,

      # Execution state manager for tracking workflow execution state
      Cerebelum.Infrastructure.ExecutionStateManager,

      # Dead Letter Queue for managing failed tasks
      Cerebelum.Infrastructure.DLQ,

      # Resurrector for automatically resuming paused workflows on boot
      Cerebelum.Execution.Resurrector,

      # Workflow scheduler for periodic resurrection of hibernated workflows
      Cerebelum.Infrastructure.WorkflowScheduler
    ]

    # Conditionally add gRPC server if enabled
    children =
      if grpc_enabled?() do
        base_children ++
          [
            {GRPC.Server.Supervisor,
             servers: [Cerebelum.Infrastructure.WorkerServiceServer],
             port: grpc_port(),
             start_server: true,
             adapter_opts: grpc_tls_opts()}
          ]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Cerebelum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ── gRPC Configuration ──────────────────────────────

  defp grpc_enabled? do
    Application.get_env(:cerebelum, :enable_grpc_server, false)
  end

  defp grpc_port do
    Application.get_env(:cerebelum, :grpc_port, 50051)
  end

  defp grpc_tls_opts do
    certs_dir = Application.get_env(:cerebelum, :grpc_certs_dir, "priv/certs")

    cacert = Path.join(certs_dir, "ca.crt")
    cert = Path.join(certs_dir, "server.crt")
    key = Path.join(certs_dir, "server.key")

    require Logger
    Logger.info("gRPC TLS: certs_dir=#{certs_dir} cacert_exists=#{File.exists?(cacert)} cert_exists=#{File.exists?(cert)} key_exists=#{File.exists?(key)}")

    if File.exists?(cacert) and File.exists?(cert) and File.exists?(key) do
      cred = GRPC.Credential.new(
        ssl: [
          certfile: cert,
          keyfile: key,
          cacertfile: cacert,
          verify: :verify_peer,
          fail_if_no_peer_cert: true,
          versions: [:"tlsv1.2", :"tlsv1.3"]
        ]
      )
      Logger.info("gRPC TLS: mTLS enabled")
      [cred: cred]
    else
      Logger.warning("gRPC TLS: certs not found, starting without TLS")
      []
    end
  end

  # http_enabled? and http_port are used when cerebelum starts its own
  # supervision tree. When used as a library, the host app handles this.
end
