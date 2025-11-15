defmodule Rzeczywiscie.Repo do
  use Ecto.Repo,
    otp_app: :rzeczywiscie,
    adapter: Ecto.Adapters.Postgres
end
