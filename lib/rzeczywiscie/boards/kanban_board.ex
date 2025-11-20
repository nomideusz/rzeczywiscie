defmodule Rzeczywiscie.Boards.KanbanBoard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kanban_boards" do
    field :name, :string
    has_many :cards, Rzeczywiscie.Boards.KanbanCard
    timestamps()
  end

  @doc false
  def changeset(kanban_board, attrs) do
    kanban_board
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
