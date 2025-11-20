defmodule Rzeczywiscie.Repo.Migrations.CreateKanbanCards do
  use Ecto.Migration

  def change do
    create table(:kanban_cards) do
      add :kanban_board_id, references(:kanban_boards, on_delete: :delete_all), null: false
      add :card_id, :string, null: false
      add :text, :text, null: false
      add :column, :string, null: false
      add :created_by, :string
      add :position, :integer, default: 0
      timestamps()
    end

    create index(:kanban_cards, [:kanban_board_id])
    create unique_index(:kanban_cards, [:kanban_board_id, :card_id])
  end
end
