defmodule RzeczywiscieWeb.PixelCanvasLive do
  use RzeczywiscieWeb, :live_view
  alias Rzeczywiscie.PixelCanvas

  @topic "pixel_canvas"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
    end

    {width, height} = PixelCanvas.canvas_size()
    user_id = get_or_create_user_id(socket)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:canvas_width, width)
      |> assign(:canvas_height, height)
      |> assign(:colors, PixelCanvas.available_colors())
      |> assign(:selected_color, hd(PixelCanvas.available_colors()))
      |> assign(:cooldown_seconds, PixelCanvas.cooldown_seconds())
      |> assign(:seconds_remaining, PixelCanvas.seconds_remaining(user_id))
      |> assign(:stats, PixelCanvas.stats())
      |> assign(:page_title, "Pixels")

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.svelte
      name="PixelCanvas"
      props={%{
        width: @canvas_width,
        height: @canvas_height,
        colors: @colors,
        selectedColor: @selected_color,
        secondsRemaining: @seconds_remaining,
        cooldownSeconds: @cooldown_seconds,
        stats: @stats
      }}
      socket={@socket}
    />
    <Layouts.flash_group flash={@flash} />
    """
  end

  def handle_event("place_pixel", %{"x" => x, "y" => y}, socket)
      when is_integer(x) and is_integer(y) do
    case PixelCanvas.place_pixel(x, y, socket.assigns.selected_color, socket.assigns.user_id) do
      {:ok, pixel} ->
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          @topic,
          {:pixel_placed, pixel.x, pixel.y, pixel.color}
        )

        {:noreply, assign(socket, :seconds_remaining, PixelCanvas.cooldown_seconds())}

      {:error, {:cooldown, remaining}} ->
        {:noreply, assign(socket, :seconds_remaining, remaining)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not place pixel")}
    end
  end

  # Client asks for the full canvas once its event handlers are mounted;
  # afterwards only single-pixel events flow, so props stay tiny.
  def handle_event("load_canvas", _params, socket) do
    {:reply, %{pixels: PixelCanvas.load_canvas()}, socket}
  end

  def handle_event("select_color", %{"color" => color}, socket) do
    if color in socket.assigns.colors do
      {:noreply, assign(socket, :selected_color, color)}
    else
      {:noreply, socket}
    end
  end

  # Browser sends its persistent id after mount so the cooldown follows the
  # browser rather than the IP/user-agent fallback.
  def handle_event("set_user_id", %{"user_id" => user_id}, socket)
      when is_binary(user_id) and byte_size(user_id) in 8..64 do
    {:noreply,
     socket
     |> assign(:user_id, user_id)
     |> assign(:seconds_remaining, PixelCanvas.seconds_remaining(user_id))}
  end

  def handle_event("set_user_id", _params, socket), do: {:noreply, socket}

  def handle_info({:pixel_placed, x, y, color}, socket) do
    {:noreply,
     socket
     |> assign(:stats, PixelCanvas.stats())
     |> push_event("pixel", %{x: x, y: y, color: color})}
  end

  defp get_or_create_user_id(socket) do
    get_user_agent_id(socket) || get_peer_ip_id(socket) || get_fallback_id()
  end

  defp get_user_agent_id(socket) do
    case get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) and ua != "" ->
        :crypto.hash(:md5, ua) |> Base.encode16(case: :lower) |> String.slice(0, 16)

      _ ->
        nil
    end
  end

  defp get_peer_ip_id(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} ->
        ip = :inet.ntoa(address) |> to_string()
        :crypto.hash(:md5, ip) |> Base.encode16(case: :lower) |> String.slice(0, 16)

      _ ->
        nil
    end
  end

  defp get_fallback_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
