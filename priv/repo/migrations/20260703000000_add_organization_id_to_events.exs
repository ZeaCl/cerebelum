defmodule Cerebelum.Repo.Migrations.AddOrganizationIdToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :organization_id, :string, null: true
    end

    create index(:events, [:organization_id])
  end
end
