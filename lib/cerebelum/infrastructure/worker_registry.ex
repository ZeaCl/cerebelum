defmodule Cerebelum.Infrastructure.WorkerRegistry do
  @moduledoc """
  Manages the pool of registered SDK workers with health monitoring and DB persistence.

  Responsibilities:
  - Track registered workers with metadata (language, capabilities, status)
  - Persist worker registrations to DB so workflows survive Cerebelum restarts
  - Monitor worker health via heartbeats
  - Detect and deregister dead workers (3 missed heartbeats = 30s)
  - Provide worker pool status and queries
  - Support graceful worker shutdown (draining)

  Architecture:
  - DB (worker_registrations table) = source of truth
  - ETS (:worker_registry table) = hot cache for runtime lookups
  - On boot: load all workers from DB into ETS (status: :offline by default)
  - On register: upsert to DB + insert/update in ETS
  - On unregister: mark offline in DB + remove from ETS
  - Heartbeats: update ETS immediately, flush to DB periodically
  """

  use GenServer
  require Logger

  alias Cerebelum.Infrastructure.Schemas.WorkerRegistration
  alias Cerebelum.Repo
  import Ecto.Query, only: [from: 2]

  # 30 seconds = 3 missed heartbeats @ 10s interval
  @heartbeat_timeout_ms 30_000
  # Check every 10 seconds
  @health_check_interval_ms 10_000
  # Flush heartbeat timestamps to DB every 60 seconds (6 heartbeats)
  @db_flush_interval_ms 60_000
  @table_name :worker_registry

  # Client API

  @doc """
  Starts the WorkerRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new worker with metadata.

  If the worker was previously registered (offline in DB), it is reactivated.

  ## Parameters
  - worker_id: Unique identifier for the worker
  - metadata: Map containing:
    - language: "kotlin", "typescript", "python"
    - capabilities: List of workflow modules this worker can execute
    - version: SDK version
    - custom metadata

  ## Returns
  - {:ok, worker} on success
  - {:error, reason} if worker already registered
  """
  def register_worker(worker_id, metadata) do
    GenServer.call(__MODULE__, {:register, worker_id, metadata})
  end

  @doc """
  Record heartbeat from a worker to update liveness.

  ## Parameters
  - worker_id: Worker identifier
  - status: Worker status (:idle, :busy, :draining)
  """
  def heartbeat(worker_id, status \\ :idle) do
    GenServer.cast(__MODULE__, {:heartbeat, worker_id, status})
  end

  @doc """
  Unregister a worker from the pool.

  ## Parameters
  - worker_id: Worker to remove
  - reason: Reason for unregistration (e.g., "shutdown", "error")
  """
  def unregister_worker(worker_id, reason \\ "unknown") do
    GenServer.call(__MODULE__, {:unregister, worker_id, reason})
  end

  @doc """
  Get all workers with specified status.

  ## Parameters
  - status: :idle, :busy, :draining, or :all (default)

  ## Returns
  List of workers matching the status
  """
  def get_workers(status \\ :all) do
    GenServer.call(__MODULE__, {:get_workers, status})
  end

  @doc """
  Get worker by ID.

  ## Returns
  - {:ok, worker} if found
  - {:error, :not_found} if worker doesn't exist
  """
  def get_worker(worker_id) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, worker}] -> {:ok, worker}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get idle workers that can accept tasks.
  """
  def get_idle_workers do
    GenServer.call(__MODULE__, {:get_workers, :idle})
  end

  @doc """
  Get pool statistics.

  ## Returns
  Map with:
  - total: Total registered workers
  - idle: Workers available for tasks
  - busy: Workers currently executing tasks
  - draining: Workers in graceful shutdown
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast concurrent reads
    table =
      try do
        :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
      rescue
        ArgumentError -> :ets.whereis(@table_name)
      end

    # Load persisted worker registrations from DB into ETS (skip in test)
    if Application.get_env(:cerebelum, :env) != :test do
      load_workers_from_db()
      schedule_db_flush()
      Logger.info("WorkerRegistry started with DB persistence")
    else
      Logger.info("WorkerRegistry started (test mode, DB persistence disabled)")
    end

    # Schedule periodic health checks
    schedule_health_check()

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, worker_id, metadata}, _from, state) do
    case :ets.lookup(@table_name, worker_id) do
      [] ->
        # New worker — register in ETS + DB
        worker = build_worker(worker_id, metadata)
        persist_worker(worker)
        :ets.insert(@table_name, {worker_id, worker})

        Logger.info("Worker registered: #{worker_id} (#{worker.language})")
        total = count_workers()

        :telemetry.execute(
          [:cerebelum, :workers, :connected],
          %{count: total},
          %{worker_id: worker_id, language: worker.language}
        )

        {:reply, {:ok, worker}, state}

      [{^worker_id, existing}] ->
        # Only allow re-registration if worker is offline (loaded from DB
        # after restart) or busy/draining (reconnecting after disconnect).
        # Reject duplicate register from already-active workers to avoid
        # masking bugs in SDK clients.
        if existing.status == :idle do
          Logger.warning(
            "Worker #{worker_id} already active with status :idle, rejecting duplicate register"
          )

          {:reply, {:error, :already_registered}, state}
        else
          worker = build_worker(worker_id, metadata)
          persist_worker(worker)
          :ets.insert(@table_name, {worker_id, worker})

          Logger.info(
            "Worker re-registered (was #{existing.status}): #{worker_id} (#{worker.language})"
          )

          {:reply, {:ok, worker}, state}
        end
    end
  end

  @impl true
  def handle_call({:unregister, worker_id, reason}, _from, state) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, _worker}] ->
        # Mark as offline in DB
        mark_worker_offline(worker_id)

        # Remove from ETS cache
        :ets.delete(@table_name, worker_id)

        Logger.info("Worker unregistered: #{worker_id}, reason: #{reason}")

        # Telemetry: worker disconnected
        total = count_workers()

        :telemetry.execute(
          [:cerebelum, :workers, :disconnected],
          %{count: total},
          %{worker_id: worker_id, reason: reason}
        )

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_workers, status}, _from, state) do
    workers =
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_id, worker} -> worker end)
      |> filter_by_status(status)

    {:reply, workers, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    workers = :ets.tab2list(@table_name) |> Enum.map(fn {_id, w} -> w end)

    stats = %{
      total: length(workers),
      idle: count_by_status(workers, :idle),
      busy: count_by_status(workers, :busy),
      draining: count_by_status(workers, :draining)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:heartbeat, worker_id, status}, state) do
    case :ets.lookup(@table_name, worker_id) do
      [{^worker_id, worker}] ->
        updated_worker = %{worker | last_heartbeat: now(), status: status}
        :ets.insert(@table_name, {worker_id, updated_worker})
        Logger.debug("Heartbeat received from worker: #{worker_id}")

      [] ->
        Logger.warning("Heartbeat from unregistered worker: #{worker_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    check_worker_health()
    schedule_health_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:db_flush, state) do
    flush_heartbeats_to_db()
    schedule_db_flush()
    {:noreply, state}
  end

  # ── DB Persistence ──────────────────────────────────

  defp load_workers_from_db do
    try do
      registrations = Repo.all(WorkerRegistration)
      count = length(registrations)

      Enum.each(registrations, fn reg ->
        worker = db_registration_to_worker(reg)
        :ets.insert(@table_name, {reg.worker_id, worker})
      end)

      Logger.info("Loaded #{count} worker registration(s) from DB into ETS cache")
    rescue
      error ->
        Logger.warning("Failed to load worker registrations from DB: #{inspect(error)}")
    end
  end

  defp persist_worker(worker) do
    if Application.get_env(:cerebelum, :env) == :test do
      Logger.debug("Worker persistence skipped in test mode: #{worker.worker_id}")
    else
      _persist_worker_to_db(worker)
    end
  end

  defp _persist_worker_to_db(worker) do
    now_time = worker.last_heartbeat

    try do
      # Use on_conflict upsert to avoid TOCTOU race between get_by and insert.
      # If two workers register simultaneously with the same ID (unlikely but
      # possible on reconnect storms), the DB unique constraint ensures exactly
      # one row with the latest metadata.
      changeset =
        WorkerRegistration.changeset(%WorkerRegistration{}, %{
          worker_id: worker.worker_id,
          language: worker.language,
          capabilities: worker.capabilities,
          version: worker.version,
          metadata: worker.metadata,
          status: "online",
          registered_at: now_time,
          last_heartbeat: now_time
        })

      Repo.insert!(
        changeset,
        on_conflict: [
          set: [
            language: worker.language,
            capabilities: worker.capabilities,
            version: worker.version,
            metadata: worker.metadata,
            status: "online",
            registered_at: now_time,
            last_heartbeat: now_time
          ]
        ],
        conflict_target: :worker_id
      )

      Logger.debug("Worker persisted to DB: #{worker.worker_id}")
    rescue
      error ->
        Logger.warning("Failed to persist worker #{worker.worker_id} to DB: #{inspect(error)}")
    end
  end

  defp mark_worker_offline(worker_id) do
    if Application.get_env(:cerebelum, :env) == :test do
      Logger.debug("Worker offline marking skipped in test mode: #{worker_id}")
    else
      _mark_worker_offline_in_db(worker_id)
    end
  end

  defp _mark_worker_offline_in_db(worker_id) do
    try do
      case Repo.get_by(WorkerRegistration, worker_id: worker_id) do
        nil ->
          Logger.debug("Worker not found in DB for offline marking: #{worker_id}")

        reg ->
          reg
          |> WorkerRegistration.changeset(%{
            status: "offline",
            last_heartbeat: now()
          })
          |> Repo.update!()

          Logger.debug("Worker marked offline in DB: #{worker_id}")
      end
    rescue
      error ->
        Logger.warning("Failed to mark worker #{worker_id} offline in DB: #{inspect(error)}")
    end
  end

  defp flush_heartbeats_to_db do
    if Application.get_env(:cerebelum, :env) == :test do
      :ok
    else
      _flush_heartbeats_to_db()
    end
  end

  defp _flush_heartbeats_to_db do
    workers = :ets.tab2list(@table_name)

    if workers != [] do
      try do
        worker_ids = Enum.map(workers, fn {id, _worker} -> id end)
        now_ts = now()

        # Bulk UPDATE instead of N individual queries
        {count, _} =
          Repo.update_all(
            from(w in WorkerRegistration, where: w.worker_id in ^worker_ids),
            set: [last_heartbeat: now_ts, status: "online"]
          )

        Logger.debug("Flushed #{count} heartbeat(s) to DB")
      rescue
        error ->
          Logger.warning("Failed to flush heartbeats to DB: #{inspect(error)}")
      end
    end
  end

  defp db_registration_to_worker(reg) do
    %{
      worker_id: reg.worker_id,
      language: reg.language,
      capabilities: reg.capabilities,
      version: reg.version,
      metadata: reg.metadata,
      # Workers loaded from DB are offline until they explicitly re-register.
      # This prevents race conditions where a worker appears :idle after
      # a Cerebelum restart when the real worker process is long dead.
      status: :offline,
      registered_at: reg.registered_at,
      last_heartbeat: reg.last_heartbeat
    }
  end

  # ── Health Check ────────────────────────────────────

  defp check_worker_health do
    current_time = now()
    timeout_threshold = current_time - div(@heartbeat_timeout_ms, 1000)

    dead_workers =
      @table_name
      |> :ets.tab2list()
      |> Enum.filter(fn {_id, worker} ->
        worker.last_heartbeat < timeout_threshold
      end)

    Enum.each(dead_workers, fn {worker_id, worker} ->
      Logger.warning(
        "Worker #{worker_id} is dead (last heartbeat: #{current_time - worker.last_heartbeat}s ago), deregistering"
      )

      # Mark offline in DB
      mark_worker_offline(worker_id)

      # Remove from ETS cache
      :ets.delete(@table_name, worker_id)

      # TODO: Trigger task reassignment in P8.3
      # reassign_tasks(worker_id)
    end)

    if length(dead_workers) > 0 do
      Logger.info("Deregistered #{length(dead_workers)} dead worker(s)")
    end
  end

  # ── Helpers ─────────────────────────────────────────

  defp build_worker(worker_id, metadata) do
    %{
      worker_id: worker_id,
      language: Map.get(metadata, :language, "unknown"),
      capabilities: Map.get(metadata, :capabilities, []),
      version: Map.get(metadata, :version, "0.0.0"),
      metadata: Map.get(metadata, :metadata, %{}),
      status: :idle,
      registered_at: now(),
      last_heartbeat: now()
    }
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval_ms)
  end

  defp schedule_db_flush do
    Process.send_after(self(), :db_flush, @db_flush_interval_ms)
  end

  defp filter_by_status(workers, :all), do: workers

  defp filter_by_status(workers, status) do
    Enum.filter(workers, fn worker -> worker.status == status end)
  end

  defp count_by_status(workers, status) do
    Enum.count(workers, fn worker -> worker.status == status end)
  end

  defp now do
    System.system_time(:second)
  end

  defp count_workers do
    :ets.info(@table_name, :size)
  end
end
