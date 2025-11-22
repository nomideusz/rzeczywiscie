defmodule Rzeczywiscie.Scrapers.OtodomScraper do
  @moduledoc """
  Scraper for Otodom.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate

  @base_url "https://www.otodom.pl"
  # Search URL for Malopolskie region (both sale and rent)
  @malopolskie_sale_url "#{@base_url}/pl/wyniki/sprzedaz/mieszkanie,dom/malopolskie"
  @malopolskie_rent_url "#{@base_url}/pl/wyniki/wynajem/mieszkanie,dom/malopolskie"

  @doc """
  Scrape properties from Otodom for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape per transaction type (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 5000)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 5000)

    Logger.info("Starting Otodom scrape for Malopolskie region, #{pages} page(s) per transaction type")

    # Scrape both sale and rent listings
    sale_results = scrape_transaction_type(@malopolskie_sale_url, "sprzedaż", pages, delay)
    rent_results = scrape_transaction_type(@malopolskie_rent_url, "wynajem", pages, delay)

    all_results = sale_results ++ rent_results

    # Save to database
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

  defp scrape_transaction_type(base_url, transaction_type, pages, delay) do
    Logger.info("Scraping #{transaction_type} listings...")

    1..pages
    |> Enum.flat_map(fn page ->
      url = if page == 1, do: base_url, else: "#{base_url}?page=#{page}"

      case fetch_page(url) do
        {:ok, html} ->
          properties = parse_listings(html, transaction_type)
          Logger.info("Scraped #{transaction_type} page #{page}: found #{length(properties)} properties")

          # Add delay between requests to be respectful
          if page < pages, do: Process.sleep(delay)

          properties

        {:error, reason} ->
          Logger.error("Failed to fetch #{transaction_type} page #{page}: #{inspect(reason)}")
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

  defp parse_listings(html, transaction_type) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        Logger.info("HTML length: #{String.length(html)}")

        # Save HTML for debugging
        debug_filename = "/tmp/otodom_debug_#{:os.system_time(:second)}.html"
        File.write(debug_filename, html)
        Logger.info("Saved debug HTML to #{debug_filename}")

        # Check if we got blocked/captcha
        if String.contains?(html, ["captcha", "robot", "blocked", "Verifying you are human"]) do
          Logger.warning("Possible bot detection - page contains captcha/robot keywords")
        end

        # Extract JSON-LD structured data instead of HTML scraping
        properties = extract_from_json_ld(document, transaction_type)

        if length(properties) > 0 do
          Logger.info("Found #{length(properties)} properties from JSON-LD data")
          properties
        else
          Logger.warning("No properties found in JSON-LD, falling back to HTML scraping")
          # Fallback to HTML scraping if JSON-LD fails
          cards = try_find_listings(document)
          Logger.info("Found #{length(cards)} listing cards")

          cards
          |> Enum.map(&parse_listing(&1, transaction_type))
          |> Enum.reject(&is_nil/1)
        end

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  defp extract_from_json_ld(document, transaction_type) do
    # Find all JSON-LD script tags
    json_ld_scripts = Floki.find(document, "script[type='application/ld+json']")

    json_ld_scripts
    |> Enum.flat_map(fn {_tag, _attrs, [content]} ->
      case Jason.decode(content) do
        {:ok, json_data} -> extract_offers_from_json(json_data, transaction_type)
        {:error, _} -> []
      end
    end)
  end

  defp extract_offers_from_json(json_data, transaction_type) when is_map(json_data) do
    # Handle @graph structure (array of structured data objects)
    case json_data do
      %{"@graph" => graph} when is_list(graph) ->
        Enum.flat_map(graph, &extract_offers_from_json(&1, transaction_type))

      %{"@type" => "Product", "offers" => %{"offers" => offers}} when is_list(offers) ->
        Enum.map(offers, fn offer -> parse_json_offer(offer, transaction_type) end)

      %{"@type" => "Product", "offers" => %{"offers" => offers}} when is_map(offers) ->
        [parse_json_offer(offers, transaction_type)]

      _ ->
        []
    end
  end

  defp extract_offers_from_json(_, _), do: []

  defp parse_json_offer(offer, transaction_type) do
    item = offer["itemOffered"] || %{}
    address = item["address"] || %{}
    floor_size = item["floorSize"] || %{}

    # Extract ID from URL
    url = offer["url"] || ""
    external_id = extract_id_from_url(url)

    %{
      source: "otodom",
      external_id: external_id || generate_id_from_url(url),
      title: String.trim(offer["name"] || ""),
      url: url,
      price: parse_json_price(offer["price"]),
      currency: offer["priceCurrency"] || "PLN",
      area_sqm: parse_json_number(floor_size["value"]),
      rooms: parse_json_integer(item["numberOfRooms"]),
      transaction_type: transaction_type,
      property_type: nil,  # Not in JSON-LD, could extract from title
      city: address["addressLocality"],
      voivodeship: address["addressRegion"] || "małopolskie",
      image_url: offer["image"],
      raw_data: %{
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        from_json_ld: true
      }
    }
  end

  defp parse_json_price(price) when is_float(price) do
    Decimal.from_float(price)
  end
  defp parse_json_price(price) when is_integer(price) do
    Decimal.new(price)
  end
  defp parse_json_price(_), do: nil

  defp parse_json_number(num) when is_float(num), do: Decimal.from_float(num)
  defp parse_json_number(num) when is_integer(num), do: Decimal.new(num)
  defp parse_json_number(_), do: nil

  defp parse_json_integer(num) when is_integer(num), do: num
  defp parse_json_integer(num) when is_float(num), do: round(num)
  defp parse_json_integer(_), do: nil

  defp try_find_listings(document) do
    # Otodom-specific selectors - trying many variations
    selectors = [
      # Modern Otodom selectors
      "article[data-cy='listing-item']",
      "li[data-cy='listing-item']",
      "div[data-cy='listing-item']",
      "[data-cy='listing-item']",
      "div[data-cy='search.listing']",
      "article[data-cy='search.listing']",

      # Generic article/list selectors
      "article[class*='listing']",
      "li[class*='listing']",
      "div[class*='listing']",
      "article",

      # CSS class-based selectors (may change)
      "li.css-p74l73",
      "div.css-p74l73",
      "article.css-p74l73",

      # Link-based approach (find links to /pl/oferta/)
      "a[href*='/pl/oferta/']"
    ]

    result =
      Enum.reduce_while(selectors, [], fn selector, _acc ->
        cards = Floki.find(document, selector)

        if length(cards) > 0 do
          Logger.info("✓ Found #{length(cards)} elements using selector: #{selector}")
          {:halt, cards}
        else
          Logger.info("✗ Selector '#{selector}' found 0 elements")
          {:cont, []}
        end
      end)

    # If still nothing found, do extensive debugging
    if result == [] do
      Logger.warning("⚠️  No listings found with any selector!")
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
      |> Enum.take(30)

    Logger.warning("⚠️  No listings found! Available data-cy values (first 30): #{inspect(data_cy_values)}")

    # Check for links to property pages
    property_links = Floki.find(document, "a[href*='/oferta/']")
    Logger.info("Found #{length(property_links)} links containing '/oferta/'")

    # Check for common container elements
    articles = Floki.find(document, "article")
    Logger.info("Found #{length(articles)} article elements")

    list_items = Floki.find(document, "li")
    Logger.info("Found #{length(list_items)} li elements")

    # Check page title to verify we're on the right page
    title = Floki.find(document, "title") |> Floki.text()
    Logger.info("Page title: #{title}")

    # Look for any class names that might indicate listings
    divs_with_class = Floki.find(document, "div[class]") |> Enum.take(10)

    class_samples =
      divs_with_class
      |> Enum.map(fn {_tag, attrs, _children} ->
        Enum.find_value(attrs, fn
          {"class", value} -> value
          _ -> nil
        end)
      end)
      |> Enum.reject(&is_nil/1)

    Logger.info("Sample div classes (first 10): #{inspect(class_samples)}")
  end

  defp parse_listing(card, transaction_type) do
    with {:ok, url} <- extract_url(card),
         {:ok, title} <- extract_title(card) do
      external_id = extract_id_from_url(url)

      if is_nil(external_id) do
        Logger.warning("Could not extract ID from URL: #{url}")
      end

      full_url = ensure_absolute_url(url)

      # Extract property type from URL or title
      property_type = extract_property_type(full_url, title)

      %{
        source: "otodom",
        external_id: external_id || generate_id_from_url(url),
        title: String.trim(title),
        url: full_url,
        price: extract_price(card),
        currency: "PLN",
        area_sqm: extract_area(card),
        rooms: extract_rooms(card),
        transaction_type: transaction_type,
        property_type: property_type,
        city: extract_city(card),
        voivodeship: "małopolskie",
        image_url: extract_image(card),
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
    # Otodom URLs format: /pl/oferta/TITLE-ID12345678
    cond do
      String.contains?(url, "-ID") ->
        case Regex.run(~r/-ID([A-Za-z0-9]+)/, url) do
          [_, id] -> id
          _ -> nil
        end

      true ->
        # Try to extract last segment as ID
        url
        |> String.split("/")
        |> List.last()
        |> String.replace(".html", "")
        |> String.split("-")
        |> List.last()
    end
  end

  defp generate_id_from_url(url) do
    url
    |> String.split("/")
    |> List.last()
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 50)
    |> case do
      "" ->
        :crypto.hash(:md5, url)
        |> Base.encode16()
        |> String.slice(0, 16)

      id ->
        id
    end
  end

  defp extract_url(card) do
    selectors = [
      "a[data-cy='listing-item-link']",
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
    selectors = [
      "h2[data-cy='listing-item-title']",
      "h3",
      "h2",
      "p[class*='title']"
    ]

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
    selectors = [
      "span[data-cy='listing-item-price']",
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
    # Otodom typically shows area in specific format: "75 m²" or "75m²"
    # Get all text and look for m² pattern
    text = Floki.text(card)

    # Look for pattern: number + m² (with optional space/comma/dot)
    # Examples: "75 m²", "75.5 m²", "1 200 m²", "5000m2", "1558 m^2"
    # Use negative lookbehind to avoid matching years (2024, 2025, etc.)
    # Allow up to 5 digits to match land plots but reject via validation if too large
    regex = ~r/(?<![0-9-])(\d{1,5}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*m[\^²2]/iu

    case Regex.run(regex, text) do
      [_, number_str] ->
        # Clean up the number: remove spaces and replace comma with dot
        clean_number =
          number_str
          |> String.replace(~r/\s+/, "")  # Remove all spaces
          |> String.replace(",", ".")     # Replace comma with dot

        case Decimal.parse(clean_number) do
          {decimal, _} ->
            # Validate: area should be reasonable (10 to 50,000 m²)
            # Residential: 20-500 m², Commercial: up to 5,000 m², Land: up to 50,000 m² (5 hectares)
            if Decimal.compare(decimal, Decimal.new("10")) != :lt and
                 Decimal.compare(decimal, Decimal.new("50000")) != :gt do
              decimal
            else
              Logger.debug("Area out of range: #{clean_number} m² - ignoring")
              nil
            end

          :error ->
            Logger.debug("Could not parse area: #{clean_number}")
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_rooms(card) do
    text = Floki.text(card)

    extract_number_with_unit(text, "pokoje")
    |> case do
      nil ->
        # Try alternative patterns
        extract_number_with_unit(text, "pokoi") ||
          extract_number_with_unit(text, "pok.")

      decimal ->
        decimal
    end
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
    # Try to find location text
    selectors = [
      "p[data-cy='listing-item-location']",
      "span[class*='location']",
      "p[class*='location']"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text()

        case String.split(text, ",") |> List.first() |> String.trim() do
          "" -> {:cont, nil}
          city -> {:halt, city}
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

  defp extract_property_type(url, title) do
    url_lower = String.downcase(url <> " " <> title)

    cond do
      # Apartment (mieszkanie)
      String.contains?(url_lower, "mieszkanie") -> "mieszkanie"
      String.contains?(url_lower, "mieszkania") -> "mieszkanie"

      # House (dom)
      String.contains?(url_lower, "-dom-") -> "dom"
      String.contains?(url_lower, "/dom/") -> "dom"
      String.match?(url_lower, ~r/\bdom\b/) -> "dom"

      # Room (pokój)
      String.contains?(url_lower, "pokoj") -> "pokój"

      # Garage (garaż)
      String.contains?(url_lower, "garaz") -> "garaż"

      # Plot/land (działka)
      String.contains?(url_lower, "dzialka") -> "działka"

      # Commercial space (lokal użytkowy)
      String.contains?(url_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(url_lower, "lokal") -> "lokal użytkowy"

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
