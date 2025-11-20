defmodule Rzeczywiscie.Repo.Migrations.CreateDrawingBoards do
  use Ecto.Migration

  def change do
    create table(:drawing_boards) do
      add :name, :string, null: false
      add :width, :integer, default: 1200, null: false
      add :height, :integer, default: 800, null: false
      timestamps()
    end

    create unique_index(:drawing_boards, [:name])
  end
end
