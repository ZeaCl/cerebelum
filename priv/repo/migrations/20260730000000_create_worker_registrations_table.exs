defmodule Cerebelum.Repo.Migrations.CreateWorkerRegistrationsTable do
  use Ecto.Migration

  @moduledoc """
  Creates the worker_registrations table for persisting worker registrations
  across Cerebelum restarts.

  Previously, worker registrations (including workflow capabilities) were stored
  only in ETS memory, causing all workflows to disappear when Cerebelum restarted
  or when a worker disconnected without clean re-registration.

  This table serves as the source of truth, while ETS remains as a hot cache
  for fast lookups during normal operation.

  ## Purpose

  - Persist worker identity, capabilities (workflows), and metadata
  - Survive Cerebelum restarts — workers reloaded from DB on boot
  - Track worker lifecycle: online → offline → reconnected
  - Enable workflow discovery even when workers are temporarily down

  ## Performance

  - ETS cache for all runtime lookups (no DB queries during execution)
  - DB writes on register/unregister only (heartbeats stay in ETS)
  - Small table: one row per worker (typically < 50 rows)
  """

  def up do
    create table(:worker_registrations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :worker_id, :text, null: false

      # Worker metadata
      add :language, :text, null: false, default: "unknown"
      add :capabilities, {:array, :text}, default: [], null: false
      add :version, :text, default: "0.0.0"
      add :metadata, :map, default: %{}

      # Worker lifecycle state
      add :status, :text, null: false, default: "online"
      # online | offline

      # Tracking
      add :registered_at, :bigint, null: false
      add :last_heartbeat, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique index on worker_id — one registration per worker
    create unique_index(:worker_registrations, [:worker_id])

    # Index for filtering by status (online/offline)
    create index(:worker_registrations, [:status])

    # Index for finding recently active workers
    create index(:worker_registrations, [:last_heartbeat])
  end

  def down do
    drop table(:worker_registrations)
  end
end
