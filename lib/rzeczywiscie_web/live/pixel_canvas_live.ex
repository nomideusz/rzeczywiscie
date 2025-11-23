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
    cooldown = PixelCanvas.check_cooldown(user_id)
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
      |> assign(:page_title, "Pixel Canvas")
      |> assign(:pixels_version, 0)  # Add version counter to force Svelte updates

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
        stats: @stats
      }}
      socket={@socket}
    />
    """
  end

  def handle_event("place_pixel", %{"x" => x, "y" => y}, socket) do
    color = socket.assigns.selected_color
    user_id = socket.assigns.user_id

    case PixelCanvas.place_pixel(x, y, color, user_id) do
      {:ok, pixel} ->
        # Update pixels map with the newly placed pixel
        pixels = Map.put(socket.assigns.pixels, {x, y}, %{
          color: color,
          user_id: user_id,
          updated_at: pixel.updated_at
        })

        stats = PixelCanvas.stats()

        # Broadcast to all connected clients (including stats)
        IO.inspect("Broadcasting pixel placement: x=#{x}, y=#{y}, color=#{color}")
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:pixel_placed, x, y, color, user_id, stats}
        )

        # Schedule cooldown update
        Process.send_after(self(), :update_cooldown, 1000)

        {:noreply,
         socket
         |> assign(:pixels, pixels)
         |> assign(:pixels_version, socket.assigns.pixels_version + 1)
         |> assign(:can_place, false)
         |> assign(:seconds_remaining, PixelCanvas.cooldown_seconds())
         |> assign(:stats, stats)}

      {:error, {:cooldown, seconds}} ->
        {:noreply, put_flash(socket, :error, "Cooldown: #{seconds}s remaining")}

      {:error, changeset} ->
        error_msg = format_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, selected_color: color)}
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
  def handle_info({:pixel_placed, x, y, color, user_id, stats}, socket) do
    IO.inspect("Received pixel_placed event: x=#{x}, y=#{y}, my_user_id=#{socket.assigns.user_id}, sender_user_id=#{user_id}")

    # Don't update if this was our own pixel (already updated)
    if user_id != socket.assigns.user_id do
      IO.inspect("Updating pixels for other user's placement")
      pixels = Map.put(socket.assigns.pixels, {x, y}, %{
        color: color,
        user_id: user_id,
        updated_at: DateTime.utc_now()
      })

      {:noreply,
       socket
       |> assign(:pixels, pixels)
       |> assign(:pixels_version, socket.assigns.pixels_version + 1)
       |> assign(:stats, stats)}
    else
      IO.inspect("Ignoring own pixel placement")
      {:noreply, socket}
    end
  end

  defp serialize_pixels(pixels) do
    Enum.map(pixels, fn {{x, y}, data} ->
      %{x: x, y: y, color: data.color}
    end)
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
