defmodule Rzeczywiscie.PixelCanvas.UserPixelStats do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_pixel_stats" do
    field :user_id, :string
    field :pixels_placed_count, :integer, default: 0
    field :mega_pixels_available, :integer, default: 0
    field :mega_pixels_used_count, :integer, default: 0
    field :mega_last_unlock_at, :utc_datetime
    field :massive_pixels_available, :integer, default: 0
    field :last_unlock_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stats, attrs) do
    stats
    |> cast(attrs, [:user_id, :pixels_placed_count, :mega_pixels_available, :mega_pixels_used_count, :mega_last_unlock_at, :massive_pixels_available, :last_unlock_at])
    |> validate_required([:user_id])
    |> validate_number(:pixels_placed_count, greater_than_or_equal_to: 0)
    |> validate_number(:mega_pixels_available, greater_than_or_equal_to: 0)
    |> validate_number(:mega_pixels_used_count, greater_than_or_equal_to: 0)
    |> validate_number(:massive_pixels_available, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_id)
  end
end
