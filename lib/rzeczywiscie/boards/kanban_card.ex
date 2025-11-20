defmodule Rzeczywiscie.Boards.KanbanCard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "kanban_cards" do
    field :card_id, :string
    field :text, :string
    field :column, :string
    field :created_by, :string
    field :position, :integer, default: 0
    belongs_to :kanban_board, Rzeczywiscie.Boards.KanbanBoard
    timestamps()
  end

  @doc false
  def changeset(kanban_card, attrs) do
    kanban_card
    |> cast(attrs, [:card_id, :text, :column, :created_by, :position, :kanban_board_id])
    |> validate_required([:card_id, :text, :column, :kanban_board_id])
  end
end
