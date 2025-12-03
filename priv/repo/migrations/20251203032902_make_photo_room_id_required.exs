defmodule Rzeczywiscie.Repo.Migrations.MakePhotoRoomIdRequired do
  use Ecto.Migration

  def up do
    # First, assign any orphaned photos to lobby
    execute """
    UPDATE friends_photos
    SET room_id = (SELECT id FROM friends_rooms WHERE code = 'lobby' LIMIT 1)
    WHERE room_id IS NULL
    """

    # Then make the column NOT NULL
    alter table(:friends_photos) do
      modify :room_id, references(:friends_rooms, on_delete: :delete_all), null: false, from: references(:friends_rooms, on_delete: :delete_all)
    end
  end

  def down do
    alter table(:friends_photos) do
      modify :room_id, references(:friends_rooms, on_delete: :delete_all), null: true, from: references(:friends_rooms, on_delete: :delete_all)
    end
  end
end

