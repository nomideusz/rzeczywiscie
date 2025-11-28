defmodule Rzeczywiscie.Repo.Migrations.AddThreeTierPixelSystem do
  use Ecto.Migration

  def up do
    # Add pixel_tier enum to pixels table
    execute """
    CREATE TYPE pixel_tier AS ENUM ('normal', 'mega', 'massive')
    """

    alter table(:pixels) do
      add :pixel_tier, :pixel_tier
    end

    # Migrate existing data: is_massive = true → mega, is_massive = false → normal
    execute """
    UPDATE pixels SET pixel_tier = 'mega' WHERE is_massive = true
    """

    execute """
    UPDATE pixels SET pixel_tier = 'normal' WHERE is_massive = false
    """

    # Make pixel_tier NOT NULL after migration
    execute """
    ALTER TABLE pixels ALTER COLUMN pixel_tier SET NOT NULL
    """

    # Add new fields to user_pixel_stats for three-tier system
    alter table(:user_pixel_stats) do
      add :mega_pixels_available, :integer, default: 0, null: false
      add :mega_pixels_used_count, :integer, default: 0, null: false
      add :mega_last_unlock_at, :utc_datetime
    end

    # Migrate existing massive_pixels_available to mega_pixels_available
    # (current "massive" becomes "mega" in the new system)
    execute """
    UPDATE user_pixel_stats SET mega_pixels_available = massive_pixels_available
    """

    execute """
    UPDATE user_pixel_stats SET mega_last_unlock_at = last_unlock_at
    """

    # Reset massive_pixels_available to 0 (will be used for new 5x5 tier)
    execute """
    UPDATE user_pixel_stats SET massive_pixels_available = 0
    """

    execute """
    UPDATE user_pixel_stats SET last_unlock_at = NULL
    """
  end

  def down do
    # Revert user_pixel_stats changes
    execute """
    UPDATE user_pixel_stats SET massive_pixels_available = mega_pixels_available
    """

    execute """
    UPDATE user_pixel_stats SET last_unlock_at = mega_last_unlock_at
    """

    alter table(:user_pixel_stats) do
      remove :mega_pixels_available
      remove :mega_pixels_used_count
      remove :mega_last_unlock_at
    end

    # Drop pixel_tier column
    alter table(:pixels) do
      remove :pixel_tier
    end

    # Drop enum type
    execute """
    DROP TYPE pixel_tier
    """
  end
end
