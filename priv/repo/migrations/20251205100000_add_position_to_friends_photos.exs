defmodule Rzeczywiscie.Repo.Migrations.AddPositionToFriendsPhotos do
  use Ecto.Migration

  def change do
    alter table(:friends_photos) do
      add :position, :integer
    end

    # Create index for efficient ordering queries
    create index(:friends_photos, [:user_id, :position])
  end
end

