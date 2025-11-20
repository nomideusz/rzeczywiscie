defmodule Rzeczywiscie.Repo.Migrations.AddImageToWorldMapPins do
  use Ecto.Migration

  def change do
    alter table(:world_map_pins) do
      add :image_data, :text
    end
  end
end
