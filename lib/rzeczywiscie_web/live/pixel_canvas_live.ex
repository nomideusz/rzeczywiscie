defmodule RzeczywiscieWeb.PixelCanvasLive do
  use RzeczywiscieWeb, :live_view
  alias Rzeczywiscie.PixelCanvas

  @topic "pixel_canvas"

  def mount(_params, _session, socket) do
    # Initially use IP-based user_id, client will send browser-specific ID after mount
    user_id = get_or_create_user_id(socket)
    # Generate unique session ID for this specific LiveView connection
    session_id = generate_session_id()

    if connected?(socket) do
      # Subscribe to global canvas updates only
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
    end
    {width, height} = PixelCanvas.canvas_size()
    pixels = PixelCanvas.load_canvas()
    stats = PixelCanvas.stats()
    user_stats = PixelCanvas.get_user_stats(user_id)
    cooldown = PixelCanvas.check_cooldown(user_id)
    seconds_remaining = get_seconds_remaining(cooldown)
    milestone_progress = PixelCanvas.milestone_progress()

    # Start cooldown timer if user is on cooldown
    if connected?(socket) && seconds_remaining > 0 do
      Process.send_after(self(), :update_cooldown, 1000)
    end

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:session_id, session_id)
      |> assign(:canvas_width, width)
      |> assign(:canvas_height, height)
      |> assign(:pixels, pixels)
      |> assign(:colors, PixelCanvas.available_colors())
      |> assign(:selected_color, List.first(PixelCanvas.available_colors()))
      |> assign(:cooldown_seconds, PixelCanvas.cooldown_seconds())
      |> assign(:can_place, cooldown == :ok)
      |> assign(:seconds_remaining, seconds_remaining)
      |> assign(:stats, stats)
      |> assign(:user_stats, user_stats)
      |> assign(:pixel_mode, :normal)  # Can be :normal, :mega, :massive, or :special
      |> assign(:selected_special_type, nil)
      |> assign(:milestone_progress, milestone_progress)
      |> assign(:page_title, "Pixels")
      |> assign(:pixels_version, 0)
      |> assign(:cursors, %{})

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.svelte
      name="PixelCanvas"
      props={%{
        width: @canvas_width,
        height: @canvas_height,
        pixels: serialize_pixels(@pixels),
        pixelsVersion: @pixels_version,
        colors: @colors,
        selectedColor: @selected_color,
        canPlace: @can_place,
        secondsRemaining: @seconds_remaining,
        cooldownSeconds: @cooldown_seconds,
        stats: @stats,
        cursors: serialize_cursors(@cursors),
        userStats: serialize_user_stats(@user_stats),
        pixelMode: @pixel_mode,
        milestoneProgress: @milestone_progress
      }}
      socket={@socket}
    />
    <Layouts.flash_group flash={@flash} />
    """
  end

  def handle_event("place_pixel", %{"x" => x, "y" => y}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id

    # Check if pixel already exists
    existing_pixel = Map.get(socket.assigns.pixels, {x, y})

    if existing_pixel do
      # Position occupied - pixels are now permanent!
      {:noreply, put_flash(socket, :error, "Position already occupied")}
    else
      case PixelCanvas.place_pixel(x, y, color, user_id) do
        {:ok, pixel} ->
          # Update pixels map with the newly placed pixel
          pixels = Map.put(socket.assigns.pixels, {x, y}, %{
            color: color,
            user_id: user_id,
            updated_at: pixel.updated_at,
            pixel_tier: :normal
          })

          stats = PixelCanvas.stats()
          user_stats = PixelCanvas.get_user_stats(user_id)
          milestone_progress = PixelCanvas.milestone_progress()

          # Broadcast to all connected clients (including stats and milestone progress)
          Phoenix.PubSub.broadcast(
            Rzeczywiscie.PubSub,
            @topic,
            {:pixel_placed, x, y, color, user_id, :normal, stats, milestone_progress, socket.assigns.session_id}
          )

          # Schedule cooldown update
          Process.send_after(self(), :update_cooldown, 1000)

          socket = socket
           |> assign(:pixels, pixels)
           |> assign(:pixels_version, socket.assigns.pixels_version + 1)
           |> assign(:can_place, false)
           |> assign(:seconds_remaining, PixelCanvas.cooldown_seconds())
           |> assign(:stats, stats)
           |> assign(:user_stats, user_stats)
           |> assign(:milestone_progress, milestone_progress)

          {:noreply, socket}

        {:error, {:cooldown, _seconds}} ->
          # Don't show toast - visual cooldown timer on button is enough
          {:noreply, socket}

        {:error, :position_occupied} ->
          {:noreply, put_flash(socket, :error, "Position already occupied")}

        {:error, changeset} ->
          error_msg = format_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end
  end

  def handle_event("place_mega_pixel", %{"x" => x, "y" => y}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id

    case PixelCanvas.place_mega_pixel(x, y, color, user_id) do
      {:ok, _center_pixel} ->
        # Reload all pixels (easier than updating 9 individually)
        pixels = PixelCanvas.load_canvas()
        stats = PixelCanvas.stats()
        user_stats = PixelCanvas.get_user_stats(user_id)
        milestone_progress = PixelCanvas.milestone_progress()

        # Broadcast mega pixel placement
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:mega_pixel_placed, x, y, color, user_id, stats, milestone_progress, socket.assigns.session_id}
        )

        # Schedule cooldown update (mega pixel has 45s cooldown)
        Process.send_after(self(), :update_cooldown, 1000)

        {:noreply,
         socket
         |> assign(:pixels, pixels)
         |> assign(:pixels_version, socket.assigns.pixels_version + 1)
         |> assign(:can_place, false)
         |> assign(:seconds_remaining, 45)
         |> assign(:stats, stats)
         |> assign(:user_stats, user_stats)
         |> assign(:milestone_progress, milestone_progress)
         |> put_flash(:info, "Mega pixel placed! ⭐")}

      {:error, {:cooldown, _seconds}} ->
        # Don't show toast - visual cooldown timer on color picker is enough
        {:noreply, socket}

      {:error, :no_mega_pixels_available} ->
        {:noreply, put_flash(socket, :error, "No mega pixels available. Place 15 regular pixels to unlock one!")}

      {:error, :insufficient_space} ->
        {:noreply, put_flash(socket, :error, "Insufficient space for 3x3 mega pixel")}

      {:error, changeset} ->
        error_msg = format_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("place_massive_pixel", %{"x" => x, "y" => y}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id

    case PixelCanvas.place_massive_pixel(x, y, color, user_id) do
      {:ok, _center_pixel} ->
        # Reload all pixels (easier than updating 25 individually)
        pixels = PixelCanvas.load_canvas()
        stats = PixelCanvas.stats()
        user_stats = PixelCanvas.get_user_stats(user_id)
        milestone_progress = PixelCanvas.milestone_progress()

        # Broadcast massive pixel placement
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:massive_pixel_placed, x, y, color, user_id, stats, milestone_progress, socket.assigns.session_id}
        )

        # Schedule cooldown update (massive pixel has 120s cooldown)
        Process.send_after(self(), :update_cooldown, 1000)

        {:noreply,
         socket
         |> assign(:pixels, pixels)
         |> assign(:pixels_version, socket.assigns.pixels_version + 1)
         |> assign(:can_place, false)
         |> assign(:seconds_remaining, 120)
         |> assign(:stats, stats)
         |> assign(:user_stats, user_stats)
         |> assign(:milestone_progress, milestone_progress)
         |> put_flash(:info, "Massive pixel placed! 🌈")}

      {:error, {:cooldown, _seconds}} ->
        # Don't show toast - visual cooldown timer on color picker is enough
        {:noreply, socket}

      {:error, :no_massive_pixels_available} ->
        {:noreply, put_flash(socket, :error, "No massive pixels available. Use 5 mega pixels to unlock one!")}

      {:error, :insufficient_space} ->
        {:noreply, put_flash(socket, :error, "Insufficient space for 5x5 massive pixel")}

      {:error, changeset} ->
        error_msg = format_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("toggle_pixel_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_existing_atom(mode)

    {:noreply, assign(socket, pixel_mode: new_mode)}
  end

  def handle_event("select_special_pixel", %{"special_type" => special_type}, socket) do
    {:noreply, 
     socket
     |> assign(:pixel_mode, :special)
     |> assign(:selected_special_type, special_type)}
  end

  def handle_event("place_special_pixel", %{"x" => x, "y" => y, "name" => name}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id
    special_type = socket.assigns.selected_special_type

    case PixelCanvas.place_special_pixel(x, y, color, user_id, special_type, name, color) do
      {:ok, pixel} ->
        pixels = Map.put(socket.assigns.pixels, {x, y}, %{
          color: color,
          user_id: user_id,
          updated_at: pixel.updated_at,
          pixel_tier: :normal,
          is_special: true,
          special_type: special_type,
          claimer_name: name,
          claimer_color: color
        })

        stats = PixelCanvas.stats()
        user_stats = PixelCanvas.get_user_stats(user_id)
        milestone_progress = PixelCanvas.milestone_progress()

        # Broadcast special pixel placement
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:special_pixel_placed, x, y, color, user_id, special_type, name, color, stats, milestone_progress, socket.assigns.session_id}
        )

        # Schedule cooldown update
        Process.send_after(self(), :update_cooldown, 1000)

        {:noreply,
         socket
         |> assign(:pixels, pixels)
         |> assign(:pixels_version, socket.assigns.pixels_version + 1)
         |> assign(:can_place, false)
         |> assign(:seconds_remaining, PixelCanvas.cooldown_seconds())
         |> assign(:stats, stats)
         |> assign(:user_stats, user_stats)
         |> assign(:milestone_progress, milestone_progress)
         |> assign(:pixel_mode, :normal)
         |> assign(:selected_special_type, nil)
         |> put_flash(:info, "Special #{special_type} pixel claimed! #{name} ✨")}

      {:error, :no_special_pixel_available} ->
        {:noreply, put_flash(socket, :error, "You don't have this special pixel available")}

      {:error, :position_occupied} ->
        {:noreply, put_flash(socket, :error, "Position already occupied")}

      {:error, {:cooldown, _seconds}} ->
        {:noreply, socket}

      {:error, changeset} ->
        error_msg = format_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, selected_color: color)}
  end

  def handle_event("set_user_id", %{"user_id" => client_user_id}, socket) do
    # Client sends device-specific user_id from localStorage
    # Reload user stats and milestone progress with the correct device fingerprint user_id
    user_stats = PixelCanvas.get_user_stats(client_user_id)
    cooldown = PixelCanvas.check_cooldown(client_user_id)
    seconds_remaining = get_seconds_remaining(cooldown)
    milestone_progress = PixelCanvas.milestone_progress()
    
    # Start cooldown timer if needed
    if connected?(socket) && seconds_remaining > 0 do
      Process.send_after(self(), :update_cooldown, 1000)
    end
    
    {:noreply, 
     socket
     |> assign(:user_id, client_user_id)
     |> assign(:user_stats, user_stats)
     |> assign(:milestone_progress, milestone_progress)
     |> assign(:can_place, cooldown == :ok)
     |> assign(:seconds_remaining, seconds_remaining)}
  end

  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    user_id = socket.assigns.user_id
    selected_color = socket.assigns.selected_color

    # Broadcast cursor position to all connected clients
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {:cursor_move, user_id, x, y, selected_color}
    )

    {:noreply, socket}
  end


  # Update cooldown timer every second
  def handle_info(:update_cooldown, socket) do
    cooldown = PixelCanvas.check_cooldown(socket.assigns.user_id)

    socket =
      assign(socket,
        can_place: cooldown == :ok,
        seconds_remaining: get_seconds_remaining(cooldown)
      )

    # Keep updating if still on cooldown
    if socket.assigns.seconds_remaining > 0 do
      Process.send_after(self(), :update_cooldown, 1000)
    end

    {:noreply, socket}
  end

  # Handle pixel placed by other sessions (including same user on different devices)
  def handle_info({:pixel_placed, x, y, color, user_id, pixel_tier, stats, milestone_progress, from_session_id}, socket) do
    # Update pixels for all sessions except the one that placed it
    if from_session_id != socket.assigns.session_id do
      pixels = Map.put(socket.assigns.pixels, {x, y}, %{
        color: color,
        user_id: user_id,
        updated_at: DateTime.utc_now(),
        pixel_tier: pixel_tier,
        is_special: false,
        special_type: nil,
        claimer_name: nil,
        claimer_color: nil
      })

      # Reload user stats to get any newly unlocked special pixels
      user_stats = PixelCanvas.get_user_stats(socket.assigns.user_id)

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)
       |> assign(:user_stats, user_stats)}
    else
      # Still update stats and milestones even for own session to ensure consistency
      {:noreply, 
       socket
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)}
    end
  end

  # Handle mega pixel placed by other sessions (including same user on different devices)
  def handle_info({:mega_pixel_placed, _x, _y, _color, _user_id, stats, milestone_progress, from_session_id}, socket) do
    # Update pixels for all sessions except the one that placed it
    if from_session_id != socket.assigns.session_id do
      # Reload all pixels to get the 3x3 grid
      pixels = PixelCanvas.load_canvas()
      # Reload user stats to get any newly unlocked special pixels
      user_stats = PixelCanvas.get_user_stats(socket.assigns.user_id)

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)
       |> assign(:user_stats, user_stats)}
    else
      # Still update stats and milestones even for own session to ensure consistency
      {:noreply, 
       socket
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)}
    end
  end

  # Handle massive pixel placed by other sessions (including same user on different devices)
  def handle_info({:massive_pixel_placed, _x, _y, _color, _user_id, stats, milestone_progress, from_session_id}, socket) do
    # Update pixels for all sessions except the one that placed it
    if from_session_id != socket.assigns.session_id do
      # Reload all pixels to get the 5x5 grid
      pixels = PixelCanvas.load_canvas()
      # Reload user stats to get any newly unlocked special pixels
      user_stats = PixelCanvas.get_user_stats(socket.assigns.user_id)

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)
       |> assign(:user_stats, user_stats)}
    else
      # Still update stats and milestones even for own session to ensure consistency
      {:noreply, 
       socket
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)}
    end
  end

  # Handle special pixel placed by other sessions
  def handle_info({:special_pixel_placed, x, y, color, user_id, special_type, claimer_name, claimer_color, stats, milestone_progress, from_session_id}, socket) do
    # Update pixels for all sessions except the one that placed it
    if from_session_id != socket.assigns.session_id do
      pixels = Map.put(socket.assigns.pixels, {x, y}, %{
        color: color,
        user_id: user_id,
        updated_at: DateTime.utc_now(),
        pixel_tier: :normal,
        is_special: true,
        special_type: special_type,
        claimer_name: claimer_name,
        claimer_color: claimer_color
      })

      # Reload user stats to get updated special pixels count
      user_stats = PixelCanvas.get_user_stats(socket.assigns.user_id)

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)
       |> assign(:user_stats, user_stats)}
    else
      {:noreply, 
       socket
       |> assign(:stats, stats)
       |> assign(:milestone_progress, milestone_progress)}
    end
  end

  # Handle cursor movements from other users
  def handle_info({:cursor_move, user_id, x, y, color}, socket) do
    # Don't track our own cursor
    if user_id != socket.assigns.user_id do
      cursors = Map.put(socket.assigns.cursors, user_id, %{
        x: x,
        y: y,
        color: color,
        timestamp: System.system_time(:second)
      })

      # Clean up stale cursors (older than 3 seconds)
      now = System.system_time(:second)
      cursors = Map.filter(cursors, fn {_id, data} -> now - data.timestamp < 3 end)

      {:noreply, assign(socket, cursors: cursors)}
    else
      {:noreply, socket}
    end
  end


  defp serialize_pixels(pixels) do
    Enum.map(pixels, fn {{x, y}, data} ->
      %{
        x: x,
        y: y,
        color: data.color,
        pixel_tier: Atom.to_string(data.pixel_tier),
        is_special: data.is_special,
        special_type: data.special_type,
        claimer_name: data.claimer_name,
        claimer_color: data.claimer_color
      }
    end)
  end

  defp serialize_cursors(cursors) do
    Enum.map(cursors, fn {user_id, data} ->
      %{
        id: String.slice(user_id, 0, 6),  # First 6 chars for display
        x: data.x,
        y: data.y,
        color: data.color
      }
    end)
  end

  defp serialize_user_stats(user_stats) do
    %{
      pixels_placed: user_stats.pixels_placed_count,
      mega_pixels_available: user_stats.mega_pixels_available,
      mega_pixels_used: user_stats.mega_pixels_used_count,
      massive_pixels_available: user_stats.massive_pixels_available,
      special_pixels_available: user_stats.special_pixels_available || %{},
      progress_to_mega: rem(user_stats.pixels_placed_count, 15),
      progress_to_massive_fusion: rem(user_stats.mega_pixels_used_count, 5),
      progress_to_massive_bonus: rem(user_stats.pixels_placed_count, 100)
    }
  end

  defp get_seconds_remaining(:ok), do: 0
  defp get_seconds_remaining({:error, seconds}), do: seconds

  defp format_error(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
      |> Enum.map(fn {field, messages} ->
        "#{field}: #{Enum.join(messages, ", ")}"
      end)
      |> Enum.join("; ")

    "Error: #{errors}"
  end

  # Get or create user ID (same pattern as other features)
  defp get_or_create_user_id(socket) do
    get_peer_ip_id(socket) || get_user_agent_id(socket) || get_fallback_id()
  end

  defp get_user_agent_id(socket) do
    case get_connect_info(socket, :user_agent) do
      nil -> nil
      ua when is_binary(ua) and ua != "" ->
        :crypto.hash(:md5, ua) |> Base.encode16(case: :lower) |> String.slice(0, 16)
      _ -> nil
    end
  end

  defp get_peer_ip_id(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} ->
        ip_string = :inet.ntoa(address) |> to_string()
        :crypto.hash(:md5, ip_string) |> Base.encode16(case: :lower) |> String.slice(0, 16)
      _ -> nil
    end
  end

  defp get_fallback_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Generate unique session ID for each LiveView connection
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
