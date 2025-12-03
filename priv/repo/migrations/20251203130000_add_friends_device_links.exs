defmodule Rzeczywiscie.Repo.Migrations.AddFriendsDeviceLinks do
  use Ecto.Migration

  def change do
    # Table to store device-to-user mappings (for linked devices)
    create table(:friends_device_links) do
      add :device_fingerprint, :string, null: false
      add :master_user_id, :string, null: false

      timestamps()
    end

    create unique_index(:friends_device_links, [:device_fingerprint])
    create index(:friends_device_links, [:master_user_id])

    # Table to store temporary link codes
    create table(:friends_link_codes) do
      add :code, :string, null: false
      add :user_id, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:friends_link_codes, [:code])
    create index(:friends_link_codes, [:user_id])
  end
end

