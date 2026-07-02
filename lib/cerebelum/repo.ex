defmodule Cerebelum.Repo do
  use Ecto.Repo,
    otp_app: :cerebelum,
    adapter: Ecto.Adapters.Postgres
end
