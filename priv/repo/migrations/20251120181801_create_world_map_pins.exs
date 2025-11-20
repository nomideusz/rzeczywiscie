defmodule Rzeczywiscie.Repo.Migrations.CreateWorldMapPins do
  use Ecto.Migration

  def change do
    create table(:world_map_pins) do
      add :user_name, :string, null: false
      add :user_color, :string, null: false
      add :lat, :float, null: false
      add :lng, :float, null: false
      add :message, :text
      add :emoji, :string
      add :ip_address, :string
      add :country, :string
      add :city, :string
      timestamps()
    end

    create index(:world_map_pins, [:lat, :lng])
    create index(:world_map_pins, [:inserted_at])
  end
end
