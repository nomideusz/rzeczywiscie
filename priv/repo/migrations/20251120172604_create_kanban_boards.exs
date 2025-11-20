defmodule Rzeczywiscie.Repo.Migrations.CreateKanbanBoards do
  use Ecto.Migration

  def change do
    create table(:kanban_boards) do
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:kanban_boards, [:name])
  end
end
