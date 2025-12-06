defmodule Rzeczywiscie.Repo.Migrations.AddBrowserLinkingToDeviceLinksV2 do
  use Ecto.Migration

  def change do
    # Add new columns if they don't exist
    alter table(:friends_device_links) do
      add_if_not_exists :browser_id, :string
      add_if_not_exists :link_code, :string
      add_if_not_exists :link_code_expires_at, :utc_datetime
    end

    # Drop old unique constraint on device_fingerprint (if exists)
    drop_if_exists unique_index(:friends_device_links, [:device_fingerprint])

    # Create new unique constraint on browser_id
    create_if_not_exists unique_index(:friends_device_links, [:browser_id])

    # Index for looking up by link code
    create_if_not_exists index(:friends_device_links, [:link_code])

    # Index for looking up by master_user_id (to find all linked browsers)
    create_if_not_exists index(:friends_device_links, [:master_user_id])

    # Migrate existing data: set browser_id = device_fingerprint for existing records
    execute """
    UPDATE friends_device_links
    SET browser_id = device_fingerprint
    WHERE browser_id IS NULL
    """, ""
  end
end

