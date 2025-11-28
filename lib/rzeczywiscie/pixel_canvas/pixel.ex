defmodule Rzeczywiscie.PixelCanvas.Pixel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pixels" do
    field :x, :integer
    field :y, :integer
    field :color, :string
    field :user_id, :string
    field :is_massive, :boolean, default: false
    field :pixel_tier, Ecto.Enum, values: [:normal, :mega, :massive], default: :normal
    field :is_special, :boolean, default: false
    field :special_type, :string
    field :claimer_name, :string
    field :claimer_color, :string
    belongs_to :parent_pixel, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pixel, attrs) do
    pixel
    |> cast(attrs, [:x, :y, :color, :user_id, :is_massive, :pixel_tier, :parent_pixel_id, :is_special, :special_type, :claimer_name, :claimer_color])
    |> validate_required([:x, :y, :color, :user_id, :pixel_tier])
    |> validate_number(:x, greater_than_or_equal_to: 0, less_than: 500)
    |> validate_number(:y, greater_than_or_equal_to: 0, less_than: 500)
    |> validate_inclusion(:color, valid_colors())
    |> unique_constraint([:x, :y])
  end

  # Modern 15-color palette (curated for aesthetics, no white)
  defp valid_colors do
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

  def colors, do: valid_colors()
end
