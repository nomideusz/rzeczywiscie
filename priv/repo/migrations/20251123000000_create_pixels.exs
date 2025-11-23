defmodule Rzeczywiscie.Repo.Migrations.CreatePixels do
  use Ecto.Migration

  def change do
    create table(:pixels) do
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :color, :string, null: false
      add :user_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: only one pixel per coordinate
    create unique_index(:pixels, [:x, :y])

    # Index for querying by user (for cooldown checks)
    create index(:pixels, [:user_id, :updated_at])
  end
end
