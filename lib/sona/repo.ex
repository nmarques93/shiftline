defmodule Sona.Repo do
  use Ecto.Repo,
    otp_app: :sona,
    adapter: Ecto.Adapters.Postgres
end
