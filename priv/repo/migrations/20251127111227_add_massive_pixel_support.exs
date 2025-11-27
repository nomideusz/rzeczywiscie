defmodule Rzeczywiscie.Repo.Migrations.AddMassivePixelSupport do
  use Ecto.Migration

  def change do
    # Add massive pixel fields to pixels table
    alter table(:pixels) do
      add :is_massive, :boolean, default: false, null: false
      add :parent_pixel_id, references(:pixels, on_delete: :delete_all)
    end

    create index(:pixels, [:parent_pixel_id])

    # Create user_pixel_stats table to track unlock progress
    create table(:user_pixel_stats) do
      add :user_id, :string, null: false
      add :pixels_placed_count, :integer, default: 0, null: false
      add :massive_pixels_available, :integer, default: 0, null: false
      add :last_unlock_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_pixel_stats, [:user_id])
  end
end
