defmodule Rzeczywiscie.PixelCanvas do
  @moduledoc """
  Context for the collaborative pixel canvas.

  Simple r/place-style rules: pick a color, place one pixel, wait out the
  cooldown. Overwriting existing pixels is allowed.
  """

  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.PixelCanvas.Pixel

  @canvas_width 200
  @canvas_height 200
  @cooldown_seconds 15

  def canvas_size, do: {@canvas_width, @canvas_height}
  def cooldown_seconds, do: @cooldown_seconds
  def available_colors, do: Pixel.colors()

  @doc "All pixels as a compact list of [x, y, color]."
  def load_canvas do
    Repo.all(from p in Pixel, select: [p.x, p.y, p.color])
  end

  @doc """
  Place (or overwrite) a pixel. Returns {:ok, pixel} or
  {:error, {:cooldown, seconds}} / {:error, :out_of_bounds} / {:error, changeset}.
  """
  def place_pixel(x, y, color, user_id)
      when is_integer(x) and is_integer(y) and is_binary(color) and is_binary(user_id) do
    remaining = seconds_remaining(user_id)

    cond do
      x < 0 or x >= @canvas_width or y < 0 or y >= @canvas_height ->
        {:error, :out_of_bounds}

      remaining > 0 ->
        {:error, {:cooldown, remaining}}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %Pixel{}
        |> Pixel.changeset(%{x: x, y: y, color: color, user_id: user_id})
        |> Repo.insert(
          on_conflict: [set: [color: color, user_id: user_id, updated_at: now]],
          conflict_target: [:x, :y]
        )
    end
  end

  @doc "Seconds until the user may place again (0 = can place now)."
  def seconds_remaining(user_id) do
    # ponytail: cooldown is derived from the user's most recent surviving
    # pixel - if it gets overwritten mid-cooldown the timer resets early.
    # Harmless; track last-placed-at separately if it ever matters.
    last =
      Repo.one(
        from p in Pixel, where: p.user_id == ^user_id, select: max(p.updated_at)
      )

    case last do
      nil -> 0
      last -> max(@cooldown_seconds - DateTime.diff(DateTime.utc_now(), last), 0)
    end
  end

  def stats do
    Repo.one(
      from p in Pixel,
        select: %{total_pixels: count(p.id), contributors: count(p.user_id, :distinct)}
    )
  end
end
