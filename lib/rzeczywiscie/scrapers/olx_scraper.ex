defmodule Rzeczywiscie.Scrapers.OlxScraper do
  @moduledoc """
  Scraper for OLX.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate

  @base_url "https://www.olx.pl"
  # OLX search pages are client-side rendered now (no listing HTML to scrape),
  # so we use the same JSON API the site itself calls.
  @api_url "#{@base_url}/api/v1/offers/"
  @category_nieruchomosci 3
  @region_malopolskie 4
  @page_size 50
  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  # OLX category id => {property_type, transaction_type}
  # nil means "not determined by category" (e.g. zamiana), fall back to text heuristics
  @category_map %{
    14 => {"mieszkanie", "sprzedaż"},
    15 => {"mieszkanie", "wynajem"},
    16 => {"mieszkanie", nil},
    18 => {"dom", "sprzedaż"},
    20 => {"dom", "wynajem"},
    22 => {"dom", nil},
    24 => {"działka", "sprzedaż"},
    25 => {"działka", "wynajem"},
    1311 => {"działka", nil},
    125 => {"lokal użytkowy", "sprzedaż"},
    127 => {"lokal użytkowy", "wynajem"},
    1405 => {"lokal użytkowy", nil},
    1329 => {"lokal użytkowy", "sprzedaż"},
    1331 => {"lokal użytkowy", "wynajem"},
    1315 => {"garaż", "sprzedaż"},
    1313 => {"garaż", "wynajem"},
    1317 => {"garaż", nil},
    11 => {"pokój", "wynajem"},
    1323 => {nil, "sprzedaż"},
    1325 => {nil, "wynajem"},
    1327 => {nil, nil}
  }

  @doc """
  Scrape properties from OLX for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 2000)
    * `:enrich` - If true, auto-enriches properties missing data after scraping (default: false)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 2000)
    enrich = Keyword.get(opts, :enrich, false)
    progress = Keyword.get(opts, :progress, fn _msg -> :ok end)

    Logger.info("Starting OLX scrape for Malopolskie region, #{pages} page(s)")

    results =
      1..pages
      |> Enum.flat_map(fn page ->
        case fetch_page(page) do
          {:ok, ads} ->
            properties = ads |> Enum.map(&parse_ad/1) |> Enum.reject(&is_nil/1)
            Logger.info("Scraped page #{page}: found #{length(properties)} properties")
            progress.("page #{page}/#{pages} — #{length(properties)} found")

            # Add delay between requests to be respectful
            if page < pages, do: Process.sleep(delay)

            properties

          {:error, reason} ->
            Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
            progress.("page #{page}/#{pages} — failed: #{inspect(reason)}")
            []
        end
      end)

    # Save results
    progress.("saving #{length(results)} listings…")
    result = save_results(results)
    
    # Auto-enrich if requested
    if enrich do
      Logger.info("🔄 Auto-enriching properties with missing data...")
      with {:ok, %{saved: saved, total: total}} <- result do
        progress.("#{saved}/#{total} saved — enriching missing data…")
      end
      enrich_recent_properties(delay)
    end
    
    result
  end
  
  @doc """
  Enrich recently scraped properties that are missing data.
  Uses the PropertyRescraper to fetch detail pages and fill in:
  - Missing price, area, rooms, district
  - Descriptions
  - Streets (extracted from titles/descriptions)
  - Cities (inferred from districts)
  """
  def enrich_recent_properties(delay \\ 2000) do
    alias Rzeczywiscie.Scrapers.PropertyRescraper
    
    # Rescrape properties missing any key data
    Logger.info("Enriching properties missing price/area/rooms...")
    PropertyRescraper.rescrape_missing(missing: :all, limit: 100, delay: delay)
    
    # Backfill cities from district information
    Logger.info("Backfilling cities from district data...")
    city_count = RealEstate.backfill_cities_from_districts()
    Logger.info("Backfilled #{city_count} cities from districts")
    
    # Fetch descriptions for properties without them
    Logger.info("Fetching descriptions for properties without them...")
    fetch_missing_descriptions(limit: 50, delay: delay)
    
    # Extract streets from titles and descriptions
    Logger.info("Extracting streets from titles/descriptions...")
    street_stats = extract_streets_from_recent()
    Logger.info("Street extraction: #{street_stats.updated} updated, #{street_stats.skipped} skipped")
  end
  
  defp extract_streets_from_recent do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property
    alias Rzeczywiscie.Services.StreetExtractor
    
    # Get OLX properties without streets, recently scraped first
    properties = Repo.all(
      from p in Property,
        where: p.active == true and p.source == "olx" and (is_nil(p.street) or p.street == ""),
        order_by: [desc: p.inserted_at],
        limit: 200
    )
    
    StreetExtractor.process_batch(properties)
  end
  
  defp fetch_missing_descriptions(opts) do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property
    alias Rzeczywiscie.Scrapers.ExtractionHelpers
    
    limit = Keyword.get(opts, :limit, 50)
    delay = Keyword.get(opts, :delay, 2000)
    
    # Get OLX properties without descriptions, recently scraped first
    properties = Repo.all(
      from p in Property,
        where: p.active == true and p.source == "olx" and (is_nil(p.description) or p.description == ""),
        order_by: [desc: p.inserted_at],
        limit: ^limit,
        select: %{id: p.id, url: p.url}
    )
    
    Logger.info("Found #{length(properties)} OLX properties without descriptions")
    
    Enum.with_index(properties, 1)
    |> Enum.each(fn {prop, index} ->
      Logger.info("[#{index}/#{length(properties)}] Fetching description for ##{prop.id}")
      
      case ExtractionHelpers.fetch_olx_description(prop.url) do
        {:ok, description} when is_binary(description) and description != "" ->
          # Update the property with the description
          property = Rzeczywiscie.RealEstate.get_property(prop.id)
          case Rzeczywiscie.RealEstate.update_property(property, %{description: description}) do
            {:ok, _} -> Logger.info("✓ Updated description for ##{prop.id} (#{String.length(description)} chars)")
            {:error, _} -> Logger.warning("✗ Failed to update description for ##{prop.id}")
          end
        _ ->
          Logger.warning("No description found for ##{prop.id}")
      end
      
      if index < length(properties), do: Process.sleep(delay)
    end)
  end

  # Save function
  defp save_results(results) do
    Logger.info("Starting database save for #{length(results)} properties...")

    saved =
      Enum.with_index(results, 1)
      |> Enum.map(fn {property_data, index} ->
        title_preview = String.slice(property_data.title, 0, 50)
        Logger.info("Saving #{index}/#{length(results)}: #{title_preview} (ID: #{property_data.external_id})")

        try do
          case RealEstate.upsert_property(property_data) do
            {:ok, property} ->
              Logger.info("✓ Saved property ID #{property.id}")
              {:ok, property}

            {:error, changeset} ->
              Logger.error("✗ Failed: #{inspect(changeset.errors)}")
              {:error, changeset}
          end
        rescue
          e ->
            Logger.error("✗ Exception: #{inspect(e)}")
            {:error, e}
        end
      end)

    successful = Enum.count(saved, fn {status, _} -> status == :ok end)
    failed = length(saved) - successful

    Logger.info("OLX scrape completed: #{successful}/#{length(results)} saved, #{failed} failed")

    {:ok, %{total: length(results), saved: successful}}
  end

  defp fetch_page(page) do
    offset = (page - 1) * @page_size
    Logger.info("Fetching OLX API page #{page} (offset #{offset})")

    case Req.get(@api_url,
           params: [
             category_id: @category_nieruchomosci,
             region_id: @region_malopolskie,
             limit: @page_size,
             offset: offset
           ],
           headers: [{"user-agent", @user_agent}, {"accept", "application/json"}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: %{"data" => ads}}} when is_list(ads) ->
        {:ok, ads}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ad(%{"id" => id, "url" => url, "title" => title} = ad) do
    params = Map.new(ad["params"] || [], fn %{"key" => k, "value" => v} -> {k, v} end)
    price = parse_decimal(get_in(params, ["price", "value"]))

    {ptype, ttype} = @category_map[get_in(ad, ["category", "id"])] || {nil, nil}
    search_text = "#{title} #{url}"

    location = ad["location"] || %{}
    {lat, lon} = extract_coords(ad["map"])

    %{
      source: "olx",
      external_id: to_string(id),
      title: String.trim(title),
      url: url,
      price: price,
      currency: get_in(params, ["price", "currency"]) || "PLN",
      area_sqm: parse_decimal(get_in(params, ["m", "key"]) || get_in(params, ["area", "key"])),
      rooms: parse_rooms(get_in(params, ["rooms", "key"])),
      floor: parse_floor(get_in(params, ["floor_select", "key"])),
      transaction_type:
        ttype || validate_transaction_type(extract_transaction_type(search_text), price),
      property_type: ptype || extract_property_type(search_text),
      city: get_in(location, ["city", "name"]),
      district: get_in(location, ["district", "name"]),
      voivodeship: "małopolskie",
      latitude: lat,
      longitude: lon,
      image_url: extract_image(ad["photos"]),
      description: ad["description"],
      raw_data: %{
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  defp parse_ad(ad) do
    Logger.info("Skipping ad without id/url/title: #{inspect(Map.keys(ad))}")
    nil
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_number(value), do: Decimal.new(to_string(value))

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(String.replace(value, ",", ".")) do
      {decimal, _rest} -> decimal
      :error -> nil
    end
  end

  @rooms_map %{"one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
               "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10}
  defp parse_rooms(key), do: @rooms_map[key]

  defp parse_floor("floor_" <> num) do
    case Integer.parse(num) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_floor(_), do: nil

  # radius > 0 means OLX only exposes approximate coordinates - skip those,
  # the app geocodes properties separately and wrong pins are worse than none
  defp extract_coords(%{"radius" => 0, "lat" => lat, "lon" => lon}), do: {lat, lon}
  defp extract_coords(_), do: {nil, nil}

  defp extract_image([%{"link" => link} | _]),
    do: String.replace(link, "{width}x{height}", "800x600")

  defp extract_image(_), do: nil

  defp extract_transaction_type(text) do
    text_lower = String.downcase(text)

    cond do
      # PRIORITY 1: Parse URL path structure (same info as breadcrumbs)
      # OLX URL structure: /nieruchomosci/{property_type}/{transaction_type}/...
      # Extract from URL path segments
      # Make trailing slash optional with /?
      String.match?(text_lower, ~r{/nieruchomosci/[^/]+/sprzedaz/?}) -> "sprzedaż"
      String.match?(text_lower, ~r{/nieruchomosci/[^/]+/wynajem/?}) -> "wynajem"

      # Also check for sprzedaz directly after nieruchomosci
      String.match?(text_lower, ~r{/nieruchomosci/sprzedaz/?}) -> "sprzedaż"

      # PRIORITY 2: Check URL patterns (direct keywords in path)
      # More flexible patterns without requiring slashes
      String.contains?(text_lower, "sprzedam") -> "sprzedaż"
      String.contains?(text_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "na-sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "-sprzedaz-") -> "sprzedaż"
      String.contains?(text_lower, "/sprzedaz/") -> "sprzedaż"

      # URL patterns for rent
      String.contains?(text_lower, "wynajem") -> "wynajem"
      String.contains?(text_lower, "do-wynajecia") -> "wynajem"
      String.contains?(text_lower, "wynajme") -> "wynajem"
      String.contains?(text_lower, "wynajęcia") -> "wynajem"
      String.contains?(text_lower, "-wynajem-") -> "wynajem"
      String.contains?(text_lower, "/wynajem/") -> "wynajem"
      String.contains?(text_lower, "wynajmę") -> "wynajem"
      String.contains?(text_lower, "wynajmie") -> "wynajem"

      # PRIORITY 3: Keywords in text (title, description)
      # Keywords for sale (sprzedaż) - check most specific first
      String.contains?(text_lower, "na sprzedaż") -> "sprzedaż"
      String.contains?(text_lower, "do kupienia") -> "sprzedaż"
      String.contains?(text_lower, "kupno") -> "sprzedaż"
      String.contains?(text_lower, "na własność") -> "sprzedaż"
      String.contains?(text_lower, "własnościowe") -> "sprzedaż"
      String.contains?(text_lower, "sprzedam ") -> "sprzedaż"
      String.contains?(text_lower, " sprzedam") -> "sprzedaż"
      String.match?(text_lower, ~r/\bsprzedam\b/) -> "sprzedaż"
      String.contains?(text_lower, "oferta sprzedaży") -> "sprzedaż"
      String.contains?(text_lower, "cena sprzedaży") -> "sprzedaż"
      String.contains?(text_lower, "do sprzedania") -> "sprzedaż"
      String.contains?(text_lower, "na sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "okazja") && not String.contains?(text_lower, "wynaj") -> "sprzedaż"

      # Keywords for rent (wynajem)
      String.contains?(text_lower, "na wynajem") -> "wynajem"
      String.contains?(text_lower, "do wynaj") -> "wynajem"
      String.contains?(text_lower, "wynajmowany") -> "wynajem"
      String.contains?(text_lower, "wynajmuję") -> "wynajem"
      String.contains?(text_lower, "wynajem ") -> "wynajem"
      String.contains?(text_lower, " wynajem") -> "wynajem"
      String.match?(text_lower, ~r/\bwynajem\b/) -> "wynajem"
      String.contains?(text_lower, "do najmu") -> "wynajem"
      String.contains?(text_lower, "wynajęcie") -> "wynajem"
      String.contains?(text_lower, "wynajęciu") -> "wynajem"

      # Room rental indicators (pokój = room, almost always rent)
      String.contains?(text_lower, "pokój") -> "wynajem"
      String.contains?(text_lower, "pokoj") -> "wynajem"
      String.contains?(text_lower, "pokoi") -> "wynajem"
      String.contains?(text_lower, "pokoik") -> "wynajem"
      String.contains?(text_lower, "pokoje") -> "wynajem"
      String.match?(text_lower, ~r/\d\s*os[\.\s]/) -> "wynajem"  # "2 os." = 2 osobowy
      String.match?(text_lower, ~r/\d-?osobow/) -> "wynajem"  # "1-osobowy", "2osobowy"
      String.contains?(text_lower, "osobowy") -> "wynajem"
      String.contains?(text_lower, "osobowa") -> "wynajem"
      String.contains?(text_lower, "współlokator") -> "wynajem"
      String.contains?(text_lower, "wolne miejsce") -> "wynajem"
      String.contains?(text_lower, "miejsce w") -> "wynajem"
      String.contains?(text_lower, "kawalerka") and not String.contains?(text_lower, "sprzeda") -> "wynajem"
      String.contains?(text_lower, "studio") and not String.contains?(text_lower, "sprzeda") -> "wynajem"

      # PRIORITY 4: Price indicators - monthly prices usually indicate rent
      # This is a fallback for ambiguous cases
      String.contains?(text_lower, "zł/mies") -> "wynajem"
      String.contains?(text_lower, "zł / mies") -> "wynajem"
      String.contains?(text_lower, "/mies") -> "wynajem"
      String.contains?(text_lower, "miesięcznie") -> "wynajem"
      String.contains?(text_lower, "mc.") -> "wynajem"
      String.contains?(text_lower, "/mc") -> "wynajem"
      String.contains?(text_lower, "pln/m") -> "wynajem"
      String.contains?(text_lower, "zł/m-c") -> "wynajem"
      String.contains?(text_lower, "+ opłaty") -> "wynajem"
      String.contains?(text_lower, "+opłaty") -> "wynajem"
      String.contains?(text_lower, "+ czynsz") -> "wynajem"
      String.contains?(text_lower, "+czynsz") -> "wynajem"

      # PRIORITY 5: Price-based heuristics
      # Very high prices (> 500,000) are likely sales, very low (< 5000) are likely rent
      # This is checked via the price value if available

      # PRIORITY 6: Fallback - if it's a property listing but no wynajem indicators,
      # assume it's for sale (most OLX listings are sales)
      String.contains?(text_lower, "/nieruchomosci/") and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "mies") and
        not String.contains?(text_lower, "najmu") ->
        "sprzedaż"

      # Even more aggressive fallback - if URL mentions property types commonly sold
      String.contains?(text_lower, "/mieszkania/") -> "sprzedaż"
      String.contains?(text_lower, "/domy/") -> "sprzedaż"
      String.contains?(text_lower, "/dzialki/") -> "sprzedaż"
      
      # PRIORITY 7: Generic OLX listing fallback
      # If it's an OLX property listing (oferta/ID.html) and no rent indicators, assume sale
      String.match?(text_lower, ~r/olx\.pl.*\/oferta\/.*\.html/) and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "/mies") and
        not String.contains?(text_lower, "mc") ->
        "sprzedaż"

      # PRIORITY 8: Last resort - if URL is from olx.pl and has nieruchomosci/mieszkania
      # but still no clear type, default to sale (90% of OLX are sales)
      String.contains?(text_lower, "olx.pl") and
        String.contains?(text_lower, "nieruchomosci") and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "najem") ->
        "sprzedaż"
      
      # PRIORITY 9: Ultra-aggressive fallback - ANY olx.pl URL without clear rent indicators
      # Statistics show ~85% of OLX properties are for sale
      String.contains?(text_lower, "olx.pl") and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "najem") and
        not String.contains?(text_lower, "/mies") and
        not String.contains?(text_lower, " mc") ->
        "sprzedaż"

      # FINAL FALLBACK: Default to sprzedaż for any unmatched transaction
      # Statistics show ~80% of all listings are for sale
      true -> 
        Logger.debug("OLX: Could not determine transaction_type, defaulting to sprzedaż")
        "sprzedaż"
    end
  end

  # Validate/correct transaction type based on price
  # If price is clearly in wrong range, override the text-based classification
  defp validate_transaction_type(transaction_type, price) when is_nil(price), do: transaction_type
  
  defp validate_transaction_type(transaction_type, price) do
    price_float = 
      case price do
        %Decimal{} -> Decimal.to_float(price)
        n when is_number(n) -> n
        _ -> nil
      end

    cond do
      is_nil(price_float) -> 
        transaction_type
      
      # If transaction_type is nil, determine from price alone
      is_nil(transaction_type) and price_float < 30_000 ->
        Logger.debug("Setting transaction_type from price: #{price_float} zł → rent")
        "wynajem"
        
      is_nil(transaction_type) and price_float >= 30_000 ->
        Logger.debug("Setting transaction_type from price: #{price_float} zł → sale")
        "sprzedaż"
        
      # Price < 30,000 zł - almost certainly rent, not sale
      # (Even a tiny studio apartment costs more than 30k to buy in Poland)
      price_float < 30_000 and transaction_type == "sprzedaż" ->
        Logger.info("Correcting transaction_type: #{price_float} zł marked as sale → rent")
        "wynajem"
        
      # Price > 100,000 zł - almost certainly sale, not rent  
      # (Monthly rent above 100k is extremely rare)
      price_float > 100_000 and transaction_type == "wynajem" ->
        Logger.info("Correcting transaction_type: #{price_float} zł marked as rent → sale")
        "sprzedaż"
        
      # Price in ambiguous range - trust the text-based classification
      true -> 
        transaction_type
    end
  end

  defp extract_property_type(text) do
    text_lower = String.downcase(text)

    cond do
      # PRIORITY 1: Parse URL path structure (same info as breadcrumbs)
      # OLX URL structure: /nieruchomosci/{property_type}/{transaction_type}/...
      # This extracts categories exactly like breadcrumbs would show
      String.match?(text_lower, ~r{/nieruchomosci/mieszkania/}) -> "mieszkanie"
      String.match?(text_lower, ~r{/nieruchomosci/domy/}) -> "dom"
      String.match?(text_lower, ~r{/nieruchomosci/biura-i-lokale/}) -> "lokal użytkowy"
      String.match?(text_lower, ~r{/nieruchomosci/stancje-pokoje/}) -> "pokój"
      String.match?(text_lower, ~r{/nieruchomosci/dzialki/}) -> "działka"
      String.match?(text_lower, ~r{/nieruchomosci/garaze/}) -> "garaż"
      String.match?(text_lower, ~r{/nieruchomosci/hale-magazyny/}) -> "lokal użytkowy"

      # PRIORITY 2: Check URL patterns (direct keywords)
      # Commercial properties
      String.contains?(text_lower, "/biura-i-lokale/") -> "lokal użytkowy"
      String.contains?(text_lower, "/biura-lokale/") -> "lokal użytkowy"
      String.contains?(text_lower, "/lokal-uzytkowy/") -> "lokal użytkowy"
      String.contains?(text_lower, "-biuro-") -> "lokal użytkowy"
      String.contains?(text_lower, "-lokal-") -> "lokal użytkowy"

      # Apartment URL patterns
      String.contains?(text_lower, "/mieszkania/") -> "mieszkanie"
      String.contains?(text_lower, "/mieszkanie/") -> "mieszkanie"
      String.contains?(text_lower, "-mieszkanie-") -> "mieszkanie"
      String.contains?(text_lower, "-m-") && String.contains?(text_lower, "pokoje") -> "mieszkanie"

      # House URL patterns
      String.contains?(text_lower, "/domy/") -> "dom"
      String.contains?(text_lower, "-dom-") -> "dom"
      String.contains?(text_lower, "/dom-") -> "dom"
      String.contains?(text_lower, "-domek-") -> "dom"

      # Plot URL patterns
      String.contains?(text_lower, "/dzialki/") -> "działka"
      String.contains?(text_lower, "/dzialka/") -> "działka"
      String.contains?(text_lower, "-dzialka-") -> "działka"

      # Garage URL patterns
      String.contains?(text_lower, "/garaze/") -> "garaż"
      String.contains?(text_lower, "/garaz/") -> "garaż"
      String.contains?(text_lower, "-garaz-") -> "garaż"
      String.contains?(text_lower, "-miejsce-postojowe-") -> "garaż"
      String.contains?(text_lower, "-miejsce-parkingowe-") -> "garaż"

      # Room URL patterns
      String.contains?(text_lower, "/stancje-pokoje/") -> "pokój"
      String.contains?(text_lower, "-pokoj-") -> "pokój"
      String.contains?(text_lower, "-stancja-") -> "pokój"

      # PRIORITY 3: Text-based detection (title, description)
      # Apartment (mieszkanie) - most common, many variations
      String.contains?(text_lower, "mieszkan") -> "mieszkanie"
      String.contains?(text_lower, "kawalerka") -> "mieszkanie"
      String.contains?(text_lower, "apartament") -> "mieszkanie"
      String.match?(text_lower, ~r/\d+[\s-]*pokoj/) -> "mieszkanie"
      String.match?(text_lower, ~r/\b[1-9]-?pokojowe\b/) -> "mieszkanie"
      String.contains?(text_lower, "m²") && String.contains?(text_lower, "pokój") -> "mieszkanie"
      String.contains?(text_lower, "m2") && String.contains?(text_lower, "pokój") -> "mieszkanie"
      String.contains?(text_lower, "mkw") && String.contains?(text_lower, "pokój") -> "mieszkanie"
      String.match?(text_lower, ~r/\b[2-6][\s-]?pok\.?\b/) -> "mieszkanie"
      String.contains?(text_lower, "studio") -> "mieszkanie"
      String.contains?(text_lower, "loft") -> "mieszkanie"
      String.contains?(text_lower, "penthouse") -> "mieszkanie"
      String.contains?(text_lower, "dwupokojowe") -> "mieszkanie"
      String.contains?(text_lower, "trzypokojowe") -> "mieszkanie"
      String.contains?(text_lower, "czteropokojowe") -> "mieszkanie"
      String.contains?(text_lower, "pięciopokojowe") -> "mieszkanie"
      String.match?(text_lower, ~r/\bm\d\b/) -> "mieszkanie"  # m2, m3, m4 etc
      String.contains?(text_lower, "spółdzielcze") -> "mieszkanie"
      String.contains?(text_lower, "własnościowe") -> "mieszkanie"

      # House (dom)
      String.contains?(text_lower, "dom ") -> "dom"
      String.contains?(text_lower, " dom") -> "dom"
      String.match?(text_lower, ~r/\bdom\b/) -> "dom"
      String.contains?(text_lower, "domek") -> "dom"
      String.contains?(text_lower, "willa") -> "dom"
      String.contains?(text_lower, "bliźniak") -> "dom"
      String.contains?(text_lower, "segment") -> "dom"
      String.contains?(text_lower, "szeregowiec") -> "dom"
      String.contains?(text_lower, "szeregowy") -> "dom"
      String.contains?(text_lower, "dworek") -> "dom"
      String.contains?(text_lower, "rezydencja") -> "dom"
      String.contains?(text_lower, "jednorodzinny") -> "dom"
      String.contains?(text_lower, "wolnostojący") -> "dom"
      String.contains?(text_lower, "parter + piętro") -> "dom"
      String.contains?(text_lower, "z ogrodem") && not String.contains?(text_lower, "mieszkan") -> "dom"
      String.contains?(text_lower, "siedlisko") -> "dom"
      String.contains?(text_lower, "gospodarstwo") -> "dom"
      String.contains?(text_lower, "zagroda") -> "dom"
      String.contains?(text_lower, "chałupa") -> "dom"
      String.contains?(text_lower, "leśniczówka") -> "dom"

      # Room (pokój) / Student accommodation (stancja)
      String.contains?(text_lower, "pokój ") -> "pokój"
      String.contains?(text_lower, " pokój") -> "pokój"
      String.match?(text_lower, ~r/\bpokój\b/) -> "pokój"
      String.contains?(text_lower, "pokoj ") -> "pokój"
      String.contains?(text_lower, " pokoj") -> "pokój"
      String.match?(text_lower, ~r/\bpokoj\b/) -> "pokój"
      String.contains?(text_lower, "stancja") -> "pokój"
      String.contains?(text_lower, "kwatera") -> "pokój"
      String.contains?(text_lower, "miejsce w pokoju") -> "pokój"
      String.contains?(text_lower, "współlokator") -> "pokój"
      String.contains?(text_lower, "dla studenta") -> "pokój"

      # Garage (garaż) / Parking
      String.contains?(text_lower, "garaż") -> "garaż"
      String.contains?(text_lower, "garaz") -> "garaż"
      String.contains?(text_lower, "miejsce postojowe") -> "garaż"
      String.contains?(text_lower, "miejsce parkingowe") -> "garaż"
      String.match?(text_lower, ~r/\bmiejsce\s+(w\s+)?parking/) -> "garaż"
      String.contains?(text_lower, "parking") && not String.contains?(text_lower, "mieszkan") -> "garaż"
      String.contains?(text_lower, "stanowisko garażowe") -> "garaż"
      String.contains?(text_lower, "hala garażowa") -> "garaż"
      String.contains?(text_lower, "komórka lokatorska") -> "garaż"
      String.contains?(text_lower, "piwnica") && not String.contains?(text_lower, "mieszkan") -> "garaż"

      # Plot/land (działka)
      String.contains?(text_lower, "działka") -> "działka"
      String.contains?(text_lower, "dzialka") -> "działka"
      String.match?(text_lower, ~r/\bgrunt\b/) -> "działka"
      String.match?(text_lower, ~r/\bteren\b/) -> "działka"
      String.contains?(text_lower, "ziemia") -> "działka"
      String.contains?(text_lower, "budowlana") -> "działka"
      String.contains?(text_lower, "rolna") -> "działka"
      String.contains?(text_lower, "siedliskowa") -> "działka"
      String.contains?(text_lower, "rekreacyjna") -> "działka"
      String.contains?(text_lower, "inwestycyjna") -> "działka"
      String.match?(text_lower, ~r/\b\d+\s*ar\b/) -> "działka"  # 10 ar, 20ar
      String.match?(text_lower, ~r/\b\d+\s*ha\b/) -> "działka"  # 1 ha, 2ha

      # Commercial space (lokal użytkowy) - check text keywords
      String.contains?(text_lower, "lokal użytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-biurowo") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-handlowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal handlowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal biurowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal usługowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal gastronomiczny") -> "lokal użytkowy"
      String.contains?(text_lower, "biura i lokale") -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bbiuro\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bbiura\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\blokal\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bsklep\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bmagazyn\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bhala\b/) -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia biurowa") -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia handlowa") -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia magazynowa") -> "lokal użytkowy"
      String.contains?(text_lower, "pow. usługowa") -> "lokal użytkowy"
      String.contains?(text_lower, "pow. biurowa") -> "lokal użytkowy"
      String.contains?(text_lower, "gabinet") -> "lokal użytkowy"
      String.contains?(text_lower, "kancelaria") -> "lokal użytkowy"
      
      # ULTRA-AGGRESSIVE FALLBACK: If we still don't know and it's OLX nieruchomosci
      # Default to mieszkanie (apartment) - most common property type (~70% of OLX)
      # This catches generic URLs/titles that have no clear indicators
      String.contains?(text_lower, "olx.pl") and
        (String.contains?(text_lower, "nieruchomosci") or String.contains?(text_lower, "/oferta/")) and
        not String.contains?(text_lower, "dom") and
        not String.contains?(text_lower, "dzialka") and
        not String.contains?(text_lower, "garaz") and
        not String.contains?(text_lower, "parking") ->
        "mieszkanie"

      # FINAL FALLBACK: Default to mieszkanie for any unmatched property
      # Statistics show ~70% of all listings are apartments
      true -> 
        Logger.debug("OLX: Could not determine property_type, defaulting to mieszkanie")
        "mieszkanie"
    end
  end
end
