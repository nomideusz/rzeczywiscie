defmodule Rzeczywiscie.Services.AirQuality do
  @moduledoc """
  Google Air Quality API integration to fetch AQI data for coordinates.
  """

  require Logger
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.AirQuality.Cache
  import Ecto.Query

  @base_url "https://airquality.googleapis.com/v1/currentConditions:lookup"
  # Cache AQI data for 6 hours
  @cache_duration_hours 6
  # Round coordinates to this precision for grid-based caching
  @grid_precision 2

  @doc """
  Get air quality data for given coordinates.
  Uses cached data if available and not expired.
  """
  def get_air_quality(lat, lng) when is_number(lat) and is_number(lng) do
    # Round to grid for caching
    grid_lat = round_to_grid(lat)
    grid_lng = round_to_grid(lng)

    case get_from_cache(grid_lat, grid_lng) do
      {:ok, cached} ->
        Logger.debug("Using cached AQI for #{grid_lat}, #{grid_lng}")
        {:ok, cached}

      {:error, :not_found} ->
        Logger.debug("No cache found for #{grid_lat}, #{grid_lng}, fetching")
        fetch_and_cache(grid_lat, grid_lng)

      {:error, :expired} ->
        Logger.debug("Cache expired for #{grid_lat}, #{grid_lng}, refetching")
        fetch_and_cache(grid_lat, grid_lng)
    end
  end

  def get_air_quality(%Decimal{} = lat, %Decimal{} = lng) do
    get_air_quality(Decimal.to_float(lat), Decimal.to_float(lng))
  end

  def get_air_quality(_, _), do: {:error, :invalid_coordinates}

  @doc """
  Get AQI for a property. Returns nil if property has no coordinates.
  """
  def get_property_aqi(property) do
    if property.latitude && property.longitude do
      case get_air_quality(property.latitude, property.longitude) do
        {:ok, aqi_data} -> aqi_data
        {:error, _} -> nil
      end
    else
      nil
    end
  end

  defp get_from_cache(lat, lng) do
    lat_decimal = Decimal.from_float(lat)
    lng_decimal = Decimal.from_float(lng)

    query =
      from c in Cache,
        where: c.lat == ^lat_decimal and c.lng == ^lng_decimal,
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      cache ->
        now = DateTime.utc_now()

        if DateTime.compare(cache.expires_at, now) == :gt do
          {:ok, format_cache_data(cache)}
        else
          {:error, :expired}
        end
    end
  end

  defp fetch_and_cache(lat, lng) do
    case fetch_air_quality(lat, lng) do
      {:ok, aqi_data} ->
        Logger.info("Fetched AQI for #{lat}, #{lng}: #{aqi_data.aqi} (#{aqi_data.category})")
        save_to_cache(lat, lng, aqi_data)
        {:ok, aqi_data}

      error ->
        error
    end
  end

  defp fetch_air_quality(lat, lng) do
    api_key = Application.get_env(:rzeczywiscie, :google_maps_api_key, "")

    if api_key == "" do
      Logger.warning("Google Maps API key not configured")
      {:error, :api_key_not_configured}
    else
      body = %{
        location: %{
          latitude: lat,
          longitude: lng
        }
      }

      url = "#{@base_url}?key=#{api_key}"

      case Req.post(url, json: body) do
        {:ok, %{status: 200, body: response}} ->
          parse_air_quality_response(response)

        {:ok, %{status: status}} ->
          Logger.error("Air Quality API returned status #{status}")
          {:error, :api_error}

        {:error, reason} ->
          Logger.error("Air Quality request failed: #{inspect(reason)}")
          {:error, :request_failed}
      end
    end
  end

  defp parse_air_quality_response(%{"indexes" => indexes}) when is_list(indexes) do
    # Find the Universal AQI index
    universal_aqi = Enum.find(indexes, fn idx -> idx["code"] == "uaqi" end)

    if universal_aqi do
      {:ok,
       %{
         aqi: universal_aqi["aqi"],
         category: universal_aqi["category"],
         dominant_pollutant: universal_aqi["dominantPollutant"],
         color: universal_aqi["color"]
       }}
    else
      {:error, :no_aqi_data}
    end
  end

  defp parse_air_quality_response(_) do
    {:error, :invalid_response}
  end

  defp save_to_cache(lat, lng, aqi_data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @cache_duration_hours * 3600, :second)

    lat_decimal = Decimal.from_float(lat)
    lng_decimal = Decimal.from_float(lng)

    attrs = %{
      lat: lat_decimal,
      lng: lng_decimal,
      aqi: aqi_data.aqi,
      category: aqi_data.category,
      dominant_pollutant: aqi_data.dominant_pollutant,
      fetched_at: now,
      expires_at: expires_at
    }

    # Upsert: update if exists, insert if not
    query =
      from c in Cache,
        where: c.lat == ^lat_decimal and c.lng == ^lng_decimal

    case Repo.one(query) do
      nil ->
        %Cache{}
        |> Cache.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Cache.changeset(attrs)
        |> Repo.update()
    end
  end

  defp format_cache_data(cache) do
    %{
      aqi: cache.aqi,
      category: cache.category,
      dominant_pollutant: cache.dominant_pollutant,
      cached: true,
      fetched_at: cache.fetched_at
    }
  end

  defp round_to_grid(coordinate) do
    # Round to grid precision (e.g., 2 decimal places = ~1km grid)
    Float.round(coordinate, @grid_precision)
  end

  @doc """
  Get AQI category color for UI display.
  """
  def category_color(category) when is_binary(category) do
    case String.downcase(category) do
      "good" -> "success"
      "moderate" -> "warning"
      "unhealthy for sensitive groups" -> "warning"
      "unhealthy" -> "error"
      "very unhealthy" -> "error"
      "hazardous" -> "error"
      _ -> "neutral"
    end
  end

  def category_color(_), do: "neutral"
end
