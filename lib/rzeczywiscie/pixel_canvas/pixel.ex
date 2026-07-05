defmodule Rzeczywiscie.PixelCanvas.Pixel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pixels" do
    field :x, :integer
    field :y, :integer
    field :color, :string
    field :user_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pixel, attrs) do
    pixel
    |> cast(attrs, [:x, :y, :color, :user_id])
    |> validate_required([:x, :y, :color, :user_id])
    |> validate_inclusion(:color, colors())
    |> unique_constraint([:x, :y])
  end

  # Modern 15-color palette (curated for aesthetics, no white)
  def colors do
    [
      "#1a1a1a",  # Rich Black
      "#ef4444",  # Soft Red
      "#10b981",  # Emerald
      "#3b82f6",  # Blue
      "#f59e0b",  # Amber
      "#8b5cf6",  # Purple
      "#ec4899",  # Pink
      "#14b8a6",  # Teal
      "#f97316",  # Orange
      "#6366f1",  # Indigo
      "#84cc16",  # Lime
      "#06b6d4",  # Cyan
      "#a855f7",  # Violet
      "#64748b",  # Slate
      "#fbbf24"   # Yellow
    ]
  end
end
