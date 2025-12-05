defmodule Rzeczywiscie.Repo.Migrations.AddThumbnailToFriendsPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add :thumbnail_data, :text
    end
  end
end

