defmodule Rzeczywiscie.Repo.Migrations.AddFriendsRooms do
  use Ecto.Migration

  def change do
    create table(:friends_rooms) do
      add :code, :string, null: false
      add :name, :string
      add :created_by, :string
      add :emoji, :string, default: "📸"

      timestamps()
    end

    create unique_index(:friends_rooms, [:code])

    # Add room_id to photos
    alter table(:friends_photos) do
      add :room_id, references(:friends_rooms, on_delete: :delete_all)
    end

    create index(:friends_photos, [:room_id])

    # Create default "lobby" room
    execute """
    INSERT INTO friends_rooms (code, name, emoji, inserted_at, updated_at)
    VALUES ('lobby', 'Lobby', '🏠', NOW(), NOW())
    """, ""
  end
end

