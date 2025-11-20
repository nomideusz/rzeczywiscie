defmodule Rzeczywiscie.Drawings.Stroke do
  use Ecto.Schema
  import Ecto.Changeset

  schema "strokes" do
    field :stroke_data, :map
    belongs_to :drawing_board, Rzeczywiscie.Drawings.DrawingBoard
    timestamps()
  end

  @doc false
  def changeset(stroke, attrs) do
    stroke
    |> cast(attrs, [:stroke_data, :drawing_board_id])
    |> validate_required([:stroke_data, :drawing_board_id])
  end
end
