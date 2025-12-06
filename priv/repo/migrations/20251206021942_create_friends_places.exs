defmodule Rzeczywiscie.Repo.Migrations.CreateFriendsPlaces do
  use Ecto.Migration

  def change do
    create table(:friends_places) do
      add :room_id, references(:friends_rooms, on_delete: :delete_all)
      add :user_id, :string, null: false
      add :user_name, :string
      add :user_color, :string
      add :name, :string, null: false
      add :description, :text
      add :lat, :float, null: false
      add :lng, :float, null: false
      add :emoji, :string, default: "📍"

      timestamps()
    end

    create index(:friends_places, [:room_id])
    create index(:friends_places, [:user_id])
  end
end

