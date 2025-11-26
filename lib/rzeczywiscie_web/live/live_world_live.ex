defmodule RzeczywiscieWeb.LiveWorldLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.WorldMap

  @topic "world_map"
  @presence_topic "world_presence"

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <.svelte
        name="LiveWorld"
        props={%{
          currentUser: @current_user,
          users: @users,
          pins: @pins,
          googleMapsApiKey: @google_maps_api_key
        }}
        socket={@socket}
      />
    </.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to world map updates and presence
      WorldMap.subscribe()
      RzeczywiscieWeb.Endpoint.subscribe(@presence_topic)

      # Get user's IP and geolocation
      ip = get_connect_ip(socket)
      {:ok, geo} = WorldMap.get_geolocation(ip)

      # Generate user identity
      user_name = generate_username()
      user_color = generate_user_color()
      user_id = generate_user_id()

      current_user = %{
        id: user_id,
        name: user_name,
        color: user_color,
        country: geo.country,
        country_code: geo.country_code,
        city: geo.city,
        lat: geo.lat,
        lng: geo.lng,
        timezone: geo.timezone,
        ip: geo.ip,
        joined_at: System.system_time(:second)
      }

      # Track presence
      {:ok, _} =
        RzeczywiscieWeb.Presence.track(
          self(),
          @presence_topic,
          user_id,
          current_user
        )

      # Get all existing pins
      pins = WorldMap.list_pins()

      {:ok,
       socket
       |> assign(:current_user, current_user)
       |> assign(:users, get_present_users())
       |> assign(:pins, pins)
       |> assign(:google_maps_api_key, get_google_maps_api_key())}
    else
      {:ok,
       socket
       |> assign(:current_user, %{})
       |> assign(:users, [])
       |> assign(:pins, [])
       |> assign(:google_maps_api_key, "")}
    end
  end

  def handle_event("drop_pin", %{"lat" => lat, "lng" => lng} = params, socket) do
    message = Map.get(params, "message", "")
    emoji = Map.get(params, "emoji", "📍")
    image_data = Map.get(params, "image_data")

    user = socket.assigns.current_user

    pin_attrs = %{
      user_name: user.name,
      user_color: user.color,
      lat: lat,
      lng: lng,
      message: message,
      emoji: emoji,
      image_data: image_data,
      ip_address: user.ip,
      country: user.country,
      city: user.city
    }

    WorldMap.create_pin(pin_attrs)

    {:noreply, socket}
  end

  def handle_event("delete_pin", %{"pin_id" => pin_id}, socket) do
    WorldMap.delete_pin(pin_id)
    {:noreply, socket}
  end

  def handle_event("cursor_move", %{"lat" => lat, "lng" => lng}, socket) do
    # Broadcast cursor position to other users
    RzeczywiscieWeb.Endpoint.broadcast_from(
      self(),
      @presence_topic,
      "cursor_move",
      %{
        user_id: socket.assigns.current_user.id,
        user_name: socket.assigns.current_user.name,
        color: socket.assigns.current_user.color,
        lat: lat,
        lng: lng
      }
    )

    {:noreply, socket}
  end

  def handle_event("send_chat", %{"message" => message}, socket) do
    chat_message = %{
      user_name: socket.assigns.current_user.name,
      color: socket.assigns.current_user.color,
      message: message,
      timestamp: System.system_time(:second)
    }

    broadcast_chat_message(chat_message)
    {:noreply, socket}
  end

  # Handle pin broadcasts
  def handle_info({:pin_created, pin}, socket) do
    pins = [pin | socket.assigns.pins]
    {:noreply,
     socket
     |> assign(:pins, pins)
     |> push_event("pin_created", pin)}
  end

  def handle_info({:pin_deleted, %{id: id}}, socket) do
    pins = Enum.reject(socket.assigns.pins, &(&1.id == id))
    {:noreply,
     socket
     |> assign(:pins, pins)
     |> push_event("pin_deleted", %{id: id})}
  end

  # Handle presence updates
  def handle_info(%{event: "presence_diff"}, socket) do
    users = get_present_users()

    {:noreply,
     socket
     |> assign(:users, users)
     |> push_event("presence_update", %{users: users})}
  end

  # Handle cursor movements from other users
  def handle_info(%{event: "cursor_move", payload: cursor_data}, socket) do
    {:noreply, push_event(socket, "cursor_move", cursor_data)}
  end

  # Handle chat messages
  def handle_info({:chat_message, message}, socket) do
    {:noreply, push_event(socket, "chat_message", message)}
  end

  defp get_present_users do
    RzeczywiscieWeb.Presence.list(@presence_topic)
    |> Enum.map(fn {_id, %{metas: [meta | _]}} -> meta end)
  end

  defp broadcast_chat_message(message) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {:chat_message, message}
    )
  end

  defp get_connect_ip(socket) do
    # First, try to get real IP from proxy headers (x-real-ip or x-forwarded-for)
    case get_in(socket.private, [:connect_info, :x_headers]) do
      headers when is_list(headers) ->
        # Look for x-real-ip first, then x-forwarded-for
        real_ip = Enum.find_value(headers, fn
          {"x-real-ip", ip} -> ip
          _ -> nil
        end)

        forwarded_ip = Enum.find_value(headers, fn
          {"x-forwarded-for", ips} ->
            # x-forwarded-for can have multiple IPs, get the first one
            ips |> String.split(",") |> List.first() |> String.trim()
          _ -> nil
        end)

        real_ip || forwarded_ip || get_peer_ip(socket)

      _ ->
        get_peer_ip(socket)
    end
  end

  defp get_peer_ip(socket) do
    case get_in(socket.private, [:connect_info, :peer_data, :address]) do
      {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
      _ -> nil
    end
  end

  defp get_google_maps_api_key do
    # You can set this in config or environment variable
    Application.get_env(:rzeczywiscie, :google_maps_api_key, "")
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp generate_username do
    adjectives = [
      "Swift",
      "Bright",
      "Clever",
      "Bold",
      "Happy",
      "Cosmic",
      "Mighty",
      "Noble",
      "Quick",
      "Wise",
      "Epic",
      "Wild"
    ]

    nouns = [
      "Explorer",
      "Voyager",
      "Nomad",
      "Wanderer",
      "Traveler",
      "Pioneer",
      "Navigator",
      "Adventurer"
    ]

    "#{Enum.random(adjectives)} #{Enum.random(nouns)}"
  end

  defp generate_user_color do
    colors = [
      "#FF6B6B",
      "#4ECDC4",
      "#45B7D1",
      "#FFA07A",
      "#98D8C8",
      "#F7DC6F",
      "#BB8FCE",
      "#85C1E2",
      "#F8B500",
      "#52B788",
      "#E74C3C",
      "#3498DB",
      "#9B59B6",
      "#1ABC9C",
      "#F39C12"
    ]

    Enum.random(colors)
  end
end
