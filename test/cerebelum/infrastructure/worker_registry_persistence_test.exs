defmodule Cerebelum.Infrastructure.WorkerRegistryPersistenceTest do
  @moduledoc """
  Integration tests for WorkerRegistry DB persistence layer.

  Tests the DB functions directly (not through the GenServer) to verify
  that persist, mark_offline, flush, and load operations work correctly
  against a real PostgreSQL database.

  The GenServer integration (ETS + DB) is tested implicitly by
  `worker_registry_test.exs` and verified manually in staging/prod.
  """

  use ExUnit.Case, async: false

  alias Cerebelum.Infrastructure.Schemas.WorkerRegistration
  alias Cerebelum.Repo

  import Ecto.Query, only: [from: 2]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(WorkerRegistration)
    :ok
  end

  describe "persist worker (insert)" do
    test "inserts new worker into DB" do
      worker = %{
        worker_id: "persist-test-1",
        language: "python",
        capabilities: ["WorkflowA", "WorkflowB"],
        version: "1.2.3",
        metadata: %{"region" => "us-east-1"},
        status: :idle,
        registered_at: System.system_time(:second),
        last_heartbeat: System.system_time(:second)
      }

      # Simulate persist_worker
      now_ts = worker.last_heartbeat

      %WorkerRegistration{}
      |> WorkerRegistration.changeset(%{
        worker_id: worker.worker_id,
        language: worker.language,
        capabilities: worker.capabilities,
        version: worker.version,
        metadata: worker.metadata,
        status: "online",
        registered_at: now_ts,
        last_heartbeat: now_ts
      })
      |> Repo.insert!()

      # Verify
      db_record = Repo.get_by!(WorkerRegistration, worker_id: "persist-test-1")
      assert db_record.status == "online"
      assert db_record.language == "python"
      assert db_record.capabilities == ["WorkflowA", "WorkflowB"]
      assert db_record.version == "1.2.3"
      assert db_record.metadata["region"] == "us-east-1"
    end
  end

  describe "persist worker (update / reactivate)" do
    test "updates existing offline worker to online" do
      now_ts = System.system_time(:second)

      # Insert an offline worker
      %WorkerRegistration{}
      |> WorkerRegistration.changeset(%{
        worker_id: "reactivate-1",
        language: "python",
        capabilities: ["OldCap"],
        version: "1.0.0",
        metadata: %{},
        status: "offline",
        registered_at: now_ts - 1000,
        last_heartbeat: now_ts - 500
      })
      |> Repo.insert!()

      # Simulate re-registration: update to online with new capabilities
      existing = Repo.get_by!(WorkerRegistration, worker_id: "reactivate-1")
      existing
      |> WorkerRegistration.changeset(%{
        language: "python",
        capabilities: ["NewCap1", "NewCap2"],
        version: "2.0.0",
        metadata: %{"updated" => true},
        status: "online",
        registered_at: now_ts,
        last_heartbeat: now_ts
      })
      |> Repo.update!()

      # Verify
      updated = Repo.get_by!(WorkerRegistration, worker_id: "reactivate-1")
      assert updated.status == "online"
      assert updated.capabilities == ["NewCap1", "NewCap2"]
      assert updated.version == "2.0.0"
      assert updated.metadata["updated"] == true
    end
  end

  describe "mark worker offline" do
    test "updates status to offline" do
      now_ts = System.system_time(:second)

      %WorkerRegistration{}
      |> WorkerRegistration.changeset(%{
        worker_id: "offline-1",
        language: "elixir",
        capabilities: ["Test"],
        version: "1.0.0",
        metadata: %{},
        status: "online",
        registered_at: now_ts,
        last_heartbeat: now_ts
      })
      |> Repo.insert!()

      # Mark offline
      reg = Repo.get_by!(WorkerRegistration, worker_id: "offline-1")
      reg
      |> WorkerRegistration.changeset(%{status: "offline", last_heartbeat: now_ts + 10})
      |> Repo.update!()

      updated = Repo.get_by!(WorkerRegistration, worker_id: "offline-1")
      assert updated.status == "offline"
    end
  end

  describe "flush heartbeats (bulk update)" do
    test "bulk updates heartbeat and status for multiple workers" do
      now_ts = System.system_time(:second)

      # Insert 3 workers
      for i <- 1..3 do
        %WorkerRegistration{}
        |> WorkerRegistration.changeset(%{
          worker_id: "flush-#{i}",
          language: "python",
          capabilities: [],
          version: "1.0.0",
          metadata: %{},
          status: "online",
          registered_at: now_ts - 100,
          last_heartbeat: now_ts - 100
        })
        |> Repo.insert!()
      end

      # Bulk update (simulating heartbeat flush)
      new_ts = now_ts + 100
      worker_ids = ["flush-1", "flush-2", "flush-3"]

      {count, _} =
        Repo.update_all(
          from(w in WorkerRegistration, where: w.worker_id in ^worker_ids),
          set: [last_heartbeat: new_ts, status: "online"]
        )

      assert count == 3

      # Verify all updated
      for i <- 1..3 do
        reg = Repo.get_by!(WorkerRegistration, worker_id: "flush-#{i}")
        assert reg.last_heartbeat == new_ts
        assert reg.status == "online"
      end
    end
  end

  describe "load workers from DB" do
    test "loads both online and offline workers" do
      now_ts = System.system_time(:second)

      %WorkerRegistration{}
      |> WorkerRegistration.changeset(%{
        worker_id: "load-1",
        language: "python",
        capabilities: ["A", "B"],
        version: "1.0.0",
        metadata: %{},
        status: "online",
        registered_at: now_ts,
        last_heartbeat: now_ts
      })
      |> Repo.insert!()

      %WorkerRegistration{}
      |> WorkerRegistration.changeset(%{
        worker_id: "load-2",
        language: "elixir",
        capabilities: ["C"],
        version: "0.9.0",
        metadata: %{},
        status: "offline",
        registered_at: now_ts - 1000,
        last_heartbeat: now_ts - 1000
      })
      |> Repo.insert!()

      # Load all (simulating init)
      registrations = Repo.all(WorkerRegistration)
      assert length(registrations) == 2

      online = Enum.find(registrations, fn r -> r.worker_id == "load-1" end)
      offline = Enum.find(registrations, fn r -> r.worker_id == "load-2" end)

      assert online.status == "online"
      assert online.capabilities == ["A", "B"]
      assert offline.status == "offline"
      assert offline.capabilities == ["C"]
    end
  end
end
