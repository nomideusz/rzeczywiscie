defmodule Rzeczywiscie.Repo.Migrations.AddFriendsMessages do
  use Ecto.Migration

  def change do
    create table(:friends_messages) do
      add :user_id, :string, null: false
      add :user_color, :string, null: false
      add :content, :text, null: false
      add :room_id, references(:friends_rooms, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:friends_messages, [:room_id])
    create index(:friends_messages, [:inserted_at])
  end
end

