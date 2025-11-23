defmodule Rzeczywiscie.Repo.Migrations.AddIpTrackingToPixels do
  use Ecto.Migration

  def change do
    alter table(:pixels) do
      add :ip_address, :string
    end

    # Index for IP-based rate limiting queries
    create index(:pixels, [:ip_address, :updated_at])
  end
end
