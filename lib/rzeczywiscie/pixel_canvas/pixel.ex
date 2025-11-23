defmodule Rzeczywiscie.PixelCanvas.Pixel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pixels" do
    field :x, :integer
    field :y, :integer
    field :color, :string
    field :user_id, :string
    field :ip_address, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pixel, attrs) do
    pixel
    |> cast(attrs, [:x, :y, :color, :user_id, :ip_address])
    |> validate_required([:x, :y, :color, :user_id])
    |> validate_number(:x, greater_than_or_equal_to: 0, less_than: 500)
    |> validate_number(:y, greater_than_or_equal_to: 0, less_than: 500)
    |> validate_inclusion(:color, valid_colors())
    |> unique_constraint([:x, :y])
  end

  # 16-color palette (retro/brutalist aesthetic)
  defp valid_colors do
    [
      "#000000",  # Black
      "#FFFFFF",  # White
      "#FF0000",  # Red
      "#00FF00",  # Green
      "#0000FF",  # Blue
      "#FFFF00",  # Yellow
      "#FF00FF",  # Magenta
      "#00FFFF",  # Cyan
      "#FF8800",  # Orange
      "#8800FF",  # Purple
      "#00FF88",  # Mint
      "#FF0088",  # Hot Pink
      "#888888",  # Gray
      "#444444",  # Dark Gray
      "#CCCCCC",  # Light Gray
      "#88FF00"   # Lime
    ]
  end

  def colors, do: valid_colors()
end
