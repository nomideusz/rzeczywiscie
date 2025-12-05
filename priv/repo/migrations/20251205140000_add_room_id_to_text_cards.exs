defmodule Rzeczywiscie.Repo.Migrations.AddRoomIdToTextCards do
  use Ecto.Migration

  def change do
    alter table(:friends_text_cards) do
      add :room_id, references(:friends_rooms, on_delete: :delete_all)
    end

    create index(:friends_text_cards, [:room_id])
  end
end

