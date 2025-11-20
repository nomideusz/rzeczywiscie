defmodule Rzeczywiscie.Drawings.DrawingBoard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "drawing_boards" do
    field :name, :string
    field :width, :integer, default: 1200
    field :height, :integer, default: 800
    has_many :strokes, Rzeczywiscie.Drawings.Stroke
    timestamps()
  end

  @doc false
  def changeset(drawing_board, attrs) do
    drawing_board
    |> cast(attrs, [:name, :width, :height])
    |> validate_required([:name, :width, :height])
    |> unique_constraint(:name)
  end
end
