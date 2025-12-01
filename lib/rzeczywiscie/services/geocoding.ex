defmodule Rzeczywiscie.Services.Geocoding do
  @moduledoc """
  Google Geocoding API integration to convert addresses to coordinates.
  
  Includes district-level coordinate caching to avoid redundant API calls
  for properties in the same district without street addresses.
  """

  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"
  
  # Pre-computed district centers for Kraków - saves API calls
  # These are approximate centers, good enough for properties without street addresses
  @krakow_district_coords %{
    "stare miasto" => {50.0614, 19.9366},
    "grzegórzki" => {50.0683, 19.9656},
    "prądnik czerwony" => {50.0919, 19.9428},
    "prądnik biały" => {50.1050, 19.9150},
    "krowodrza" => {50.0780, 19.9100},
    "bronowice" => {50.0800, 19.8850},
    "zwierzyniec" => {50.0530, 19.8820},
    "dębniki" => {50.0380, 19.9280},
    "łagiewniki-borek fałęcki" => {50.0150, 19.9350},
    "swoszowice" => {49.9970, 19.9450},
    "podgórze duchackie" => {50.0180, 19.9600},
    "bieżanów-prokocim" => {50.0100, 20.0100},
    "podgórze" => {50.0450, 19.9500},
    "czyżyny" => {50.0750, 20.0100},
    "mistrzejowice" => {50.1050, 20.0000},
    "bieńczyce" => {50.0950, 20.0350},
    "wzgórza krzesławickie" => {50.1020, 20.0650},
    "nowa huta" => {50.0700, 20.0350},
    "ruczaj" => {50.0250, 19.8900},
    "wola justowska" => {50.0600, 19.8550},
    "salwator" => {50.0580, 19.9080},
    "tonie" => {50.1150, 19.8900},
    "łobzów" => {50.0750, 19.9200},
    "kazimierz" => {50.0510, 19.9450},
    "zabłocie" => {50.0480, 19.9620},
    "płaszów" => {50.0350, 19.9800},
    "kurdwanów" => {50.0050, 19.9250},
    "kliny" => {50.0000, 19.8750},
    "bieżanów" => {50.0050, 20.0300},
    "prokocim" => {50.0150, 20.0000},
    "wola duchacka" => {50.0100, 19.9700},
    "piaski wielkie" => {50.0200, 20.0250},
    "rybitwy" => {50.0100, 20.0600},
    "przewóz" => {50.0000, 20.0500},
    "wieliczka" => {49.9870, 20.0650},
    "niepołomice" => {50.0300, 20.2200},
    "skawina" => {49.9750, 19.8300},
    "zabierzów" => {50.1200, 19.7900},
    "zielonki" => {50.1300, 19.9300},
    "michałowice" => {50.1100, 19.8700},
    "mogilany" => {49.9350, 19.9100},
    "siepraw" => {49.9180, 19.9900},
    "myślenice" => {49.8350, 19.9400},
    "dobczyce" => {49.8850, 20.0950},
    "krzeszowice" => {50.1350, 19.6300},
    "świątniki górne" => {49.9550, 19.8800},
    "gdów" => {49.9100, 20.1950}
  }

  @doc """
  Geocode an address to get latitude and longitude.

  ## Examples

      iex> geocode("Kraków, Małopolskie, Poland")
      {:ok, %{lat: 50.0646, lng: 19.9450}}

      iex> geocode("")
      {:error, :invalid_address}
  """
  def geocode(address) when is_binary(address) and address != "" do
    api_key = Application.get_env(:rzeczywiscie, :google_maps_api_key, "")

    if api_key == "" do
      Logger.warning("Google Maps API key not configured")
      {:error, :api_key_not_configured}
    else
      params = %{
        address: address,
        key: api_key,
        region: "pl"  # Prefer Polish results
      }

      url = "#{@base_url}?#{URI.encode_query(params)}"

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          parse_geocoding_response(body)

        {:ok, %{status: status}} ->
          Logger.error("Geocoding API returned status #{status}")
          {:error, :api_error}

        {:error, reason} ->
          Logger.error("Geocoding request failed: #{inspect(reason)}")
          {:error, :request_failed}
      end
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  @doc """
  Geocode a property using city, district, and street information.
  
  Uses cached district coordinates for properties without street addresses
  to avoid redundant API calls. Only calls Google API when:
  - Property has a specific street address
  - District is not in the cache
  """
  def geocode_property(property) do
    has_street? = property.street && property.street != "" && String.length(property.street) > 3
    district = normalize_district(property.district)
    
    cond do
      # If we have a street, use full geocoding for precision
      has_street? ->
        address = build_address_string(property)
        if address && address != "", do: geocode(address), else: {:error, :insufficient_location_data}
      
      # If no street but district is cached, use cached coordinates (FREE!)
      cached = Map.get(@krakow_district_coords, district) ->
        {lat, lng} = cached
        Logger.debug("Using cached coordinates for district: #{district}")
        {:ok, %{
          lat: Decimal.from_float(lat),
          lng: Decimal.from_float(lng),
          formatted_address: "#{property.district || district}, #{property.city || "Kraków"}, Poland"
        }}
      
      # District not cached - try API for the district only
      district && district != "" ->
        Logger.info("District not in cache, geocoding: #{district}")
        address = build_address_string(property)
        if address && address != "", do: geocode(address), else: {:error, :insufficient_location_data}
      
      # No usable location data
      true ->
        {:error, :insufficient_location_data}
    end
  end
  
  @doc """
  Check if a district is cached (for logging/stats).
  """
  def district_cached?(district) do
    Map.has_key?(@krakow_district_coords, normalize_district(district))
  end
  
  @doc """
  List all cached districts.
  """
  def cached_districts, do: Map.keys(@krakow_district_coords)
  
  defp normalize_district(nil), do: nil
  defp normalize_district(district) do
    district
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp build_address_string(property) do
    parts = [
      property.street,
      property.district,
      property.city,
      property.voivodeship || "małopolskie",
      "Poland"
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp parse_geocoding_response(%{"status" => "OK", "results" => [result | _]}) do
    location = get_in(result, ["geometry", "location"])

    if location && location["lat"] && location["lng"] do
      {:ok,
       %{
         lat: Decimal.from_float(location["lat"]),
         lng: Decimal.from_float(location["lng"]),
         formatted_address: result["formatted_address"]
       }}
    else
      {:error, :invalid_response}
    end
  end

  defp parse_geocoding_response(%{"status" => "ZERO_RESULTS"}) do
    {:error, :not_found}
  end

  defp parse_geocoding_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    Logger.warning("Geocoding API quota exceeded")
    {:error, :quota_exceeded}
  end

  defp parse_geocoding_response(%{"status" => status}) do
    Logger.error("Geocoding API returned unexpected status: #{status}")
    {:error, :api_error}
  end

  defp parse_geocoding_response(_) do
    {:error, :invalid_response}
  end
end
