defmodule Rzeczywiscie.PixelCanvasTest do
  use Rzeczywiscie.DataCase

  alias Rzeczywiscie.PixelCanvas

  @color hd(PixelCanvas.available_colors())

  test "place, cooldown, and overwrite" do
    assert {:ok, pixel} = PixelCanvas.place_pixel(5, 5, @color, "user-a")
    assert pixel.color == @color

    # same user is on cooldown
    assert {:error, {:cooldown, s}} = PixelCanvas.place_pixel(6, 6, @color, "user-a")
    assert s > 0

    # another user can overwrite the same position
    other_color = Enum.at(PixelCanvas.available_colors(), 1)
    assert {:ok, overwritten} = PixelCanvas.place_pixel(5, 5, other_color, "user-b")
    assert overwritten.color == other_color

    assert PixelCanvas.load_canvas() == [[5, 5, other_color]]
    assert PixelCanvas.stats() == %{total_pixels: 1, contributors: 1}
  end

  test "rejects out of bounds and bad colors" do
    assert {:error, :out_of_bounds} = PixelCanvas.place_pixel(-1, 0, @color, "u")
    assert {:error, :out_of_bounds} = PixelCanvas.place_pixel(0, 300, @color, "u")
    assert {:error, %Ecto.Changeset{}} = PixelCanvas.place_pixel(0, 0, "#ffffff", "u")
  end
end
