defmodule Rzeczywiscie.Repo.Migrations.CreateStrokes do
  use Ecto.Migration

  def change do
    create table(:strokes) do
      add :drawing_board_id, references(:drawing_boards, on_delete: :delete_all), null: false
      add :stroke_data, :map, null: false
      timestamps()
    end

    create index(:strokes, [:drawing_board_id])
  end
end
