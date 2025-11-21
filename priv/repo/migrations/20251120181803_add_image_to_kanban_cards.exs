defmodule Rzeczywiscie.Repo.Migrations.AddImageToKanbanCards do
  use Ecto.Migration

  def change do
    alter table(:kanban_cards) do
      add :image_data, :text
    end
  end
end
