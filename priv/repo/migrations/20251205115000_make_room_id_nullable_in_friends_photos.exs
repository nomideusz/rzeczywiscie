defmodule Rzeczywiscie.Repo.Migrations.MakeRoomIdNullableInFriendsPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      modify :room_id, :bigint, null: true
    end
  end
end

