defmodule Rzeczywiscie.PixelCanvas do
  @moduledoc """
  Context for managing the collaborative pixel canvas.
  """

  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.PixelCanvas.Pixel

  @canvas_width 500
  @canvas_height 500
  @cooldown_seconds 60
  @ip_rate_limit_count 10  # Max pixels per IP per hour
  @ip_rate_limit_window 3600  # 1 hour in seconds

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
  Returns a map of {x, y} => %{color: color, user_id: user_id, updated_at: datetime}
  """
  def load_canvas do
    Pixel
    |> Repo.all()
    |> Enum.map(fn pixel ->
      {{pixel.x, pixel.y}, %{
        color: pixel.color,
        user_id: pixel.user_id,
        updated_at: pixel.updated_at
      }}
    end)
    |> Map.new()
  end

  @doc """
  Places a pixel on the canvas.
  Returns {:ok, pixel} or {:error, reason}
  """
  def place_pixel(x, y, color, user_id, ip_address \\ nil) do
    # Check per-user cooldown (60 seconds)
    with :ok <- check_cooldown(user_id),
         # Check IP-based rate limit (10 pixels per hour)
         :ok <- check_ip_rate_limit(ip_address) do
      attrs = %{x: x, y: y, color: color, user_id: user_id, ip_address: ip_address}

      # Upsert: insert or update if pixel already exists at this location
      %Pixel{}
      |> Pixel.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:color, :user_id, :ip_address, :updated_at]},
        conflict_target: [:x, :y]
      )
    end
  end

  @doc """
  Checks if a user can place a pixel (cooldown check).
  Returns :ok or {:error, seconds_remaining}
  """
  def check_cooldown(user_id) do
    last_placement =
      Pixel
      |> where([p], p.user_id == ^user_id)
      |> order_by([p], desc: p.updated_at)
      |> limit(1)
      |> Repo.one()

    case last_placement do
      nil ->
        :ok

      pixel ->
        seconds_since = DateTime.diff(DateTime.utc_now(), pixel.updated_at, :second)

        if seconds_since >= @cooldown_seconds do
          :ok
        else
          seconds_remaining = @cooldown_seconds - seconds_since
          {:error, seconds_remaining}
        end
    end
  end

  @doc """
  Checks IP-based rate limit (prevents abuse from multiple devices).
  Returns :ok or {:error, {:ip_rate_limit, count, window}}
  """
  def check_ip_rate_limit(nil), do: :ok  # Skip check if no IP provided

  def check_ip_rate_limit(ip_address) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@ip_rate_limit_window, :second)

    pixel_count =
      Pixel
      |> where([p], p.ip_address == ^ip_address)
      |> where([p], p.updated_at > ^cutoff_time)
      |> select([p], count(p.id))
      |> Repo.one()

    if pixel_count >= @ip_rate_limit_count do
      {:error, {:ip_rate_limit, @ip_rate_limit_count, div(@ip_rate_limit_window, 60)}}
    else
      :ok
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
end
