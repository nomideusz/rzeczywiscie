defmodule Rzeczywiscie.Repo.Migrations.CreateFriendsPhotos do
  use Ecto.Migration

  def change do
    create table(:friends_photos) do
      add :user_id, :string, null: false
      add :user_color, :string, null: false
      add :image_data, :text, null: false
      add :content_type, :string, default: "image/jpeg"
      add :file_size, :integer

      timestamps()
    end

    create index(:friends_photos, [:user_id])
    create index(:friends_photos, [:inserted_at])
  end
end

