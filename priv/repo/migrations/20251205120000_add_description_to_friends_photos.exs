defmodule Rzeczywiscie.Repo.Migrations.AddDescriptionToFriendsPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add :description, :string, size: 200
    end
  end
end

