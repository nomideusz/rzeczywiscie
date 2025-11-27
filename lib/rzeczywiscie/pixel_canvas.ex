defmodule Rzeczywiscie.PixelCanvas do
  @moduledoc """
  Context for managing the collaborative pixel canvas.
  """

  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.PixelCanvas.Pixel
  alias Rzeczywiscie.PixelCanvas.UserPixelStats

  @canvas_width 200
  @canvas_height 200
  @cooldown_seconds 15
  @massive_pixel_cooldown_seconds 45
  @pixels_required_for_unlock 15

  @doc """
  Returns the canvas dimensions.
  """
  def canvas_size, do: {@canvas_width, @canvas_height}

  @doc """
  Returns the cooldown period in seconds.
  """
  def cooldown_seconds, do: @cooldown_seconds

  @doc """
  Returns all available colors for the palette.
  """
  def available_colors, do: Pixel.colors()

  @doc """
  Loads all pixels for the canvas.
  Returns a map of {x, y} => %{color: color, user_id: user_id, updated_at: datetime, is_massive: boolean}
  """
  def load_canvas do
    Pixel
    |> Repo.all()
    |> Enum.map(fn pixel ->
      {{pixel.x, pixel.y}, %{
        color: pixel.color,
        user_id: pixel.user_id,
        updated_at: pixel.updated_at,
        is_massive: pixel.is_massive
      }}
    end)
    |> Map.new()
  end

  @doc """
  Places a pixel on the canvas.
  Returns {:ok, pixel} or {:error, reason}
  """
  def place_pixel(x, y, color, user_id) do
    # Check cooldown
    case check_cooldown(user_id, false) do
      :ok ->
        # Check if position is already occupied (pixels are now permanent)
        case pixel_at(x, y) do
          nil ->
            attrs = %{x: x, y: y, color: color, user_id: user_id, is_massive: false}

            result = %Pixel{}
            |> Pixel.changeset(attrs)
            |> Repo.insert()

            # Update user stats and check for unlock
            case result do
              {:ok, pixel} ->
                update_user_progress(user_id)
                {:ok, pixel}
              error ->
                error
            end

          _pixel ->
            {:error, :position_occupied}
        end

      {:error, seconds_remaining} ->
        {:error, {:cooldown, seconds_remaining}}
    end
  end

  @doc """
  Checks if a user can place a pixel (cooldown check).
  Returns :ok or {:error, seconds_remaining}
  """
  def check_cooldown(user_id, is_massive \\ false) do
    last_placement =
      Pixel
      |> where([p], p.user_id == ^user_id)
      |> order_by([p], desc: p.updated_at)
      |> limit(1)
      |> Repo.one()

    cooldown = if is_massive, do: @massive_pixel_cooldown_seconds, else: @cooldown_seconds

    case last_placement do
      nil ->
        :ok

      pixel ->
        seconds_since = DateTime.diff(DateTime.utc_now(), pixel.updated_at, :second)

        if seconds_since >= cooldown do
          :ok
        else
          seconds_remaining = cooldown - seconds_since
          {:error, seconds_remaining}
        end
    end
  end

  @doc """
  Gets the next available time for a user to place a pixel.
  Returns DateTime or nil if they can place now.
  """
  def next_available_time(user_id) do
    last_placement =
      Pixel
      |> where([p], p.user_id == ^user_id)
      |> order_by([p], desc: p.updated_at)
      |> limit(1)
      |> Repo.one()

    case last_placement do
      nil -> nil
      pixel -> DateTime.add(pixel.updated_at, @cooldown_seconds, :second)
    end
  end

  @doc """
  Returns total pixel count and unique users count.
  """
  def stats do
    total_pixels = Repo.aggregate(Pixel, :count)
    unique_users = Pixel
      |> select([p], fragment("COUNT(DISTINCT ?)", p.user_id))
      |> Repo.one()

    %{
      total_pixels: total_pixels,
      unique_users: unique_users || 0
    }
  end

  @doc """
  Places a massive pixel (3x3 grid) on the canvas.
  Returns {:ok, center_pixel} or {:error, reason}
  """
  def place_massive_pixel(x, y, color, user_id) do
    # Check cooldown
    case check_cooldown(user_id, true) do
      :ok ->
        # Get user stats to check if they have massive pixels available
        stats = get_or_create_user_stats(user_id)

        if stats.massive_pixels_available > 0 do
          # Check if all 9 positions are free (3x3 grid centered on x,y)
          positions = for dx <- -1..1, dy <- -1..1, do: {x + dx, y + dy}

          occupied = Enum.any?(positions, fn {px, py} ->
            pixel_at(px, py) != nil || px < 0 || py < 0 || px >= @canvas_width || py >= @canvas_height
          end)

          if occupied do
            {:error, :insufficient_space}
          else
            # Insert center pixel first
            center_attrs = %{x: x, y: y, color: color, user_id: user_id, is_massive: true}

            case %Pixel{} |> Pixel.changeset(center_attrs) |> Repo.insert() do
              {:ok, center_pixel} ->
                # Insert surrounding 8 pixels
                surrounding_positions = positions -- [{x, y}]

                Enum.each(surrounding_positions, fn {px, py} ->
                  attrs = %{
                    x: px,
                    y: py,
                    color: color,
                    user_id: user_id,
                    is_massive: true,
                    parent_pixel_id: center_pixel.id
                  }

                  %Pixel{} |> Pixel.changeset(attrs) |> Repo.insert()
                end)

                # Decrement available massive pixels
                stats
                |> UserPixelStats.changeset(%{massive_pixels_available: stats.massive_pixels_available - 1})
                |> Repo.update()

                {:ok, center_pixel}

              error ->
                error
            end
          end
        else
          {:error, :no_massive_pixels_available}
        end

      {:error, seconds_remaining} ->
        {:error, {:cooldown, seconds_remaining}}
    end
  end

  @doc """
  Gets user pixel stats.
  Returns %UserPixelStats{} with progress info
  """
  def get_user_stats(user_id) do
    get_or_create_user_stats(user_id)
  end

  # Private helper functions

  defp pixel_at(x, y) do
    Pixel
    |> where([p], p.x == ^x and p.y == ^y)
    |> Repo.one()
  end

  defp get_or_create_user_stats(user_id) do
    case Repo.get_by(UserPixelStats, user_id: user_id) do
      nil ->
        %UserPixelStats{}
        |> UserPixelStats.changeset(%{user_id: user_id})
        |> Repo.insert!()

      stats ->
        stats
    end
  end

  defp update_user_progress(user_id) do
    stats = get_or_create_user_stats(user_id)
    new_count = stats.pixels_placed_count + 1

    # Check if user unlocked a massive pixel (every 15 pixels)
    {new_massive_count, last_unlock} =
      if rem(new_count, @pixels_required_for_unlock) == 0 do
        {stats.massive_pixels_available + 1, DateTime.utc_now()}
      else
        {stats.massive_pixels_available, stats.last_unlock_at}
      end

    stats
    |> UserPixelStats.changeset(%{
      pixels_placed_count: new_count,
      massive_pixels_available: new_massive_count,
      last_unlock_at: last_unlock
    })
    |> Repo.update()
  end
end
