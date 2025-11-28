defmodule Rzeczywiscie.Repo.Migrations.AddGlobalMilestonesAndSpecialPixels do
  use Ecto.Migration

  def change do
    # Add special pixel support to pixels table
    alter table(:pixels) do
      add :is_special, :boolean, default: false, null: false
      add :special_type, :string  # "unicorn", "star", "diamond", etc.
      add :claimer_name, :string  # Name of the person who claimed it
      add :claimer_color, :string # Color associated with the claimer
    end

    # Track available special pixels for users
    alter table(:user_pixel_stats) do
      add :special_pixels_available, :map, default: %{}, null: false
    end

    # Create global milestone tracking table
    create table(:global_milestones) do
      add :milestone_type, :string, null: false  # "pixels_1000", "pixels_5000", etc.
      add :threshold, :integer, null: false      # Pixel count needed
      add :reward_type, :string, null: false     # "unicorn", "star", etc.
      add :unlocked_at, :utc_datetime
      add :total_pixels_when_unlocked, :integer
      
      timestamps(type: :utc_datetime)
    end

    create unique_index(:global_milestones, [:milestone_type])
  end
end
