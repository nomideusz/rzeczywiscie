defmodule Rzeczywiscie.PixelCanvas do
  @moduledoc """
  Context for managing the collaborative pixel canvas.
  """

  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.PixelCanvas.Pixel
  alias Rzeczywiscie.PixelCanvas.UserPixelStats
  alias Rzeczywiscie.PixelCanvas.GlobalMilestone

  @canvas_width 200
  @canvas_height 200
  @cooldown_seconds 15
  @mega_pixel_cooldown_seconds 45
  @massive_pixel_cooldown_seconds 120
  @pixels_required_for_mega_unlock 15
  @mega_pixels_required_for_massive_unlock 5
  @pixels_required_for_massive_bonus 100

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
  Returns a map of {x, y} => %{color: color, user_id: user_id, updated_at: datetime, pixel_tier: atom, ...}
  """
  def load_canvas do
    Pixel
    |> Repo.all()
    |> Enum.map(fn pixel ->
      {{pixel.x, pixel.y}, %{
        color: pixel.color,
        user_id: pixel.user_id,
        updated_at: pixel.updated_at,
        pixel_tier: pixel.pixel_tier,
        is_special: pixel.is_special,
        special_type: pixel.special_type,
        claimer_name: pixel.claimer_name,
        claimer_color: pixel.claimer_color
      }}
    end)
    |> Map.new()
  end

  # Unicorn shape offsets (facing right) - must match frontend UNICORN_SHAPE
  @unicorn_shape_right [
    {6, -9}, {7, -9}, {7, -8},  # horn
    {5, -8}, {6, -8},  # head top
    {2, -7}, {3, -8}, {3, -7}, {4, -7}, {5, -7}, {6, -7},  # mane + head
    {1, -6}, {2, -6}, {3, -6}, {4, -6}, {5, -6}, {6, -6}, {7, -6},  # mane + head + eye
    {1, -5}, {2, -5}, {3, -5}, {4, -5}, {5, -5},  # mane + neck
    {0, -4}, {1, -4}, {2, -4}, {3, -4}, {4, -4}, {5, -4},  # mane + body
    {0, -3}, {1, -3}, {2, -3}, {3, -3}, {4, -3},  # mane + body
    {-1, -2}, {0, -2}, {1, -2}, {2, -2}, {3, -2}, {5, -2}, {6, -2},  # tail + body + legs
    {-1, -1}, {0, -1}, {2, -1}, {3, -1}, {5, -1}, {6, -1},  # tail + legs
    {0, 0}, {2, 0}, {3, 0}, {5, 0}, {6, 0}  # tail + feet
  ]

  # Unicorn shape facing left (mirror of right)
  @unicorn_shape_left Enum.map(@unicorn_shape_right, fn {dx, dy} -> {-dx, dy} end)

  @doc """
  Returns the unicorn shape offsets for a given direction.
  """
  def unicorn_shape(:left), do: @unicorn_shape_left
  def unicorn_shape(:right), do: @unicorn_shape_right
  def unicorn_shape(_), do: @unicorn_shape_right

  @doc """
  Places a special pixel on the canvas with the user's name and color.
  Uses a transaction to prevent race conditions.
  Returns {:ok, pixel} or {:error, reason}
  """
  def place_special_pixel(x, y, color, user_id, special_type, claimer_name, claimer_color, direction \\ :right) do
    # Check cooldown first (outside transaction)
    case check_cooldown(user_id) do
      :ok ->
        # Use transaction with row-level locking
        Repo.transaction(fn ->
          # Lock and get user stats
          stats = get_or_create_user_stats(user_id)
          available_count = Map.get(stats.special_pixels_available || %{}, special_type, 0)

          if available_count > 0 do
            # Get all positions the unicorn would occupy
            shape_offsets = unicorn_shape(direction)
            positions = Enum.map(shape_offsets, fn {dx, dy} -> {x + dx, y + dy} end)

            # Check if ANY position is already occupied
            occupied = Pixel
            |> where([p], fragment("(?, ?) IN (SELECT * FROM unnest(?::int[], ?::int[]))",
              p.x, p.y,
              ^Enum.map(positions, &elem(&1, 0)),
              ^Enum.map(positions, &elem(&1, 1))))
            |> limit(1)
            |> Repo.one()

            if occupied do
              Repo.rollback(:position_occupied)
            else
              # Store anchor pixel with direction metadata
              attrs = %{
                x: x,
                y: y,
                color: color,
                user_id: user_id,
                pixel_tier: :normal,
                is_massive: false,
                is_special: true,
                special_type: "#{special_type}:#{direction}",
                claimer_name: claimer_name,
                claimer_color: claimer_color
              }

              case %Pixel{} |> Pixel.changeset(attrs) |> Repo.insert() do
                {:ok, pixel} ->
                  # Decrement available special pixel
                  updated_specials = Map.update(
                    stats.special_pixels_available,
                    special_type,
                    0,
                    &max(0, &1 - 1)
                  )

                  stats
                  |> UserPixelStats.changeset(%{special_pixels_available: updated_specials})
                  |> Repo.update!()

                  pixel

                {:error, _changeset} ->
                  Repo.rollback(:insert_failed)
              end
            end
          else
            Repo.rollback(:no_special_pixel_available)
          end
        end)

      {:error, seconds_remaining} ->
        {:error, {:cooldown, seconds_remaining}}
    end
  end

  @doc """
  Places a pixel on the canvas.
  Returns {:ok, pixel} or {:error, reason}
  """
  def place_pixel(x, y, color, user_id) do
    # Check cooldown
    case check_cooldown(user_id) do
      :ok ->
        # Check if position is already occupied (pixels are now permanent)
        case pixel_at(x, y) do
          nil ->
            attrs = %{x: x, y: y, color: color, user_id: user_id, pixel_tier: :normal, is_massive: false}

            result = %Pixel{}
            |> Pixel.changeset(attrs)
            |> Repo.insert()

            # Update user stats and check for unlock
            case result do
              {:ok, pixel} ->
                update_user_progress(user_id, :normal)
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
        # Determine cooldown based on the tier of the LAST pixel placed
        cooldown = case pixel.pixel_tier do
          :normal -> @cooldown_seconds
          :mega -> @mega_pixel_cooldown_seconds
          :massive -> @massive_pixel_cooldown_seconds
        end

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
  Places a mega pixel (3x3 grid) on the canvas.
  Returns {:ok, center_pixel} or {:error, reason}
  """
  def place_mega_pixel(x, y, color, user_id) do
    # Check cooldown
    case check_cooldown(user_id) do
      :ok ->
        # Get user stats to check if they have mega pixels available
        stats = get_or_create_user_stats(user_id)

        if stats.mega_pixels_available > 0 do
          # Check if all 9 positions are free (3x3 grid centered on x,y)
          positions = for dx <- -1..1, dy <- -1..1, do: {x + dx, y + dy}

          occupied = Enum.any?(positions, fn {px, py} ->
            pixel_at(px, py) != nil || px < 0 || py < 0 || px >= @canvas_width || py >= @canvas_height
          end)

          if occupied do
            {:error, :insufficient_space}
          else
            # Insert center pixel first
            center_attrs = %{x: x, y: y, color: color, user_id: user_id, pixel_tier: :mega, is_massive: true}

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
                    pixel_tier: :mega,
                    is_massive: true,
                    parent_pixel_id: center_pixel.id
                  }

                  %Pixel{} |> Pixel.changeset(attrs) |> Repo.insert()
                end)

                # Update user stats: decrement available mega pixels, increment used count
                update_user_progress(user_id, :mega)

                {:ok, center_pixel}

              error ->
                error
            end
          end
        else
          {:error, :no_mega_pixels_available}
        end

      {:error, seconds_remaining} ->
        {:error, {:cooldown, seconds_remaining}}
    end
  end

  @doc """
  Places a massive pixel (5x5 grid) on the canvas.
  Returns {:ok, center_pixel} or {:error, reason}
  """
  def place_massive_pixel(x, y, color, user_id) do
    # Check cooldown
    case check_cooldown(user_id) do
      :ok ->
        # Get user stats to check if they have massive pixels available
        stats = get_or_create_user_stats(user_id)

        if stats.massive_pixels_available > 0 do
          # Check if all 25 positions are free (5x5 grid centered on x,y)
          positions = for dx <- -2..2, dy <- -2..2, do: {x + dx, y + dy}

          occupied = Enum.any?(positions, fn {px, py} ->
            pixel_at(px, py) != nil || px < 0 || py < 0 || px >= @canvas_width || py >= @canvas_height
          end)

          if occupied do
            {:error, :insufficient_space}
          else
            # Insert center pixel first
            center_attrs = %{x: x, y: y, color: color, user_id: user_id, pixel_tier: :massive, is_massive: true}

            case %Pixel{} |> Pixel.changeset(center_attrs) |> Repo.insert() do
              {:ok, center_pixel} ->
                # Insert surrounding 24 pixels
                surrounding_positions = positions -- [{x, y}]

                Enum.each(surrounding_positions, fn {px, py} ->
                  attrs = %{
                    x: px,
                    y: py,
                    color: color,
                    user_id: user_id,
                    pixel_tier: :massive,
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

  defp update_user_progress(user_id, pixel_tier) do
    stats = get_or_create_user_stats(user_id)

    case pixel_tier do
      :normal ->
        new_count = stats.pixels_placed_count + 1

        # Check if user unlocked a mega pixel (every 15 normal pixels)
        {new_mega_count, mega_last_unlock} =
          if rem(new_count, @pixels_required_for_mega_unlock) == 0 do
            {stats.mega_pixels_available + 1, DateTime.utc_now()}
          else
            {stats.mega_pixels_available, stats.mega_last_unlock_at}
          end

        # Check if user unlocked a massive pixel (bonus: every 100 normal pixels)
        {new_massive_count, last_unlock} =
          if rem(new_count, @pixels_required_for_massive_bonus) == 0 do
            {stats.massive_pixels_available + 1, DateTime.utc_now()}
          else
            {stats.massive_pixels_available, stats.last_unlock_at}
          end

        # Check global milestones and award special pixels
        check_and_unlock_milestones()

        stats
        |> UserPixelStats.changeset(%{
          pixels_placed_count: new_count,
          mega_pixels_available: new_mega_count,
          mega_last_unlock_at: mega_last_unlock,
          massive_pixels_available: new_massive_count,
          last_unlock_at: last_unlock
        })
        |> Repo.update()

      :mega ->
        # Mega pixel used - decrement available, increment used count
        new_used_count = stats.mega_pixels_used_count + 1

        # Check if user unlocked a massive pixel (fusion: every 5 mega pixels used)
        {new_massive_count, last_unlock} =
          if rem(new_used_count, @mega_pixels_required_for_massive_unlock) == 0 do
            {stats.massive_pixels_available + 1, DateTime.utc_now()}
          else
            {stats.massive_pixels_available, stats.last_unlock_at}
          end

        stats
        |> UserPixelStats.changeset(%{
          mega_pixels_available: stats.mega_pixels_available - 1,
          mega_pixels_used_count: new_used_count,
          massive_pixels_available: new_massive_count,
          last_unlock_at: last_unlock
        })
        |> Repo.update()

      :massive ->
        # Massive pixel used - no progression, just track
        {:ok, stats}
    end
  end

  @doc """
  Returns global milestone progress information.
  """
  def milestone_progress do
    total_pixels = Repo.aggregate(Pixel, :count)
    
    # Define milestones: every 1000 pixels unlocks a special pixel
    milestones = [
      %{threshold: 1000, reward: "unicorn", name: "Unicorn"},
      %{threshold: 2000, reward: "star", name: "Star"},
      %{threshold: 3000, reward: "diamond", name: "Diamond"},
      %{threshold: 5000, reward: "rainbow", name: "Rainbow"},
      %{threshold: 10000, reward: "crown", name: "Crown"}
    ]

    # Find next milestone and current progress
    next_milestone = Enum.find(milestones, fn m -> total_pixels < m.threshold end)
    
    unlocked_rewards = Enum.filter(milestones, fn m -> total_pixels >= m.threshold end)
                       |> Enum.map(& &1.reward)

    %{
      total_pixels: total_pixels,
      next_milestone: next_milestone,
      unlocked_rewards: unlocked_rewards,
      all_milestones: milestones
    }
  end

  @doc """
  Check and unlock global milestones, distributing special pixels to all active users.
  """
  def check_and_unlock_milestones do
    total_pixels = Repo.aggregate(Pixel, :count)
    
    # Milestones to check
    milestones_to_check = [
      %{type: "pixels_1000", threshold: 1000, reward: "unicorn"},
      %{type: "pixels_2000", threshold: 2000, reward: "star"},
      %{type: "pixels_3000", threshold: 3000, reward: "diamond"},
      %{type: "pixels_5000", threshold: 5000, reward: "rainbow"},
      %{type: "pixels_10000", threshold: 10000, reward: "crown"}
    ]

    Enum.each(milestones_to_check, fn milestone ->
      if total_pixels >= milestone.threshold do
        # Check if already unlocked
        existing = Repo.get_by(GlobalMilestone, milestone_type: milestone.type)
        
        if is_nil(existing) do
          # Unlock milestone
          %GlobalMilestone{}
          |> GlobalMilestone.changeset(%{
            milestone_type: milestone.type,
            threshold: milestone.threshold,
            reward_type: milestone.reward,
            unlocked_at: DateTime.utc_now(),
            total_pixels_when_unlocked: total_pixels
          })
          |> Repo.insert()

          # Award special pixel to ALL users
          award_special_pixel_to_all_users(milestone.reward)
        end
      end
    end)
  end

  defp award_special_pixel_to_all_users(reward_type) do
    # Get all users who have placed pixels
    user_stats = Repo.all(UserPixelStats)
    
    Enum.each(user_stats, fn stats ->
      # Add the special pixel to their available map
      updated_specials = Map.update(
        stats.special_pixels_available || %{},
        reward_type,
        1,
        &(&1 + 1)
      )
      
      stats
      |> UserPixelStats.changeset(%{special_pixels_available: updated_specials})
      |> Repo.update()
    end)
  end
end
