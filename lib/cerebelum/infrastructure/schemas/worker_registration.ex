defmodule Cerebelum.Infrastructure.Schemas.WorkerRegistration do
  @moduledoc """
  Ecto schema for persisted worker registrations.

  Stores worker identity, capabilities (workflows), and lifecycle state
  so that workflow definitions survive Cerebelum restarts.

  The ETS cache in WorkerRegistry is the hot path for runtime lookups;
  this table is the source of truth loaded on boot.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "worker_registrations" do
    field(:worker_id, :string)
    field(:language, :string, default: "unknown")
    field(:capabilities, {:array, :string}, default: [])
    field(:version, :string, default: "0.0.0")
    field(:metadata, :map, default: %{})

    # Lifecycle: "online" | "offline"
    field(:status, :string, default: "online")

    # Unix timestamps (seconds)
    field(:registered_at, :integer)
    field(:last_heartbeat, :integer)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a worker registration.
  """
  def changeset(registration, attrs) do
    registration
    |> cast(attrs, [
      :worker_id,
      :language,
      :capabilities,
      :version,
      :metadata,
      :status,
      :registered_at,
      :last_heartbeat
    ])
    |> validate_required([:worker_id, :registered_at, :last_heartbeat])
    |> validate_inclusion(:status, ["online", "offline"])
    |> unique_constraint(:worker_id)
  end
end
