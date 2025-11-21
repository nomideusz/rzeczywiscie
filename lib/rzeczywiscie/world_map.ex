defmodule Rzeczywiscie.WorldMap do
  @moduledoc """
  The WorldMap context - manages global presence and pins with real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.WorldMap.Pin

  @topic "world_map"
  @presence_topic "world_presence"

  @doc """
  Subscribe to world map updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Subscribe to presence updates.
  """
  def subscribe_presence do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @presence_topic)
  end

  @doc """
  Broadcast pin updates to all subscribed clients.
  """
  def broadcast_pin(pin, event) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {event, pin}
    )
  end

  @doc """
  Get all pins from the map.
  """
  def list_pins do
    Pin
    |> order_by([p], desc: p.inserted_at)
    |> limit(1000)  # Limit to most recent 1000 pins
    |> Repo.all()
    |> Enum.map(&pin_to_map/1)
  end

  @doc """
  Create a new pin and broadcast it.
  """
  def create_pin(attrs) do
    %Pin{}
    |> Pin.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, pin} ->
        pin_map = pin_to_map(pin)
        broadcast_pin(pin_map, :pin_created)
        {:ok, pin_map}

      error ->
        error
    end
  end

  @doc """
  Delete a pin and broadcast the deletion.
  """
  def delete_pin(id) do
    case Repo.get(Pin, id) do
      nil ->
        {:error, :not_found}

      pin ->
        Repo.delete(pin)
        broadcast_pin(%{id: id}, :pin_deleted)
        {:ok, pin}
    end
  end

  @doc """
  Get geolocation data from IP address.
  Uses ip-api.com free tier (45 requests per minute).
  """
  def get_geolocation(ip) do
    # Handle localhost/development
    ip = if ip in ["127.0.0.1", "::1", nil], do: "", else: ip

    url = "http://ip-api.com/json/#{ip}?fields=status,message,country,countryCode,city,lat,lon,timezone,query"

    case :httpc.request(:get, {String.to_charlist(url), []}, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(List.to_string(body)) do
          {:ok, %{"status" => "success"} = data} ->
            {:ok,
             %{
               country: data["country"],
               country_code: data["countryCode"],
               city: data["city"],
               lat: data["lat"],
               lng: data["lon"],
               timezone: data["timezone"],
               ip: data["query"]
             }}

          {:ok, %{"status" => "fail", "message" => _message}} ->
            # API failed (e.g., private IP range) - use default location
            {:ok, default_location()}

          _ ->
            # Default to Warsaw, Poland for development/localhost
            {:ok, default_location()}
        end

      _ ->
        {:ok, default_location()}
    end
  end

  defp default_location do
    %{
      country: "Poland",
      country_code: "PL",
      city: "Warsaw",
      lat: 52.2297,
      lng: 21.0122,
      timezone: "Europe/Warsaw",
      ip: "localhost"
    }
  end

  defp pin_to_map(pin) do
    %{
      id: pin.id,
      user_name: pin.user_name,
      user_color: pin.user_color,
      lat: pin.lat,
      lng: pin.lng,
      message: pin.message,
      emoji: pin.emoji,
      image_data: pin.image_data,
      ip_address: pin.ip_address,
      country: pin.country,
      city: pin.city,
      created_at: pin.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    }
  end
end
