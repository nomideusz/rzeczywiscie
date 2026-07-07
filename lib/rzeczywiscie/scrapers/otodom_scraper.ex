defmodule Rzeczywiscie.Scrapers.OtodomScraper do
  @moduledoc """
  Scraper for Otodom.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Scrapers.ExtractionHelpers

  @base_url "https://www.otodom.pl"
  # Otodom no longer supports comma-separated estates in search URLs
  # ("mieszkanie,dom" redirects to just "mieszkanie"), so each combo is
  # scraped separately
  @searches [
    {"sprzedaz", "mieszkanie"},
    {"sprzedaz", "dom"},
    {"wynajem", "mieszkanie"},
    {"wynajem", "dom"}
  ]

  @doc """
  Scrape properties from Otodom for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape per transaction type (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 5000)
    * `:enrich` - If true, auto-enriches properties missing data after scraping (default: false)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 5000)
    enrich = Keyword.get(opts, :enrich, false)
    progress = Keyword.get(opts, :progress, fn _msg -> :ok end)

    Logger.info("Starting Otodom scrape for Malopolskie region, #{pages} page(s) per search")

    search_count = length(@searches)

    all_results =
      @searches
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{transaction, estate}, i} ->
        progress.("search #{i}/#{search_count} (#{transaction}/#{estate})…")
        scrape_search(transaction, estate, pages, delay)
      end)
    
    # Save results
    progress.("saving #{length(all_results)} listings…")
    result = save_results(all_results)
    
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
    alias Rzeczywiscie.RealEstate
    
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
    
    # Get Otodom properties without streets, recently scraped first
    properties = Repo.all(
      from p in Property,
        where: p.active == true and p.source == "otodom" and (is_nil(p.street) or p.street == ""),
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
    
    # Get Otodom properties without descriptions, recently scraped first
    properties = Repo.all(
      from p in Property,
        where: p.active == true and p.source == "otodom" and (is_nil(p.description) or p.description == ""),
        order_by: [desc: p.inserted_at],
        limit: ^limit,
        select: %{id: p.id, url: p.url}
    )
    
    Logger.info("Found #{length(properties)} Otodom properties without descriptions")
    
    Enum.with_index(properties, 1)
    |> Enum.each(fn {prop, index} ->
      Logger.info("[#{index}/#{length(properties)}] Fetching description for ##{prop.id}")
      
      case ExtractionHelpers.fetch_otodom_description(prop.url) do
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
  defp save_results(all_results) do
    Logger.info("Starting database save for #{length(all_results)} properties...")

    saved =
      Enum.with_index(all_results, 1)
      |> Enum.map(fn {property_data, index} ->
        title_preview = String.slice(property_data.title, 0, 50)
        Logger.info("Saving #{index}/#{length(all_results)}: #{title_preview} (ID: #{property_data.external_id})")

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

    Logger.info("Otodom scrape completed: #{successful}/#{length(all_results)} saved, #{failed} failed")

    {:ok, %{total: length(all_results), saved: successful}}
  end

  # NOTE: Deep scrape code removed - use :enrich option instead for reliable data extraction
  # The PropertyRescraper does a better job of parsing individual detail pages

  defp scrape_search(transaction, estate, pages, delay) do
    base_url = "#{@base_url}/pl/wyniki/#{transaction}/#{estate}/malopolskie"

    1..pages
    |> Enum.flat_map(fn page ->
      url = if page == 1, do: base_url, else: "#{base_url}?page=#{page}"

      case fetch_page(url) do
        {:ok, html} ->
          properties = parse_listings(html)
          Logger.info("Scraped #{transaction}/#{estate} page #{page}: found #{length(properties)} properties")

          # Add delay between requests to be respectful
          if page < pages, do: Process.sleep(delay)

          properties

        {:error, reason} ->
          Logger.error("Failed to fetch #{transaction}/#{estate} page #{page}: #{inspect(reason)}")
          []
      end
    end)
  end

  defp fetch_page(url) do
    Logger.info("Fetching: #{url}")

    # More realistic browser headers to avoid bot detection
    headers = [
      {"user-agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"},
      {"accept",
       "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"},
      {"accept-language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"},
      {"accept-encoding", "gzip, deflate, br, zstd"},
      {"cache-control", "max-age=0"},
      {"sec-ch-ua", "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\""},
      {"sec-ch-ua-mobile", "?0"},
      {"sec-ch-ua-platform", "\"Windows\""},
      {"sec-fetch-dest", "document"},
      {"sec-fetch-mode", "navigate"},
      {"sec-fetch-site", "none"},
      {"sec-fetch-user", "?1"},
      {"upgrade-insecure-requests", "1"},
      {"referer", "https://www.google.com/"}
    ]

    case Req.get(url,
           headers: headers,
           max_redirects: 5,
           receive_timeout: 30_000,
           retry: :transient,
           retry_delay: &(&1 * 1000)
         ) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully fetched #{String.length(body)} bytes")
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HTTP #{status} from #{url}")
        Logger.info("Response preview: #{String.slice(body, 0, 200)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Request failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Search results are embedded in the Next.js __NEXT_DATA__ script tag;
  # the page's JSON-LD only carries WebPage/WebSite metadata now.
  defp parse_listings(html) do
    with {:ok, document} <- Floki.parse_document(html),
         [{_, _, [json]} | _] <- Floki.find(document, "script#__NEXT_DATA__"),
         {:ok, data} <- Jason.decode(json),
         items when is_list(items) <-
           get_in(data, ["props", "pageProps", "data", "searchAds", "items"]) do
      items |> Enum.map(&parse_item/1) |> Enum.reject(&is_nil/1)
    else
      other ->
        Logger.warning("Otodom: no searchAds items in __NEXT_DATA__: #{String.slice(inspect(other), 0, 200)}")
        []
    end
  end

  @estate_map %{
    "FLAT" => "mieszkanie",
    "HOUSE" => "dom",
    "TERRAIN" => "działka",
    "COMMERCIAL_PROPERTY" => "lokal użytkowy",
    "ROOM" => "pokój",
    "GARAGE" => "garaż"
  }

  @rooms_map %{"ONE" => 1, "TWO" => 2, "THREE" => 3, "FOUR" => 4, "FIVE" => 5,
               "SIX" => 6, "SEVEN" => 7, "EIGHT" => 8, "NINE" => 9, "TEN" => 10}

  @floor_map %{"CELLAR" => -1, "GROUND" => 0, "FIRST" => 1, "SECOND" => 2, "THIRD" => 3,
               "FOURTH" => 4, "FIFTH" => 5, "SIXTH" => 6, "SEVENTH" => 7, "EIGHTH" => 8,
               "NINTH" => 9, "TENTH" => 10}

  # Developer INVESTMENT entries are whole developments, not individual
  # listings (no url, no price) - skip them
  defp parse_item(%{"estate" => "INVESTMENT"}), do: nil

  defp parse_item(%{"id" => id, "slug" => slug, "title" => title} = item) do
    address = get_in(item, ["location", "address"]) || %{}

    %{
      source: "otodom",
      external_id: to_string(id),
      title: String.trim(title),
      url: "#{@base_url}/pl/oferta/#{slug}",
      price: parse_money(item["totalPrice"]),
      currency: get_in(item, ["totalPrice", "currency"]) || "PLN",
      area_sqm: parse_number(item["areaInSquareMeters"]),
      rooms: @rooms_map[item["roomsNumber"]],
      floor: @floor_map[item["floorNumber"]],
      transaction_type: if(item["transaction"] == "RENT", do: "wynajem", else: "sprzedaż"),
      property_type: @estate_map[item["estate"]],
      city: get_in(address, ["city", "name"]),
      district: extract_district(item),
      street: get_in(address, ["street", "name"]),
      voivodeship: "małopolskie",
      image_url: get_in(item, ["images", Access.at(0), "medium"]),
      description: item["shortDescription"],
      raw_data: %{
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  defp parse_item(item) do
    Logger.info("Skipping ad without id/slug/title: #{inspect(Map.keys(item))}")
    nil
  end

  defp parse_money(%{"value" => v}) when is_number(v), do: parse_number(v)
  defp parse_money(_), do: nil

  defp parse_number(v) when is_number(v), do: Decimal.new(to_string(v))
  defp parse_number(_), do: nil

  defp extract_district(item) do
    item
    |> get_in(["location", "reverseGeocoding", "locations"])
    |> List.wrap()
    |> Enum.find_value(fn
      %{"locationLevel" => "district", "name" => name} -> name
      _ -> nil
    end)
  end
end
