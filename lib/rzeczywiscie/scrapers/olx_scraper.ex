defmodule Rzeczywiscie.Scrapers.OlxScraper do
  @moduledoc """
  Scraper for OLX.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate

  @base_url "https://www.olx.pl"
  @malopolskie_url "#{@base_url}/nieruchomosci/malopolskie/"

  @doc """
  Scrape properties from OLX for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 2000)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 2000)

    Logger.info("Starting OLX scrape for Malopolskie region, #{pages} page(s)")

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

    # Save to database
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
      description = extract_description(card)
      search_text = "#{title} #{description} #{full_url}"

      %{
        source: "olx",
        external_id: external_id || generate_id_from_url(url),
        title: String.trim(title),
        url: full_url,
        price: extract_price(card),
        currency: "PLN",
        area_sqm: extract_area(card),
        rooms: extract_rooms(card),
        transaction_type: extract_transaction_type(search_text),
        property_type: extract_property_type(search_text),
        city: extract_city(card),
        district: extract_district(card),
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

  defp extract_price(card) do
    # Try multiple selectors for price
    selectors = [
      "p[data-testid='ad-price']",
      "[data-testid='ad-price']",
      "p[class*='price']",
      "span[class*='price']"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text()

        case parse_price(text) do
          nil -> {:cont, nil}
          price -> {:halt, price}
        end
      end)

    result
  end

  defp parse_price(text) do
    # Use regex to extract price pattern first, before stripping chars
    # Matches patterns like: "1 200 zł", "1,200.50 PLN", "1200", "1 200,50"
    regex = ~r/(\d{1,3}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*(?:zł|PLN)?/i

    case Regex.run(regex, text) do
      [_, price_str] ->
        # Clean up: remove spaces and normalize decimal separator
        clean_price =
          price_str
          |> String.replace(~r/\s+/, "")
          |> String.replace(",", ".")

        case Decimal.parse(clean_price) do
          {decimal, _} ->
            # Validate: price should be reasonable (1 to 99,999,999 PLN)
            # Database constraint: precision 10, scale 2 = max 99,999,999.99
            if Decimal.compare(decimal, Decimal.new("1")) != :lt and
                 Decimal.compare(decimal, Decimal.new("99999999")) != :gt do
              decimal
            else
              Logger.warning("Price out of range: #{clean_price} PLN - ignoring")
              nil
            end

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_area(card) do
    # OLX typically shows area in specific format: "75 m²" or "75m²"
    # Get all text and look for m² pattern
    text = Floki.text(card)

    # Strategy: Find ALL area mentions and filter intelligently
    # 1. First try to find building area keywords (powierzchnia, pow., mieszkanie)
    # 2. Avoid plot area keywords (działka, grunt, teren)
    # 3. Validate size is reasonable for building (not plot)

    # Try to find building area with specific keywords
    building_area = extract_building_area(text)

    if building_area do
      building_area
    else
      # Fallback: find any area but validate it's reasonable for a building
      extract_any_area(text)
    end
  end

  defp extract_building_area(text) do
    # Keywords that indicate building/usable area (not plot)
    # "powierzchnia: 75 m²", "pow. użytkowa: 75m2", "mieszkanie 75 m²"
    building_keywords = [
      "powierzchnia użytkowa",
      "pow\\. użytkowa",
      "pow\\.użytkowa",
      "powierzchnia",
      "pow\\.",
      "mieszkanie",
      "dom",
      "lokal",
      "garaż"
    ]

    # Build regex that looks for keyword + number + m²
    # Example: "powierzchnia: 75 m²" or "pow. 75m2"
    regex_patterns =
      Enum.map(building_keywords, fn keyword ->
        ~r/#{keyword}[:\s]*(\d{1,4}(?:[,\.]\d{1,2})?)\s*m[\^²2]/iu
      end)

    # Try each pattern
    result = Enum.find_value(regex_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, number_str] -> parse_area_number(number_str, max_area: 1000)
        _ -> nil
      end
    end)

    result
  end

  defp extract_any_area(text) do
    # Negative keywords - skip if preceded by these (plot/land indicators)
    # This avoids matching "działka 5000 m²" when we want building area
    negative_lookbehind = "(?<!działka\\s)(?<!grunt\\s)(?<!teren\\s)(?<!ogród\\s)"

    # Match number + m² but exclude very large values (likely plot area)
    regex = ~r/#{negative_lookbehind}(?<![0-9-])(\d{1,3}(?:[,\.]\d{1,2})?)\s*m[\^²2]/iu

    case Regex.run(regex, text) do
      [_, number_str] ->
        # For fallback, use stricter validation (max 1000 m² for buildings)
        parse_area_number(number_str, max_area: 1000)
      _ ->
        nil
    end
  end

  defp parse_area_number(number_str, opts \\ []) do
    max_area = Keyword.get(opts, :max_area, 50000)

    # Clean up the number: remove spaces and replace comma with dot
    clean_number =
      number_str
      |> String.replace(~r/\s+/, "")  # Remove all spaces
      |> String.replace(",", ".")     # Replace comma with dot

    case Decimal.parse(clean_number) do
      {decimal, _} ->
        # Validate: area should be reasonable
        if Decimal.compare(decimal, Decimal.new("10")) != :lt and
             Decimal.compare(decimal, Decimal.new(max_area)) != :gt do
          decimal
        else
          Logger.debug("Area out of range: #{clean_number} m² (max: #{max_area}) - ignoring")
          nil
        end

      :error ->
        Logger.debug("Could not parse area: #{clean_number}")
        nil
    end
  end

  defp extract_rooms(card) do
    card
    |> Floki.text()
    |> extract_number_with_unit("pokoje")
    |> case do
      nil -> nil
      decimal -> Decimal.to_integer(decimal)
    end
  end

  defp extract_number_with_unit(text, unit) do
    regex = Regex.compile!("(\\d+[,\\.]?\\d*)\\s*#{Regex.escape(unit)}")

    case Regex.run(regex, text) do
      [_, number] ->
        number
        |> String.replace(",", ".")
        |> Decimal.parse()
        |> case do
          {decimal, _} -> decimal
          :error -> nil
        end

      _ ->
        nil
    end
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

        case String.split(text, ",") |> Enum.at(1) do
          nil ->
            {:cont, nil}

          district ->
            cleaned = String.trim(district) |> String.split("-") |> List.first() |> String.trim()

            case cleaned do
              "" -> {:cont, nil}
              d -> {:halt, d}
            end
        end
      end)

    result
  end

  defp extract_image(card) do
    card
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_description(card) do
    card
    |> Floki.find("p")
    |> Enum.map(&Floki.text/1)
    |> Enum.join(" ")
    |> String.slice(0, 500)
  end

  defp extract_transaction_type(text) do
    text_lower = String.downcase(text)

    cond do
      # PRIORITY 1: Check URL patterns first (most reliable)
      # OLX URL patterns: /sprzedam/, /sprzedaz/, /na-sprzedaz/
      String.contains?(text_lower, "/sprzedam/") -> "sprzedaż"
      String.contains?(text_lower, "/sprzedaz/") -> "sprzedaż"
      String.contains?(text_lower, "/na-sprzedaz/") -> "sprzedaż"
      String.contains?(text_lower, "-sprzedam-") -> "sprzedaż"
      String.contains?(text_lower, "-sprzedaz-") -> "sprzedaż"

      # URL patterns for rent
      String.contains?(text_lower, "/wynajem/") -> "wynajem"
      String.contains?(text_lower, "/do-wynajecia/") -> "wynajem"
      String.contains?(text_lower, "-wynajem-") -> "wynajem"

      # PRIORITY 2: Keywords in text (title, description)
      # Keywords for sale (sprzedaż) - check most specific first
      String.contains?(text_lower, "na sprzedaż") -> "sprzedaż"
      String.contains?(text_lower, "na-sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "sprzedam") -> "sprzedaż"
      String.contains?(text_lower, "sprzedaż") -> "sprzedaż"
      String.contains?(text_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "do kupienia") -> "sprzedaż"
      String.contains?(text_lower, "kupno") -> "sprzedaż"
      String.contains?(text_lower, "na własność") -> "sprzedaż"

      # Keywords for rent (wynajem)
      String.contains?(text_lower, "na wynajem") -> "wynajem"
      String.contains?(text_lower, "do wynajęcia") -> "wynajem"
      String.contains?(text_lower, "do wynajecia") -> "wynajem"
      String.contains?(text_lower, "wynajmę") -> "wynajem"
      String.contains?(text_lower, "wynajme") -> "wynajem"
      String.contains?(text_lower, "wynajem") -> "wynajem"
      String.contains?(text_lower, "na-wynajem") -> "wynajem"

      # PRIORITY 3: Price indicators - monthly prices usually indicate rent
      # This is a fallback for ambiguous cases
      String.contains?(text_lower, "zł/mies") -> "wynajem"
      String.contains?(text_lower, "zł / mies") -> "wynajem"
      String.contains?(text_lower, "miesięcznie") -> "wynajem"

      true -> nil
    end
  end

  defp extract_property_type(text) do
    text_lower = String.downcase(text)

    cond do
      # Apartment (mieszkanie) - most common, check first
      String.contains?(text_lower, "mieszkan") -> "mieszkanie"
      String.contains?(text_lower, "kawalerka") -> "mieszkanie"
      String.contains?(text_lower, "apartament") -> "mieszkanie"
      String.contains?(text_lower, "m²") && String.contains?(text_lower, "pokój") -> "mieszkanie"

      # House (dom)
      String.contains?(text_lower, "dom ") -> "dom"
      String.contains?(text_lower, " dom") -> "dom"
      String.contains?(text_lower, "-dom-") -> "dom"
      String.contains?(text_lower, "/dom-") -> "dom"
      String.match?(text_lower, ~r/\bdom\b/) -> "dom"
      String.contains?(text_lower, "willa") -> "dom"
      String.contains?(text_lower, "bliźniak") -> "dom"
      String.contains?(text_lower, "segment") -> "dom"

      # Room (pokój) / Student accommodation (stancja)
      String.contains?(text_lower, "pokój") -> "pokój"
      String.contains?(text_lower, "pokoj") -> "pokój"
      String.contains?(text_lower, "stancja") -> "pokój"

      # Garage (garaż)
      String.contains?(text_lower, "garaż") -> "garaż"
      String.contains?(text_lower, "garaz") -> "garaż"
      String.contains?(text_lower, "miejsce") && String.contains?(text_lower, "parking") -> "garaż"

      # Plot/land (działka)
      String.contains?(text_lower, "działka") -> "działka"
      String.contains?(text_lower, "dzialka") -> "działka"
      String.contains?(text_lower, "grunt") -> "działka"
      String.contains?(text_lower, "teren") -> "działka"

      # Commercial space (lokal użytkowy)
      String.contains?(text_lower, "lokal użytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-biurowo") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-handlowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal") -> "lokal użytkowy"
      String.contains?(text_lower, "biuro") -> "lokal użytkowy"
      String.contains?(text_lower, "sklep") -> "lokal użytkowy"
      String.contains?(text_lower, "magazyn") -> "lokal użytkowy"

      true -> nil
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
