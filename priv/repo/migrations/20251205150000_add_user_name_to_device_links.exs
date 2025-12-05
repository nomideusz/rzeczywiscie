defmodule Rzeczywiscie.Repo.Migrations.AddUserNameToDeviceLinks do
  use Ecto.Migration

  def change do
    alter table(:friends_device_links) do
      add :user_name, :string
    end

    # Create index for faster lookups by device fingerprint
    create_if_not_exists index(:friends_device_links, [:device_fingerprint])
  end
end

