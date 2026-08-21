defmodule Shiftline.Repo do
  use Ecto.Repo,
    otp_app: :shiftline,
    adapter: Ecto.Adapters.Postgres
end
