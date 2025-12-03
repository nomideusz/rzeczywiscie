defmodule Rzeczywiscie.Services.Geocoding do
  @moduledoc """
  Google Geocoding API integration to convert addresses to coordinates.
  
  Includes location coordinate caching for Małopolskie region to avoid redundant API calls
  for properties without street addresses.
  """

  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"
  
  # Pre-computed coordinates for Małopolskie locations - saves API calls
  # Includes: Kraków districts, major cities, towns, and villages
  # These are approximate centers, good enough for properties without street addresses
  @malopolskie_coords %{
    # === KRAKÓW DISTRICTS ===
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
    
    # === MAJOR CITIES ===
    "kraków" => {50.0647, 19.9450},
    "tarnów" => {50.0121, 20.9858},
    "nowy sącz" => {49.6249, 20.6915},
    "oświęcim" => {50.0343, 19.2098},
    "chrzanów" => {50.1358, 19.4025},
    "olkusz" => {50.2817, 19.5640},
    "nowy targ" => {49.4770, 20.0326},
    "gorlice" => {49.6556, 21.1600},
    "zakopane" => {49.2992, 19.9496},
    "bochnia" => {49.9693, 20.4308},
    "brzesko" => {49.9686, 20.6083},
    "wadowice" => {49.8833, 19.4933},
    "andrychów" => {49.8550, 19.3383},
    "limanowa" => {49.7022, 20.4256},
    "miechów" => {50.3572, 20.0289},
    "proszowice" => {50.1897, 20.2889},
    "dąbrowa tarnowska" => {50.1728, 20.9856},
    "kęty" => {49.8817, 19.2233},
    "trzebinia" => {50.1622, 19.4731},
    "sucha beskidzka" => {49.7419, 19.5892},
    
    # === KRAKÓW SUBURBS & NEARBY TOWNS ===
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
    "gdów" => {49.9100, 20.1950},
    "słomniki" => {50.2400, 20.0800},
    "igołomia-wawrzeńczyce" => {50.1100, 20.2600},
    "kocmyrzów-luborzyca" => {50.1400, 20.1100},
    "liszki" => {50.0300, 19.7700},
    "czernichów" => {49.9900, 19.6900},
    "sułoszowa" => {50.2700, 19.6900},
    "jerzmanowice-przeginia" => {50.2300, 19.7400},
    "jerzmanowice" => {50.2300, 19.7400},
    "przeginia" => {50.2100, 19.7200},
    "iwanowice" => {50.2000, 20.0100},
    "koniusza" => {50.1800, 20.2400},
    "biskupice" => {50.0500, 20.2900},
    "drwinia" => {50.0500, 20.3800},
    "nowe brzesko" => {50.1300, 20.3700},
    
    # === OTHER MAŁOPOLSKIE COMMUNES/VILLAGES ===
    "kalwaria zebrzydowska" => {49.8686, 19.6764},
    "lanckorona" => {49.8450, 19.7300},
    "stryszów" => {49.8100, 19.5900},
    "mucharz" => {49.8100, 19.5300},
    "budzów" => {49.7400, 19.6300},
    "maków podhalański" => {49.7278, 19.6839},
    "zawoja" => {49.6400, 19.5400},
    "jordanów" => {49.6550, 19.8317},
    "bystra-sidzina" => {49.6800, 19.7900},
    "rabka-zdrój" => {49.6097, 19.9672},
    "mszana dolna" => {49.6764, 20.0794},
    "niedźwiedź" => {49.6200, 20.0900},
    "dobra" => {49.6600, 20.2500},
    "kamienica" => {49.6100, 20.3500},
    "łącko" => {49.5700, 20.4300},
    "podegrodzie" => {49.5700, 20.6000},
    "stary sącz" => {49.5617, 20.6350},
    "piwniczna-zdrój" => {49.4400, 20.7100},
    "rytro" => {49.4900, 20.6700},
    "nawojowa" => {49.5800, 20.7400},
    "łabowa" => {49.5200, 20.8400},
    "krynica-zdrój" => {49.4217, 20.9583},
    "muszyna" => {49.3500, 20.8900},
    "tylicz" => {49.4000, 21.0200},
    "uście gorlickie" => {49.4700, 21.1400},
    "sękowa" => {49.5600, 21.1200},
    "lipinki" => {49.6600, 21.2000},
    "biecz" => {49.7328, 21.2614},
    "bobowa" => {49.7100, 20.9500},
    "łużna" => {49.7300, 21.0500},
    "ropa" => {49.6000, 21.1100},
    "grybów" => {49.6250, 20.9500},
    "korzenna" => {49.6300, 20.7700},
    "chełmiec" => {49.6400, 20.6500},
    "łososina dolna" => {49.7300, 20.5400},
    "tymbark" => {49.7200, 20.3300},
    "jodłownik" => {49.7600, 20.2800},
    "łukowica" => {49.7100, 20.4500},
    "słopnice" => {49.7100, 20.2100},
    "pcim" => {49.7400, 20.0100},
    "lubień" => {49.7100, 19.9700},
    "wiśniowa" => {49.7800, 20.1200},
    "raciechowice" => {49.8300, 20.1500},
    "tokarnia" => {49.7800, 19.8600},
    "spytkowice" => {49.9100, 19.5700},
    "zembrzyce" => {49.8000, 19.5100},
    "osiek" => {49.9600, 19.3200},
    "polanka wielka" => {49.9800, 19.3000},
    "przeciszów" => {50.0000, 19.4300},
    "zator" => {49.9939, 19.4347},
    "alwernia" => {50.0600, 19.5400},
    "babice" => {50.1000, 19.4600},
    "libiąż" => {50.1000, 19.3100},
    "jaworzno" => {50.2044, 19.2750},
    "bukowno" => {50.2700, 19.4500},
    "bolesław" => {50.2900, 19.4900},
    "klucze" => {50.3200, 19.5600},
    "wolbrom" => {50.3800, 19.7600},
    "trzyciąż" => {50.3000, 19.7900},
    "charsznica" => {50.4000, 20.0000},
    "kozłów" => {50.4300, 20.1800},
    "książ wielki" => {50.4000, 20.2200},
    "słaboszów" => {50.3800, 20.3500},
    "racławice" => {50.3100, 20.2100},
    "pałecznica" => {50.2500, 20.2700},
    "radziemice" => {50.2300, 20.3300},
    "szczurowa" => {50.1000, 20.6300},
    "wietrzychowice" => {50.1200, 20.7500},
    "żabno" => {50.1300, 20.8700},
    "radłów" => {50.0800, 20.8500},
    "wierzchosławice" => {50.0300, 20.8800},
    "lisia góra" => {50.0000, 20.9700},
    "tuchów" => {49.8950, 21.0500},
    "ryglice" => {49.8900, 21.1400},
    "ciężkowice" => {49.7800, 21.0000},
    "pleśna" => {49.8600, 20.9300},
    "wojnicz" => {49.9600, 20.8400},
    "zakliczyn" => {49.8500, 20.8100},
    "gromnik" => {49.8400, 20.9400},
    "czchów" => {49.8200, 20.6800},
    "gnojnik" => {49.8700, 20.7300},
    "iwkowa" => {49.8300, 20.5800},
    "lipnica murowana" => {49.8900, 20.4500},
    "trzciana" => {49.8800, 20.3400},
    "żegocina" => {49.8600, 20.2300},
    "nowy wiśnicz" => {49.9100, 20.4700},
    "łapanów" => {49.8800, 20.3100},
    "drwinia" => {50.0500, 20.3800},
    "kłaj" => {50.0200, 20.2400},
    "gołcza" => {50.3400, 19.9700},
    "skała" => {50.2300, 19.8500},
    "sułoszowa" => {50.2700, 19.6900},
    "ojców" => {50.2100, 19.8300},
    "wielka wieś" => {50.1600, 19.8200},
    "przytkowice" => {49.9200, 19.6700},
    "stara wieś" => {49.9000, 19.7100},
    "brzeźnica" => {49.9700, 19.6100}
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
  
  Uses cached coordinates for properties without street addresses
  to avoid redundant API calls. Only calls Google API when:
  - Property has a specific street address
  - Neither city nor district is in the cache
  """
  def geocode_property(property) do
    has_street? = property.street && property.street != "" && String.length(property.street) > 3
    
    cond do
      # If we have a street, use full geocoding for precision
      has_street? ->
        address = build_address_string(property)
        if address && address != "", do: geocode(address), else: {:error, :insufficient_location_data}
      
      # Check district cache first (more specific)
      cached = lookup_cached_coords(property.district) ->
        {lat, lng} = cached
        Logger.debug("Using cached coordinates for district: #{property.district}")
        {:ok, %{
          lat: Decimal.from_float(lat),
          lng: Decimal.from_float(lng),
          formatted_address: "#{property.district}, #{property.city || "Małopolskie"}, Poland"
        }}
      
      # Then check city cache (for standalone cities/towns)
      cached = lookup_cached_coords(property.city) ->
        {lat, lng} = cached
        Logger.debug("Using cached coordinates for city: #{property.city}")
        {:ok, %{
          lat: Decimal.from_float(lat),
          lng: Decimal.from_float(lng),
          formatted_address: "#{property.city}, Małopolskie, Poland"
        }}
      
      # Not cached - try API with best available location data
      has_location_data?(property) ->
        Logger.info("Location not in cache, geocoding: #{property.district || property.city}")
        address = build_address_string(property)
        if address && address != "", do: geocode(address), else: {:error, :insufficient_location_data}
      
      # No usable location data
      true ->
        {:error, :insufficient_location_data}
    end
  end
  
  defp has_location_data?(property) do
    (property.district && property.district != "") ||
    (property.city && property.city != "")
  end
  
  @doc """
  Check if a location (district or city) is cached.
  """
  def location_cached?(location) do
    lookup_cached_coords(location) != nil
  end
  
  # Keep old function name for backward compatibility
  def district_cached?(district), do: location_cached?(district)
  
  @doc """
  List all cached locations.
  """
  def cached_locations, do: Map.keys(@malopolskie_coords)
  def cached_districts, do: cached_locations()
  
  defp normalize_location(nil), do: nil
  defp normalize_location(location) do
    location
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
  
  # Try to find location in cache, handling diacritic variations
  defp lookup_cached_coords(nil), do: nil
  defp lookup_cached_coords(location) do
    normalized = normalize_location(location)
    
    # First try exact match (after lowercase)
    case Map.get(@malopolskie_coords, normalized) do
      nil ->
        # Try without diacritics
        ascii_key = strip_diacritics(normalized)
        find_by_ascii_key(ascii_key)
      coords -> 
        coords
    end
  end
  
  defp strip_diacritics(str) do
    str
    |> String.replace("ó", "o")
    |> String.replace("ą", "a")
    |> String.replace("ę", "e")
    |> String.replace("ł", "l")
    |> String.replace("ń", "n")
    |> String.replace("ś", "s")
    |> String.replace("ć", "c")
    |> String.replace("ż", "z")
    |> String.replace("ź", "z")
  end
  
  defp find_by_ascii_key(ascii_key) do
    # Search through cache keys, strip diacritics from each and compare
    Enum.find_value(@malopolskie_coords, fn {key, coords} ->
      if strip_diacritics(key) == ascii_key, do: coords, else: nil
    end)
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
