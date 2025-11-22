defmodule RzeczywiscieWeb.RealEstateLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Workers.GeocodingWorker
  alias Rzeczywiscie.Services.AirQuality

  @impl true
  def mount(_params, session, socket) do
    # Subscribe to real-time updates
    if connected?(socket) do
      RealEstate.subscribe()
    end

    user_id = get_user_id(session, socket)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:filters, %{})
      |> assign(:sort_column, "inserted_at")
      |> assign(:sort_direction, "desc")
      |> assign(:page, 1)
      |> assign(:page_size, 50)
      |> load_properties()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <.svelte
        name="PropertyView"
        props={%{
          properties: serialize_properties(@properties, @user_id),
          map_properties: serialize_properties(@all_map_properties, @user_id),
          pagination: %{
            page: @page,
            page_size: @page_size,
            total_count: @total_count,
            total_pages: @total_pages
          },
          stats: %{
            total_count: @total_count,
            with_coords: @total_with_coords,
            with_aqi: @total_with_aqi
          },
          user_id: @user_id
        }}
        socket={@socket}
      />
    </.app>
    """
  end

  @impl true
  def handle_event("filters_changed", filters, socket) do
    Logger.debug("Filters changed: #{inspect(filters)}")

    # Convert string keys to atoms and parse values
    parsed_filters =
      filters
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Enum.into(%{})

    socket =
      socket
      |> assign(:filters, parsed_filters)
      |> assign(:page, 1)  # Reset to first page when filters change
      |> load_properties()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_changed", %{"column" => column, "direction" => direction}, socket) do
    Logger.debug("Sort changed: #{column} #{direction}")

    socket =
      socket
      |> assign(:sort_column, column)
      |> assign(:sort_direction, direction)
      |> load_properties()

    {:noreply, socket}
  end

  @impl true
  def handle_event("trigger_geocoding", _params, socket) do
    Logger.info("Manual geocoding triggered")

    case GeocodingWorker.trigger(batch_size: 50, delay_ms: 500) do
      {:ok, _job} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Geocoding job started. Coordinates will be added to properties."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start geocoding: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("page_changed", %{"page" => page}, socket) when is_integer(page) do
    Logger.debug("Page changed: #{page}")

    socket =
      socket
      |> assign(:page, max(1, page))
      |> load_properties()

    {:noreply, socket}
  end

  def handle_event("page_changed", %{"page" => page}, socket) when is_binary(page) do
    case Integer.parse(page) do
      {page_num, _} -> handle_event("page_changed", %{"page" => page_num}, socket)
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_favorite", %{"property_id" => property_id}, socket) do
    property_id = if is_binary(property_id), do: String.to_integer(property_id), else: property_id
    user_id = socket.assigns.user_id

    try do
      is_favorited = RealEstate.is_favorited?(property_id, user_id)

      result = if is_favorited do
        RealEstate.remove_favorite(property_id, user_id)
        "Removed from favorites"
      else
        case RealEstate.add_favorite(property_id, user_id) do
          {:ok, _favorite} -> "Added to favorites"
          {:error, _changeset} -> "Already in favorites"
        end
      end

      socket =
        socket
        |> put_flash(:info, result)
        |> load_properties()

      {:noreply, socket}
    rescue
      e ->
        Logger.error("Error toggling favorite: #{inspect(e)}")
        {:noreply, put_flash(socket, :error, "Failed to update favorites. Please run database migrations: mix ecto.migrate")}
    end
  end

  @impl true
  def handle_info({:property_created, _property}, socket) do
    Logger.debug("New property created, reloading...")
    socket = load_properties(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:property_updated, _property}, socket) do
    Logger.debug("Property updated, reloading...")
    socket = load_properties(socket)
    {:noreply, socket}
  end

  defp load_properties(socket) do
    filters = Map.get(socket.assigns, :filters, %{})
    sort_column = Map.get(socket.assigns, :sort_column, "inserted_at")
    sort_direction = Map.get(socket.assigns, :sort_direction, "desc")
    page = Map.get(socket.assigns, :page, 1)
    page_size = Map.get(socket.assigns, :page_size, 50)

    # Calculate offset
    offset = (page - 1) * page_size

    # Build query options for paginated list
    opts =
      filters
      |> Map.to_list()
      |> Keyword.new()
      |> Keyword.put(:limit, page_size)
      |> Keyword.put(:offset, offset)

    # Get total count for pagination
    total_count = RealEstate.count_properties(Keyword.new(Map.to_list(filters)))

    # Get paginated properties for table
    properties = RealEstate.list_properties(opts)

    # Sort in memory (could be moved to query for better performance)
    sorted_properties = sort_properties(properties, sort_column, sort_direction)

    # Get ALL properties with coordinates for map (with same filters but no pagination)
    map_opts =
      filters
      |> Map.to_list()
      |> Keyword.new()
      |> Keyword.put(:limit, 10000)  # High limit to get all

    all_map_properties = RealEstate.list_properties(map_opts)

    # Calculate global stats
    with_coords = Enum.count(all_map_properties, fn p -> p.latitude && p.longitude end)
    with_aqi = Enum.count(all_map_properties, fn p ->
      if p.latitude && p.longitude do
        aqi_data = Rzeczywiscie.Services.AirQuality.get_property_aqi(p)
        aqi_data && aqi_data.aqi
      else
        false
      end
    end)

    socket
    |> assign(:properties, sorted_properties)
    |> assign(:all_map_properties, all_map_properties)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, ceil(total_count / page_size))
    |> assign(:total_with_coords, with_coords)
    |> assign(:total_with_aqi, with_aqi)
  end

  defp sort_properties(properties, column, direction) do
    column_atom = String.to_existing_atom(column)

    sorted =
      Enum.sort_by(properties, fn property ->
        value = Map.get(property, column_atom)

        # Handle nil values
        case value do
          nil -> if direction == "asc", do: "", else: "zzz"
          %Decimal{} -> Decimal.to_float(value)
          _ -> value
        end
      end)

    if direction == "desc", do: Enum.reverse(sorted), else: sorted
  rescue
    ArgumentError ->
      # If column doesn't exist, return unsorted
      properties
  end

  defp serialize_properties(properties, user_id) do
    Enum.map(properties, fn property ->
      # Get air quality data if property has coordinates
      aqi_data = AirQuality.get_property_aqi(property)

      # Check if property is favorited by user (handle case where table doesn't exist)
      is_favorited = try do
        RealEstate.is_favorited?(property.id, user_id)
      rescue
        _ -> false
      end

      %{
        id: property.id,
        source: property.source,
        external_id: property.external_id,
        title: property.title,
        description: property.description,
        price: serialize_decimal(property.price),
        currency: property.currency,
        area_sqm: serialize_decimal(property.area_sqm),
        rooms: property.rooms,
        floor: property.floor,
        transaction_type: property.transaction_type,
        property_type: property.property_type,
        city: property.city,
        district: property.district,
        street: property.street,
        postal_code: property.postal_code,
        voivodeship: property.voivodeship,
        latitude: serialize_decimal(property.latitude),
        longitude: serialize_decimal(property.longitude),
        url: property.url,
        image_url: property.image_url,
        active: property.active,
        last_seen_at: serialize_datetime(property.last_seen_at),
        inserted_at: serialize_datetime(property.inserted_at),
        updated_at: serialize_datetime(property.updated_at),
        aqi: aqi_data && aqi_data.aqi,
        aqi_category: aqi_data && aqi_data.category,
        dominant_pollutant: aqi_data && aqi_data.dominant_pollutant,
        is_favorited: is_favorited
      }
    end)
  end

  defp serialize_decimal(nil), do: nil
  defp serialize_decimal(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp serialize_decimal(value), do: value

  defp serialize_datetime(nil), do: nil
  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_datetime(value), do: value

  defp get_user_id(session, socket) do
    # For now, use session ID or generate a browser fingerprint
    # In a real app, this would be the authenticated user ID
    session["user_id"] || socket.id
  end
end
