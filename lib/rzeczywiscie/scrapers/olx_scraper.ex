defmodule Rzeczywiscie.Scrapers.OlxScraper do
  @moduledoc """
  Scraper for OLX.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Scrapers.ExtractionHelpers

  @base_url "https://www.olx.pl"
  @malopolskie_url "#{@base_url}/nieruchomosci/malopolskie/"

  @doc """
  Scrape properties from OLX for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 2000)
    * `:deep` - If true, fetches each listing's detail page for accurate data (slower but more reliable)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 2000)
    deep = Keyword.get(opts, :deep, false)

    if deep do
      scrape_deep(pages, delay)
    else
      scrape_fast(pages, delay)
    end
  end

  # Fast scrape: Parse search result pages directly
  defp scrape_fast(pages, delay) do
    Logger.info("Starting OLX FAST scrape for Malopolskie region, #{pages} page(s)")

    results =
      1..pages
      |> Enum.flat_map(fn page ->
        url = if page == 1, do: @malopolskie_url, else: "#{@malopolskie_url}?page=#{page}"

        case fetch_page(url) do
          {:ok, html} ->
            properties = parse_listings(html)
            Logger.info("Scraped page #{page}: found #{length(properties)} properties")

            # Add delay between requests to be respectful
            if page < pages, do: Process.sleep(delay)

            properties

          {:error, reason} ->
            Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
            []
        end
      end)

    save_results(results, "fast")
  end

  # Deep scrape: Get URLs from search pages, then fetch each detail page (like rescraper)
  defp scrape_deep(pages, delay) do
    Logger.info("Starting OLX DEEP scrape for Malopolskie region, #{pages} page(s)")
    Logger.info("Deep mode: Will fetch each listing's detail page for accurate data")

    # Step 1: Get all listing URLs from search pages
    all_urls =
      1..pages
      |> Enum.flat_map(fn page ->
        url = if page == 1, do: @malopolskie_url, else: "#{@malopolskie_url}?page=#{page}"

        case fetch_page(url) do
          {:ok, html} ->
            urls = extract_listing_urls(html)
            Logger.info("Page #{page}: found #{length(urls)} listing URLs")
            
            if page < pages, do: Process.sleep(delay)
            urls

          {:error, reason} ->
            Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
            []
        end
      end)
      |> Enum.uniq()

    Logger.info("Found #{length(all_urls)} unique listing URLs")

    # Step 2: Fetch each detail page and extract full data
    results =
      all_urls
      |> Enum.with_index(1)
      |> Enum.map(fn {listing_url, index} ->
        Logger.info("[#{index}/#{length(all_urls)}] Deep fetching: #{String.slice(listing_url, 0, 60)}...")
        result = fetch_detail_page(listing_url)
        
        # Be respectful with delays
        if index < length(all_urls), do: Process.sleep(delay)
        
        result
      end)
      |> Enum.reject(&is_nil/1)

    save_results(results, "deep")
  end

  # Extract listing URLs from search results HTML
  defp extract_listing_urls(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Find all links to listing pages
        document
        |> Floki.find("a[href*='/d/oferta/']")
        |> Enum.map(fn {"a", attrs, _} ->
          Enum.find_value(attrs, fn {"href", href} -> href; _ -> nil end)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn href ->
          if String.starts_with?(href, "/"), do: "#{@base_url}#{href}", else: href
        end)
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  # Fetch and parse a detail page (like rescraper does)
  defp fetch_detail_page(url) do
    case fetch_page(url) do
      {:ok, html} ->
        parse_detail_page(html, url)

      {:error, reason} ->
        Logger.warning("Failed to fetch detail page: #{inspect(reason)}")
        nil
    end
  end

  # Parse a listing detail page (more reliable than search results)
  defp parse_detail_page(html, url) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        full_text = Floki.text(document)
        
        # Extract data from detail page
        title = extract_detail_title(document)
        price = extract_detail_price(document, full_text)
        area_sqm = ExtractionHelpers.extract_area_from_text(full_text)
        rooms = ExtractionHelpers.extract_rooms_from_text(full_text)
        district = ExtractionHelpers.extract_krakow_district(full_text)
        image_url = extract_detail_image(document)
        
        # Extract ID from URL
        external_id = extract_id_from_url(url)
        
        if external_id && title do
          # Determine transaction type from price
          transaction_type = if price do
            price_float = Decimal.to_float(price)
            if price_float < 15000, do: "rent", else: "sale"
          else
            "sale"
          end
          
          %{
            external_id: external_id,
            source: "olx",
            url: url,
            title: title,
            price: price,
            area_sqm: area_sqm,
            rooms: rooms,
            transaction_type: transaction_type,
            property_type: detect_property_type(title),
            district: district,
            voivodeship: "małopolskie",
            image_url: image_url,
            raw_data: %{scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(), method: "deep"}
          }
        else
          Logger.warning("Could not extract required data from URL: #{url}")
          nil
        end

      {:error, _} ->
        nil
    end
  end

  # HTML extraction for detail pages
  defp extract_detail_title(document) do
    selectors = ["h1", "h1[data-cy='ad_title']", "[data-testid='ad-title']"]
    Enum.find_value(selectors, fn sel ->
      text = document |> Floki.find(sel) |> Floki.text() |> String.trim()
      if text != "", do: text, else: nil
    end)
  end

  defp extract_detail_price(document, full_text) do
    selectors = [
      "h3[data-testid='ad-price-container']",
      "[data-testid='ad-price']",
      "h3[class*='price']",
      "div[class*='price'] h3"
    ]
    
    text = Enum.find_value(selectors, fn sel ->
      t = document |> Floki.find(sel) |> Floki.text() |> String.trim()
      if String.match?(t, ~r/\d/), do: t, else: nil
    end)
    
    if text do
      ExtractionHelpers.parse_price(text)
    else
      ExtractionHelpers.extract_price_from_full_text(full_text)
    end
  end

  defp extract_detail_image(document) do
    document
    |> Floki.find("img[src*='olx'], img[data-src*='olx']")
    |> Enum.find_value(fn
      {"img", attrs, _} -> Enum.find_value(attrs, fn {"src", src} -> src; {"data-src", src} -> src; _ -> nil end)
      _ -> nil
    end)
  end

  # Shared save function
  defp save_results(results, mode) do
    Logger.info("Starting database save for #{length(results)} properties (#{mode} mode)...")

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

  defp fetch_page(url) do
    Logger.info("Fetching: #{url}")

    case Req.get(url,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
             {"accept",
              "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
             {"accept-language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"},
             {"accept-encoding", "gzip, deflate, br"},
             {"cache-control", "max-age=0"},
             {"sec-fetch-dest", "document"},
             {"sec-fetch-mode", "navigate"},
             {"sec-fetch-site", "none"},
             {"upgrade-insecure-requests", "1"}
           ],
           max_redirects: 5,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully fetched #{String.length(body)} bytes")

        # Save HTML for debugging if it's a short response (might be error/captcha)
        if String.length(body) < 50_000 do
          Logger.warning("Response seems short (#{String.length(body)} bytes) - might be blocked")
          save_debug_html(body, url)
        end

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

  defp save_debug_html(html, url) do
    # Save to tmp for inspection
    filename = "/tmp/olx_debug_#{:os.system_time(:second)}.html"

    case File.write(filename, html) do
      :ok ->
        Logger.info("Saved debug HTML to #{filename} for URL: #{url}")
        Logger.info("Preview: #{String.slice(html, 0, 500)}")

      {:error, reason} ->
        Logger.warning("Could not save debug HTML: #{inspect(reason)}")
    end
  end

  defp parse_listings(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Debug: Check what we received
        Logger.info("HTML length: #{String.length(html)}")

        # Check if we got blocked/captcha
        if String.contains?(html, ["captcha", "robot", "blocked"]) do
          Logger.warning("Possible bot detection - page contains captcha/robot keywords")
        end

        # Try multiple selector strategies (OLX changes their HTML frequently)
        cards = try_find_listings(document)

        Logger.info("Found #{length(cards)} listing cards")

        cards
        |> Enum.map(&parse_listing/1)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  defp try_find_listings(document) do
    # Try different selectors in order of likelihood
    selectors = [
      "[data-cy='l-card']",           # Original selector
      "div[data-cy='l-card']",        # More specific
      "[data-testid='l-card']",       # Alternative attribute
      "div.css-1sw7q4x",              # CSS class (may change)
      "article",                       # Semantic HTML
      "[data-cy='listing-card']",     # Alternative naming
      "div[data-cy] a[href*='/d/']"   # Links to detail pages
    ]

    result =
      Enum.reduce_while(selectors, [], fn selector, _acc ->
        cards = Floki.find(document, selector)

        if length(cards) > 0 do
          Logger.info("✓ Found #{length(cards)} cards using selector: #{selector}")
          {:halt, cards}
        else
          Logger.info("✗ Selector '#{selector}' found 0 cards")
          {:cont, []}
        end
      end)

    # If still nothing found, do some debugging
    if result == [] do
      debug_document_structure(document)
    end

    result
  end

  defp debug_document_structure(document) do
    # Find all elements with data-cy attribute
    data_cy_elements = Floki.find(document, "[data-cy]")
    data_cy_values =
      data_cy_elements
      |> Enum.map(fn {_tag, attrs, _children} ->
        Enum.find_value(attrs, fn
          {"data-cy", value} -> value
          _ -> nil
        end)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(20)

    Logger.warning("⚠️  No listings found! Available data-cy values: #{inspect(data_cy_values)}")

    # Check for common containers
    containers = [
      "main",
      "#__next",
      "[role='main']",
      ".listing-grid",
      "[data-testid='listing-grid']"
    ]

    Enum.each(containers, fn selector ->
      found = Floki.find(document, selector)
      if length(found) > 0 do
        Logger.info("Found container: #{selector} (#{length(found)} elements)")
      end
    end)
  end

  defp parse_listing(card) do
    # Extract data from listing card - try multiple strategies
    with {:ok, url} <- extract_url(card),
         {:ok, title} <- extract_title(card) do
      # Use URL as external_id if no id attribute (more reliable)
      external_id = extract_id_from_url(url)

      if is_nil(external_id) do
        Logger.warning("Could not extract ID from URL: #{url}")
      end

      full_url = ensure_absolute_url(url)

      # Description is fetched manually from Admin page only
      description = nil

      search_text = "#{title} #{full_url}"

      # Try to extract price from card, if fails try title as fallback
      price = extract_price(card, title)

      # Extract initial transaction type from text
      initial_transaction_type = extract_transaction_type(search_text)
      # Validate/correct based on price
      validated_transaction_type = validate_transaction_type(initial_transaction_type, price)

      # Extract district first, then use it to infer city if needed
      district = extract_district(card)
      raw_city = extract_city(card)
      city = ExtractionHelpers.infer_city(raw_city, district)

      %{
        source: "olx",
        external_id: external_id || generate_id_from_url(url),
        title: String.trim(title),
        url: full_url,
        price: price,
        currency: "PLN",
        area_sqm: extract_area(card, title),
        rooms: extract_rooms(card, title),
        transaction_type: validated_transaction_type,
        property_type: extract_property_type(search_text),
        city: city,
        district: district,
        voivodeship: "małopolskie",
        image_url: extract_image(card),
        description: description,
        raw_data: %{
          scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    else
      {:error, reason} ->
        Logger.info("Skipping listing: #{inspect(reason)}")
        nil
    end
  end

  defp extract_id_from_url(url) do
    # OLX URLs have multiple formats, try them all:
    # Format 1: /d/ogloszenie/TITLE-ID12345678.html
    # Format 2: /oferta/TITLE-ID12345678
    # Format 3: Just use the last segment with ID prefix
    cond do
      String.contains?(url, "-ID") ->
        case Regex.run(~r/-ID([A-Za-z0-9]+)/, url) do
          [_, id] -> id
          _ -> nil
        end

      String.contains?(url, "/d/") ->
        # Extract the last part of the URL path
        url
        |> String.split("/")
        |> List.last()
        |> String.replace(".html", "")
        |> String.split("-")
        |> List.last()

      true ->
        nil
    end
  end

  defp generate_id_from_url(url) do
    # Generate a stable ID from the URL itself
    url
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 50)
    |> case do
      "" ->
        # Ultimate fallback: hash the entire URL
        :crypto.hash(:md5, url)
        |> Base.encode16()
        |> String.slice(0, 16)

      id ->
        id
    end
  end

  defp extract_url(card) do
    # Try multiple selectors for finding the URL
    selectors = [
      "a[data-cy='listing-ad-title']",
      "a[data-cy='ad-card']",
      "a[href*='/d/']",
      "a[href*='/oferta/']",
      "a"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        case Floki.find(card, selector) do
          [{_tag, attrs, _} | _] ->
            case List.keyfind(attrs, "href", 0) do
              {"href", url} when is_binary(url) and url != "" ->
                {:halt, {:ok, url}}

              _ ->
                {:cont, nil}
            end

          _ ->
            {:cont, nil}
        end
      end)

    result || {:error, :no_url}
  end

  defp extract_title(card) do
    # Try multiple selectors for title
    selectors = ["h6", "h4", "h3", "[data-cy='ad-card-title']", "a[data-cy='listing-ad-title']"]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        case Floki.find(card, selector) |> Floki.text() do
          "" -> {:cont, nil}
          title -> {:halt, {:ok, String.trim(title)}}
        end
      end)

    result || {:error, :no_title}
  end

  defp extract_price(card, title) do
    # Try multiple selectors for price
    selectors = [
      "p[data-testid='ad-price']",
      "[data-testid='ad-price']",
      "p[class*='price']",
      "span[class*='price']",
      "div[class*='price']",
      "[class*='Price']",  # Capital P variant
      "p",  # Generic paragraph - might contain price
      "span"  # Generic span - might contain price
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text()

        case parse_price(text) do
          nil -> {:cont, nil}
          price -> {:halt, price}
        end
      end)

    # Fallback 1: Try extracting from entire card text
    result = result || extract_price_from_card_text(card)
    
    # Fallback 2: Try extracting from title
    result = result || (title && parse_price(title))
    
    result
  end

  defp extract_price_from_card_text(card) do
    full_text = Floki.text(card)
    ExtractionHelpers.extract_price_from_full_text(full_text)
  end

  defp parse_price(text), do: ExtractionHelpers.parse_price(text)

  defp extract_area(card, title) do
    card_text = Floki.text(card)
    # Combine card text with title for better extraction
    full_text = if title, do: "#{title} #{card_text}", else: card_text
    ExtractionHelpers.extract_area_from_text(full_text)
  end

  defp extract_rooms(card, title) do
    card_text = Floki.text(card)
    
    # Combine card text with title for better extraction
    full_text = if title, do: "#{title} #{card_text}", else: card_text

    # Try multiple patterns for room count
    result = ExtractionHelpers.extract_number_with_unit(full_text, "pokoje")
    |> case do
      nil ->
        # Try alternative patterns
        ExtractionHelpers.extract_number_with_unit(full_text, "pokoi") ||
          ExtractionHelpers.extract_number_with_unit(full_text, "pok\\.") ||
          ExtractionHelpers.extract_number_with_unit(full_text, "pok") ||
          ExtractionHelpers.extract_rooms_from_text(full_text)

      decimal ->
        Decimal.to_integer(decimal)
    end
    |> case do
      nil -> nil
      num when is_integer(num) -> num
      decimal -> Decimal.to_integer(decimal)
    end
    
    result
  end


  defp extract_city(card) do
    # Try multiple selectors for location
    selectors = [
      "p[data-testid='location-date']",
      "[data-testid='location-date']",
      "p[class*='location']",
      "span[class*='location']"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text()

        case String.split(text, "-") |> List.first() |> String.trim() do
          "" -> {:cont, nil}
          city -> {:halt, city}
        end
      end)

    result
  end

  defp extract_district(card) do
    # Try multiple selectors for location
    selectors = [
      "p[data-testid='location-date']",
      "[data-testid='location-date']",
      "p[class*='location']",
      "span[class*='location']"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text()

        # Location format can be: "Kraków, Krowodrza - date" or "Kraków, Krowodrza, Azory - date"
        # Split by " - " first to remove date part
        location_part = text |> String.split(" - ") |> List.first() |> String.trim()
        
        # Split by comma and get district (second part)
        case String.split(location_part, ",") |> Enum.map(&String.trim/1) do
          [_city, district | _rest] when district != "" ->
            # Clean the district name (remove additional location details after dash)
            cleaned = district |> String.split("-") |> List.first() |> String.trim()
            
            case cleaned do
              "" -> {:cont, nil}
              d -> {:halt, normalize_district_name(d)}
            end
            
          _ ->
            {:cont, nil}
        end
      end)

    result
  end
  
  # Normalize district name to consistent format
  defp normalize_district_name(district) do
    # Map common variations to standard names
    district_map = %{
      "pradnik bialy" => "Prądnik Biały",
      "pradnik czerwony" => "Prądnik Czerwony",
      "stare miasto" => "Stare Miasto",
      "nowa huta" => "Nowa Huta",
      "podgorze duchackie" => "Podgórze Duchackie",
      "wzgorza krzeslawickie" => "Wzgórza Krzesławickie",
      "borek falecki" => "Borek Fałęcki"
    }
    
    normalized = String.downcase(district) |> String.trim()
    Map.get(district_map, normalized, district)
  end

  defp extract_image(card) do
    card
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end

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

  defp ensure_absolute_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      @base_url <> url
    end
  end
end
