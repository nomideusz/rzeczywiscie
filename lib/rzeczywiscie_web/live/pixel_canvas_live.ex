defmodule RzeczywiscieWeb.PixelCanvasLive do
  use RzeczywiscieWeb, :live_view
  alias Rzeczywiscie.PixelCanvas

  @topic "pixel_canvas"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
    end

    user_id = get_or_create_user_id(socket)
    {width, height} = PixelCanvas.canvas_size()
    pixels = PixelCanvas.load_canvas()
    stats = PixelCanvas.stats()
    user_stats = PixelCanvas.get_user_stats(user_id)
    cooldown = PixelCanvas.check_cooldown(user_id, false)
    seconds_remaining = get_seconds_remaining(cooldown)

    # Start cooldown timer if user is on cooldown
    if connected?(socket) && seconds_remaining > 0 do
      Process.send_after(self(), :update_cooldown, 1000)
    end

    socket =
      socket
      |> assign(:user_id, user_id)
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
      |> assign(:is_massive_mode, false)
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
        isMassiveMode: @is_massive_mode
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
            is_massive: false
          })

          stats = PixelCanvas.stats()
          user_stats = PixelCanvas.get_user_stats(user_id)

          # Check if user just unlocked a massive pixel
          unlocked = rem(user_stats.pixels_placed_count, 15) == 0

          # Broadcast to all connected clients (including stats)
          Phoenix.PubSub.broadcast(
            Rzeczywiscie.PubSub,
            @topic,
            {:pixel_placed, x, y, color, user_id, false, stats}
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

          # Show unlock message if applicable
          socket = if unlocked do
            put_flash(socket, :info, "🎉 MASSIVE PIXEL UNLOCKED! You can now place a 3x3 pixel!")
          else
            socket
          end

          {:noreply, socket}

        {:error, {:cooldown, seconds}} ->
          {:noreply, put_flash(socket, :error, "Cooldown: #{seconds}s remaining")}

        {:error, :position_occupied} ->
          {:noreply, put_flash(socket, :error, "Position already occupied")}

        {:error, changeset} ->
          error_msg = format_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end
  end

  def handle_event("place_massive_pixel", %{"x" => x, "y" => y}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id

    case PixelCanvas.place_massive_pixel(x, y, color, user_id) do
      {:ok, _center_pixel} ->
        # Reload all pixels (easier than updating 9 individually)
        pixels = PixelCanvas.load_canvas()
        stats = PixelCanvas.stats()
        user_stats = PixelCanvas.get_user_stats(user_id)

        # Broadcast massive pixel placement
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:massive_pixel_placed, x, y, color, user_id, stats}
        )

        # Schedule cooldown update (massive pixel has 3x cooldown)
        Process.send_after(self(), :update_cooldown, 1000)

        {:noreply,
         socket
         |> assign(:pixels, pixels)
         |> assign(:pixels_version, socket.assigns.pixels_version + 1)
         |> assign(:can_place, false)
         |> assign(:seconds_remaining, 45)
         |> assign(:stats, stats)
         |> assign(:user_stats, user_stats)
         |> put_flash(:info, "Massive pixel placed! 🚀")}

      {:error, {:cooldown, seconds}} ->
        {:noreply, put_flash(socket, :error, "Cooldown: #{seconds}s remaining")}

      {:error, :no_massive_pixels_available} ->
        {:noreply, put_flash(socket, :error, "No massive pixels available. Place 15 regular pixels to unlock one!")}

      {:error, :insufficient_space} ->
        {:noreply, put_flash(socket, :error, "Insufficient space for 3x3 massive pixel")}

      {:error, changeset} ->
        error_msg = format_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("toggle_massive_mode", _, socket) do
    {:noreply, assign(socket, is_massive_mode: !socket.assigns.is_massive_mode)}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, selected_color: color)}
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

  # Handle pixel placed by other users
  def handle_info({:pixel_placed, x, y, color, user_id, is_massive, stats}, socket) do
    # Don't update if this was our own pixel (already updated)
    if user_id != socket.assigns.user_id do
      pixels = Map.put(socket.assigns.pixels, {x, y}, %{
        color: color,
        user_id: user_id,
        updated_at: DateTime.utc_now(),
        is_massive: is_massive
      })

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)}
    else
      {:noreply, socket}
    end
  end

  # Handle massive pixel placed by other users
  def handle_info({:massive_pixel_placed, _x, _y, _color, user_id, stats}, socket) do
    # Don't update if this was our own pixel (already updated)
    if user_id != socket.assigns.user_id do
      # Reload all pixels to get the 3x3 grid
      pixels = PixelCanvas.load_canvas()

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)}
    else
      {:noreply, socket}
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
      %{x: x, y: y, color: data.color, is_massive: data.is_massive || false}
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
      massive_pixels_available: user_stats.massive_pixels_available,
      progress_to_next: rem(user_stats.pixels_placed_count, 15)
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
    get_user_agent_id(socket) || get_peer_ip_id(socket) || get_fallback_id()
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
end
