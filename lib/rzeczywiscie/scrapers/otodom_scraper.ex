defmodule Rzeczywiscie.Scrapers.OtodomScraper do
  @moduledoc """
  Scraper for Otodom.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Scrapers.ExtractionHelpers

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
          # Count how many have full data
          properties_with_price = Enum.count(properties, fn p -> p.price != nil end)
          properties_with_area = Enum.count(properties, fn p -> p.area_sqm != nil end)
          
          Logger.info("JSON-LD extracted #{length(properties)} properties - #{properties_with_price} with price, #{properties_with_area} with area")
          
          # Keep properties that have at least price OR area
          valid_properties = Enum.filter(properties, fn prop ->
            prop.price != nil || prop.area_sqm != nil
          end)
          
          if length(valid_properties) > 0 do
            Logger.info("Using #{length(valid_properties)} properties from JSON-LD")
            valid_properties
          else
            Logger.warning("All JSON-LD properties missing price AND area, falling back to HTML")
            html_fallback_parse(document, transaction_type)
          end
        else
          Logger.warning("No properties found in JSON-LD, falling back to HTML scraping")
          html_fallback_parse(document, transaction_type)
        end

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  # HTML fallback parser
  defp html_fallback_parse(document, transaction_type) do
    cards = try_find_listings(document)
    Logger.info("Found #{length(cards)} listing cards")

    cards
    |> Enum.map(&parse_listing(&1, transaction_type))
    |> Enum.reject(&is_nil/1)
  end

  defp extract_from_json_ld(document, transaction_type) do
    # Find all JSON-LD script tags
    json_ld_scripts = Floki.find(document, "script[type='application/ld+json']")

    Logger.info("Found #{length(json_ld_scripts)} JSON-LD script tags")

    results =
      json_ld_scripts
      |> Enum.with_index()
      |> Enum.flat_map(fn {{_tag, _attrs, children}, index} ->
        # Handle both single content and multiple children
        content =
          case children do
            [single_content] when is_binary(single_content) -> single_content
            multiple -> Enum.join(multiple, "")
          end

        case Jason.decode(content) do
          {:ok, json_data} ->
            offers = extract_offers_from_json(json_data, transaction_type)
            Logger.info("JSON-LD script #{index + 1}: extracted #{length(offers)} offers")

            if length(offers) == 0 do
              # Log the structure for debugging
              json_type = get_json_type(json_data)
              Logger.debug("JSON-LD script #{index + 1}: type = #{inspect(json_type)}, no offers found")
            end

            offers

          {:error, error} ->
            Logger.warning("Failed to parse JSON-LD script #{index + 1}: #{inspect(error)}")
            Logger.debug("Content preview: #{String.slice(content, 0, 200)}")
            []
        end
      end)

    if length(results) == 0 and length(json_ld_scripts) > 0 do
      Logger.warning("Found #{length(json_ld_scripts)} JSON-LD scripts but extracted 0 properties")
    end

    results
  end

  defp get_json_type(%{"@type" => type}), do: type
  defp get_json_type(%{"@graph" => graph}) when is_list(graph), do: "@graph with #{length(graph)} items"
  defp get_json_type(data) when is_map(data), do: "map with keys: #{inspect(Map.keys(data))}"
  defp get_json_type(data), do: inspect(data)

  defp extract_offers_from_json(json_data, transaction_type) when is_map(json_data) do
    # Handle different JSON-LD structures that Otodom might use
    case json_data do
      # @graph structure (array of structured data objects)
      %{"@graph" => graph} when is_list(graph) ->
        Enum.flat_map(graph, &extract_offers_from_json(&1, transaction_type))

      # Product with nested offers
      %{"@type" => "Product", "offers" => %{"offers" => offers}} when is_list(offers) ->
        Enum.map(offers, fn offer -> parse_json_offer(offer, transaction_type) end)

      %{"@type" => "Product", "offers" => %{"offers" => offers}} when is_map(offers) ->
        [parse_json_offer(offers, transaction_type)]

      # Product with direct offers array
      %{"@type" => "Product", "offers" => offers} when is_list(offers) ->
        Enum.map(offers, fn offer -> parse_json_offer(offer, transaction_type) end)

      # Single Product with single offer
      %{"@type" => "Product", "offers" => offer} when is_map(offer) ->
        [parse_json_offer(offer, transaction_type)]

      # RealEstateListing type (alternative format)
      %{"@type" => "RealEstateListing"} = listing ->
        [parse_real_estate_listing(listing, transaction_type)]

      # ItemList with items
      %{"@type" => "ItemList", "itemListElement" => items} when is_list(items) ->
        Enum.flat_map(items, fn item ->
          case item do
            %{"item" => item_data} -> extract_offers_from_json(item_data, transaction_type)
            _ -> extract_offers_from_json(item, transaction_type)
          end
        end)

      # SearchResultsPage (Otodom might use this)
      %{"@type" => "SearchResultsPage", "mainEntity" => entity} ->
        extract_offers_from_json(entity, transaction_type)

      _ ->
        []
    end
  end

  defp extract_offers_from_json(_, _), do: []

  defp parse_real_estate_listing(listing, transaction_type) do
    # Parse RealEstateListing structured data format
    url = listing["url"] || ""
    title = String.trim(listing["name"] || listing["description"] || "")
    external_id = extract_id_from_url(url)

    address = listing["address"] || %{}
    
    # Try multiple price extraction strategies
    price = extract_price_from_offer(listing)

    # Validate transaction type based on price
    validated_transaction_type = validate_transaction_type_by_price(transaction_type, price)

    # Try to extract district from address or URL
    district = extract_district_from_address(address) || extract_district_from_url(url)

    # Extract city with fallbacks: JSON address -> URL -> title -> infer from district
    raw_city = address["addressLocality"] || extract_city_from_url(url) || extract_city_from_title(title)
    city = ExtractionHelpers.infer_city(raw_city, district)

    # Description is fetched manually from Admin page only
    description = nil

    %{
      source: "otodom",
      external_id: external_id || generate_id_from_url(url),
      title: title,
      url: ensure_absolute_url(url),
      price: price,
      currency: listing["priceCurrency"] || "PLN",
      area_sqm: extract_area_from_offer(listing),
      rooms: parse_json_integer(listing["numberOfRooms"]),
      transaction_type: validated_transaction_type,
      property_type: extract_property_type_from_text(title <> " " <> url),
      city: city,
      district: district,
      voivodeship: address["addressRegion"] || "małopolskie",
      image_url: get_first_image(listing["image"]),
      description: description,
      raw_data: %{
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        from_json_ld: true
      }
    }
  end

  defp get_first_image(images) when is_list(images), do: List.first(images)
  defp get_first_image(image) when is_binary(image), do: image
  defp get_first_image(_), do: nil

  defp parse_json_offer(offer, transaction_type) do
    item = offer["itemOffered"] || %{}
    address = item["address"] || %{}

    # Extract ID from URL
    url = offer["url"] || ""
    title = String.trim(offer["name"] || "")
    external_id = extract_id_from_url(url)
    
    # Try multiple price extraction strategies
    price = extract_price_from_offer(offer)

    # Validate transaction type based on price
    validated_transaction_type = validate_transaction_type_by_price(transaction_type, price)

    # Try to extract district from address or URL
    district = extract_district_from_address(address) || extract_district_from_url(url)

    # Extract city with fallbacks: JSON address -> URL -> title -> infer from district
    raw_city = address["addressLocality"] || extract_city_from_url(url) || extract_city_from_title(title)
    city = ExtractionHelpers.infer_city(raw_city, district)

    # Description is fetched manually from Admin page only
    description = nil

    %{
      source: "otodom",
      external_id: external_id || generate_id_from_url(url),
      title: title,
      url: ensure_absolute_url(url),
      price: price,
      currency: offer["priceCurrency"] || "PLN",
      area_sqm: extract_area_from_offer(offer),
      rooms: parse_json_integer(item["numberOfRooms"]),
      transaction_type: validated_transaction_type,
      property_type: extract_property_type_from_text(title <> " " <> url),
      city: city,
      district: district,
      voivodeship: address["addressRegion"] || "małopolskie",
      image_url: offer["image"],
      description: description,
      raw_data: %{
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        from_json_ld: true
      }
    }
  end

  # Extract price from JSON-LD offer with fallbacks for different structures
  defp extract_price_from_offer(offer) when is_map(offer) do
    # Try multiple locations where price might be stored
    price_value = 
      offer["price"] || 
      get_in(offer, ["priceSpecification", "price"]) ||
      get_in(offer, ["priceSpecification", "priceValue"]) ||
      get_in(offer, ["offers", "price"]) ||
      get_in(offer, ["itemOffered", "price"]) ||
      get_in(offer, ["itemOffered", "offers", "price"])
    
    price = if price_value do
      parse_json_price(price_value)
    else
      # Last resort: look in item offered for any price-like field
      item = offer["itemOffered"] || %{}
      parse_json_price(item["price"])
    end
    
    # Debug logging when price extraction fails
    if is_nil(price) do
      offer_type = offer["@type"]
      available_keys = Map.keys(offer) |> Enum.take(10)
      Logger.debug("Failed to extract price from offer type=#{inspect(offer_type)}, keys=#{inspect(available_keys)}")
    end
    
    price
  end
  defp extract_price_from_offer(_), do: nil

  # Extract area from JSON-LD offer with fallbacks for different structures
  defp extract_area_from_offer(offer) when is_map(offer) do
    item = offer["itemOffered"] || %{}
    
    # Try multiple locations where area/floorSize might be stored
    # Note: floorSize can be either a direct number OR a map like {"value": 50, "unitCode": "MTK"}
    floor_size_raw = 
      item["floorSize"] ||
      item["size"] ||
      offer["floorSize"] ||
      offer["size"]
    
    # Extract the actual number value
    floor_size_value = extract_floor_size_value(floor_size_raw)
    
    area = parse_json_number(floor_size_value)
    
    # Debug logging when area extraction fails
    if is_nil(area) do
      offer_type = offer["@type"]
      item_type = item["@type"]
      Logger.info("Failed to extract area - offer type=#{inspect(offer_type)}, item type=#{inspect(item_type)}, floorSize raw=#{inspect(floor_size_raw)}")
    end
    
    area
  end
  defp extract_area_from_offer(_), do: nil

  # Extract the numeric value from floorSize which can be in different formats
  defp extract_floor_size_value(nil), do: nil
  defp extract_floor_size_value(num) when is_number(num), do: num
  defp extract_floor_size_value(%{"value" => value}) when is_number(value), do: value
  defp extract_floor_size_value(%{"value" => value}) when is_binary(value) do
    # Parse string value like "50" or "50.5"
    case Float.parse(value) do
      {num, _} -> num
      :error -> nil
    end
  end
  # Handle range format (minValue/maxValue) - use minValue as conservative estimate
  defp extract_floor_size_value(%{"minValue" => min_val, "maxValue" => _max_val}) when is_number(min_val) do
    min_val
  end
  defp extract_floor_size_value(%{"minValue" => min_val}) when is_number(min_val), do: min_val
  defp extract_floor_size_value(%{"maxValue" => max_val}) when is_number(max_val), do: max_val
  defp extract_floor_size_value(str) when is_binary(str) do
    # Parse string like "50 m²" or "50"
    case Float.parse(String.trim(str)) do
      {num, _} -> num
      :error -> nil
    end
  end
  defp extract_floor_size_value(map) when is_map(map) do
    # Try common keys for the value
    map["value"] || map["amount"] || map["size"]
    |> extract_floor_size_value()
  end
  defp extract_floor_size_value(_), do: nil

  defp parse_json_price(price) when is_float(price) do
    Decimal.from_float(price)
  end
  defp parse_json_price(price) when is_integer(price) do
    Decimal.new(price)
  end
  defp parse_json_price(price) when is_binary(price) do
    # Sometimes price comes as a string, try to parse it
    clean_price = 
      price
      |> String.replace(~r/\s+/, "")
      |> String.replace(",", ".")
      |> String.replace(~r/[^\d.]/, "")
    
    case Decimal.parse(clean_price) do
      {decimal, _} -> decimal
      :error -> nil
    end
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

      # CSS class-based selectors (may change)
      "li.css-p74l73",
      "div.css-p74l73",
      "article.css-p74l73"
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

    # If still nothing found, try link-based approach but filter for valid listings
    result = if result == [] do
      Logger.warning("⚠️  No listings found with standard selectors, trying link-based approach")
      find_listings_by_links(document)
    else
      result
    end

    # If still nothing, do extensive debugging
    if result == [] do
      Logger.warning("⚠️  No listings found with any selector!")
      debug_document_structure(document)
    end

    result
  end

  defp find_listings_by_links(document) do
    # Find all links that point to property listings
    property_links = Floki.find(document, "a[href*='/pl/oferta/']")
    Logger.info("Found #{length(property_links)} links to /pl/oferta/")

    # Group links by their parent article/li/div to find listing containers
    # Each listing typically has a link, so we can work backwards from links to containers
    property_links
    |> Enum.map(fn link ->
      # Try to find the parent container (article, li, or div)
      find_parent_container(link, document)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> tap(fn containers ->
      Logger.info("Extracted #{length(containers)} unique listing containers from links")
    end)
  end

  defp find_parent_container({_tag, _attrs, _children} = element, _document) do
    # Check if this element itself is a container (article, li, div with substantial content)
    if is_listing_container?(element) do
      element
    else
      # For links, we need a different strategy - just return the link element
      # and we'll extract data from it differently
      element
    end
  end

  defp is_listing_container?({tag, _attrs, children}) when tag in ["article", "li", "div"] do
    # A valid listing container should have some content (not empty)
    # and ideally have some structure (nested elements)
    has_content = children != [] and children != [""]

    # Check if it has nested elements (links, images, text)
    has_structure =
      Enum.any?(children, fn
        {_tag, _attrs, _children} -> true
        _ -> false
      end)

    has_content and has_structure
  end

  defp is_listing_container?(_), do: false

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

      price = extract_price(card, title)

      # Validate transaction_type or extract from URL/title if needed
      initial_transaction_type = if transaction_type in ["sprzedaż", "wynajem"] do
        transaction_type
      else
        # Fallback: try to extract from URL/title
        extract_transaction_type_from_text(full_url <> " " <> title) || transaction_type
      end

      # Validate based on price (catches misclassified listings)
      validated_transaction_type = validate_transaction_type_by_price(initial_transaction_type, price)

      # Extract district from URL or card
      district = extract_district_from_url(full_url) || extract_district_from_card(card)

      # Extract city - try card first, then URL, then infer from district
      raw_city = extract_city(card) || extract_city_from_url(full_url) || extract_city_from_title(title)
      city = ExtractionHelpers.infer_city(raw_city, district)

      # Description is fetched manually from Admin page only
      description = nil

      %{
        source: "otodom",
        external_id: external_id || generate_id_from_url(url),
        title: String.trim(title),
        url: full_url,
        price: price,
        currency: "PLN",
        area_sqm: extract_area(card, title),
        rooms: extract_rooms(card, title),
        transaction_type: validated_transaction_type,
        property_type: property_type,
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
      "h3[data-cy='listing-item-title']",
      "p[data-cy='listing-item-title']",
      "span[data-cy='listing-item-title']",
      "h3",
      "h2",
      "h4",
      "p[class*='title']",
      "span[class*='title']",
      "div[class*='title']"
    ]

    result =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        text = Floki.find(card, selector) |> Floki.text() |> String.trim()
        if text != "" and String.length(text) > 3 do
          {:halt, {:ok, text}}
        else
          {:cont, nil}
        end
      end)

    # Fallback 1: Check if this is a link element
    result = result || case extract_title_from_link(card) do
      nil -> nil
      title -> {:ok, title}
    end
    
    # Fallback 2: Try container-based title extraction
    result = result || case extract_title_from_container(card) do
      nil -> nil
      title -> {:ok, title}
    end
    
    # Fallback 3: Try to build title from URL
    result = result || extract_title_from_url(card)
    
    result || {:error, :no_title}
  end
  
  # Extract a title from the URL path (last resort)
  defp extract_title_from_url(card) do
    case extract_url(card) do
      {:ok, url} ->
        # Parse URL like /pl/oferta/mieszkanie-3-pokoje-krakow-debniki-ID123
        case Regex.run(~r{/pl/oferta/([^/]+)}, url) do
          [_, slug] ->
            # Convert slug to readable title
            title = slug
                    |> String.replace(~r/-ID\d+.*$/, "")  # Remove ID suffix
                    |> String.replace("-", " ")
                    |> String.split()
                    |> Enum.map(&String.capitalize/1)
                    |> Enum.join(" ")
            
            if String.length(title) > 5 do
              {:ok, title}
            else
              nil
            end
          _ -> nil
        end
      _ -> nil
    end
  end

  defp extract_title_from_link({tag, attrs, children}) when tag == "a" do
    # Try to get title from aria-label or title attribute
    title_from_attr =
      Enum.find_value(attrs, fn
        {"aria-label", value} when value != "" -> value
        {"title", value} when value != "" -> value
        _ -> nil
      end)

    if title_from_attr do
      String.trim(title_from_attr)
    else
      # Extract text from children - but clean it up
      text = Floki.text({tag, attrs, children}) 
             |> String.trim()
             |> String.replace(~r/\s+/, " ")  # Normalize whitespace
      
      # Only return if it looks like a title (has some content, not too short)
      if text != "" and String.length(text) > 5 do
        # Take first line / reasonable portion as title
        text
        |> String.split("\n")
        |> List.first()
        |> String.slice(0, 200)
        |> String.trim()
      else
        nil
      end
    end
  end

  defp extract_title_from_link(_), do: nil
  
  # Improved approach: find any element with substantial text that could be a title
  defp extract_title_from_container(container) do
    # Try various selectors for title within the container
    title_selectors = [
      "h2", "h3", "h1",  # Standard headings
      "p[data-cy*='title']",
      "span[data-cy*='title']",
      "[class*='title']",
      "[class*='Title']",
      "p:first-of-type",  # First paragraph might be title
      "span:first-of-type"
    ]
    
    Enum.find_value(title_selectors, fn selector ->
      case Floki.find(container, selector) do
        [] -> nil
        elements ->
          text = elements |> Floki.text() |> String.trim() |> String.replace(~r/\s+/, " ")
          if text != "" and String.length(text) > 5 and String.length(text) < 300 do
            text
          else
            nil
          end
      end
    end)
  end

  defp extract_price(card, title) do
    selectors = [
      "span[data-cy='listing-item-price']",
      "p[class*='price']",
      "span[class*='price']",
      "[class*='Price']"
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

  # Extract district from JSON-LD address data
  defp extract_district_from_address(nil), do: nil
  defp extract_district_from_address(address) when is_map(address) do
    # Try various address fields that might contain district
    district = address["addressSubLocality"] || 
               address["neighborhood"] ||
               address["subLocality"]
    
    case district do
      nil -> nil
      "" -> nil
      d when is_binary(d) -> String.trim(d)
      _ -> nil
    end
  end
  defp extract_district_from_address(_), do: nil

  # Extract district from Otodom URL
  # URL format: /pl/oferta/mieszkanie-sprzedaz-krakow-krowodrza-azory-ul-stefana-batorego-ID...
  # or: /pl/oferta/mieszkanie-sprzedaz-krakow-podgorze-ID...
  defp extract_district_from_url(nil), do: nil
  defp extract_district_from_url(url) when is_binary(url) do
    # Krakow districts - ordered by specificity (longer names first)
    krakow_districts = [
      "wzgorza-krzeslawickie", "podgorze-duchackie", "pradnik-czerwony", "pradnik-bialy",
      "stare-miasto", "nowa-huta", "lagiewniki", "borek-falecki",
      "krowodrza", "zwierzyniec", "bronowice", "debniki", "podgorze", 
      "grzegorzki", "czyzyny", "mistrzejowice", "bienczyce", "swoszowice",
      "biezanow", "prokocim"
    ]
    
    url_lower = String.downcase(url)
    
    # Try to find a district in the URL
    district = Enum.find(krakow_districts, fn d ->
      String.contains?(url_lower, d)
    end)
    
    case district do
      nil -> nil
      d -> 
        # Convert URL format to display format (e.g., "pradnik-bialy" -> "Prądnik Biały")
        format_district_name(d)
    end
  end
  defp extract_district_from_url(_), do: nil

  # Extract district from listing card (HTML)
  defp extract_district_from_card(card) do
    # Try to find location text and extract district
    selectors = [
      "p[data-cy='listing-item-location']",
      "span[class*='location']",
      "p[class*='location']"
    ]

    Enum.reduce_while(selectors, nil, fn selector, _acc ->
      text = Floki.find(card, selector) |> Floki.text()
      
      # Location format: "Kraków, Krowodrza" or "Kraków, Prądnik Biały, ul.Example"
      parts = String.split(text, ",") |> Enum.map(&String.trim/1)
      
      case parts do
        [_city, district | _rest] when district != "" -> 
          {:halt, district}
        _ -> 
          {:cont, nil}
      end
    end)
  end
  
  # Extract city from URL
  # URL format: /pl/oferta/mieszkanie-sprzedaz-krakow-krowodrza-...
  defp extract_city_from_url(nil), do: nil
  defp extract_city_from_url(url) when is_binary(url) do
    url_lower = String.downcase(url)
    
    cond do
      String.contains?(url_lower, "-krakow-") or String.contains?(url_lower, "/krakow/") ->
        "Kraków"
      String.contains?(url_lower, "-wieliczka-") or String.contains?(url_lower, "/wieliczka/") ->
        "Wieliczka"
      String.contains?(url_lower, "-niepolomice-") or String.contains?(url_lower, "/niepolomice/") ->
        "Niepołomice"
      String.contains?(url_lower, "-skawina-") or String.contains?(url_lower, "/skawina/") ->
        "Skawina"
      String.contains?(url_lower, "-tarnow-") or String.contains?(url_lower, "/tarnow/") ->
        "Tarnów"
      String.contains?(url_lower, "-nowy-sacz-") or String.contains?(url_lower, "/nowy-sacz/") ->
        "Nowy Sącz"
      true ->
        nil
    end
  end
  defp extract_city_from_url(_), do: nil
  
  # Extract city from title
  defp extract_city_from_title(nil), do: nil
  defp extract_city_from_title(title) when is_binary(title) do
    title_lower = String.downcase(title)
    
    cond do
      String.contains?(title_lower, "kraków") or String.contains?(title_lower, "krakow") ->
        "Kraków"
      String.contains?(title_lower, "wieliczka") ->
        "Wieliczka"
      String.contains?(title_lower, "niepołomice") or String.contains?(title_lower, "niepolomice") ->
        "Niepołomice"
      String.contains?(title_lower, "skawina") ->
        "Skawina"
      String.contains?(title_lower, "tarnów") or String.contains?(title_lower, "tarnow") ->
        "Tarnów"
      String.contains?(title_lower, "nowy sącz") or String.contains?(title_lower, "nowy sacz") ->
        "Nowy Sącz"
      true ->
        nil
    end
  end
  defp extract_city_from_title(_), do: nil

  # Convert URL-formatted district name to display format
  defp format_district_name(url_district) do
    district_map = %{
      "wzgorza-krzeslawickie" => "Wzgórza Krzesławickie",
      "podgorze-duchackie" => "Podgórze Duchackie",
      "pradnik-czerwony" => "Prądnik Czerwony",
      "pradnik-bialy" => "Prądnik Biały",
      "stare-miasto" => "Stare Miasto",
      "nowa-huta" => "Nowa Huta",
      "lagiewniki" => "Łagiewniki",
      "borek-falecki" => "Borek Fałęcki",
      "krowodrza" => "Krowodrza",
      "zwierzyniec" => "Zwierzyniec",
      "bronowice" => "Bronowice",
      "debniki" => "Dębniki",
      "podgorze" => "Podgórze",
      "grzegorzki" => "Grzegórzki",
      "czyzyny" => "Czyżyny",
      "mistrzejowice" => "Mistrzejowice",
      "bienczyce" => "Bieńczyce",
      "swoszowice" => "Swoszowice",
      "biezanow" => "Bieżanów",
      "prokocim" => "Prokocim"
    }
    
    Map.get(district_map, url_district, String.capitalize(url_district))
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
      # PRIORITY 1: URL patterns (most reliable)
      # Commercial properties
      String.contains?(url_lower, "/lokal-uzytkowy/") -> "lokal użytkowy"
      String.contains?(url_lower, "/lokal/") -> "lokal użytkowy"
      String.contains?(url_lower, "/biuro/") -> "lokal użytkowy"
      String.contains?(url_lower, "/biura/") -> "lokal użytkowy"
      String.contains?(url_lower, "-lokal-") -> "lokal użytkowy"
      String.contains?(url_lower, "-biuro-") -> "lokal użytkowy"

      # Apartment (mieszkanie)
      String.contains?(url_lower, "/mieszkanie/") -> "mieszkanie"
      String.contains?(url_lower, "/mieszkania/") -> "mieszkanie"
      String.contains?(url_lower, "-mieszkanie-") -> "mieszkanie"
      String.contains?(url_lower, ",mieszkanie,") -> "mieszkanie"

      # House (dom)
      String.contains?(url_lower, "/dom/") -> "dom"
      String.contains?(url_lower, "/domy/") -> "dom"
      String.contains?(url_lower, "-dom-") -> "dom"
      String.contains?(url_lower, ",dom,") -> "dom"

      # Plot/land (działka)
      String.contains?(url_lower, "/dzialka/") -> "działka"
      String.contains?(url_lower, "/dzialki/") -> "działka"
      String.contains?(url_lower, "-dzialka-") -> "działka"

      # Garage (garaż)
      String.contains?(url_lower, "/garaz/") -> "garaż"
      String.contains?(url_lower, "/garaze/") -> "garaż"
      String.contains?(url_lower, "-garaz-") -> "garaż"
      String.contains?(url_lower, "-miejsce-parkingowe-") -> "garaż"

      # Room (pokój)
      String.contains?(url_lower, "/pokoj/") -> "pokój"
      String.contains?(url_lower, "-pokoj-") -> "pokój"

      # PRIORITY 2: Title/text keywords (more comprehensive)
      # Apartment patterns
      String.contains?(url_lower, "mieszkan") -> "mieszkanie"
      String.contains?(url_lower, "kawalerka") -> "mieszkanie"
      String.contains?(url_lower, "apartament") -> "mieszkanie"
      String.match?(url_lower, ~r/\d+[\s-]*pokoj/) -> "mieszkanie"
      String.match?(url_lower, ~r/\b[1-9]-?pokojowe\b/) -> "mieszkanie"
      String.contains?(url_lower, "dwupokojowe") -> "mieszkanie"
      String.contains?(url_lower, "trzypokojowe") -> "mieszkanie"
      String.match?(url_lower, ~r/\b[2-6][\s-]?pok\.?\b/) -> "mieszkanie"
      String.contains?(url_lower, "studio") -> "mieszkanie"
      String.contains?(url_lower, "loft") -> "mieszkanie"
      String.contains?(url_lower, "penthouse") -> "mieszkanie"

      # House patterns
      String.match?(url_lower, ~r/\bdom\b/) -> "dom"
      String.contains?(url_lower, "domek") -> "dom"
      String.contains?(url_lower, "willa") -> "dom"
      String.contains?(url_lower, "bliźniak") -> "dom"
      String.contains?(url_lower, "segment") -> "dom"
      String.contains?(url_lower, "szeregowiec") -> "dom"
      String.contains?(url_lower, "jednorodzinny") -> "dom"

      # Room patterns
      String.match?(url_lower, ~r/\bpokoj\b/) -> "pokój"
      String.match?(url_lower, ~r/\bpokój\b/) -> "pokój"
      String.contains?(url_lower, "stancja") -> "pokój"

      # Garage patterns
      String.contains?(url_lower, "garaż") -> "garaż"
      String.contains?(url_lower, "garaz") -> "garaż"
      String.contains?(url_lower, "miejsce postojowe") -> "garaż"
      String.contains?(url_lower, "miejsce parkingowe") -> "garaż"

      # Plot patterns
      String.contains?(url_lower, "działka") -> "działka"
      String.contains?(url_lower, "dzialka") -> "działka"
      String.match?(url_lower, ~r/\bgrunt\b/) -> "działka"
      String.contains?(url_lower, "budowlana") -> "działka"

      # Commercial patterns
      String.match?(url_lower, ~r/\blokal\b/) -> "lokal użytkowy"
      String.match?(url_lower, ~r/\bbiuro\b/) -> "lokal użytkowy"
      String.match?(url_lower, ~r/\bsklep\b/) -> "lokal użytkowy"
      String.match?(url_lower, ~r/\bmagazyn\b/) -> "lokal użytkowy"
      
      # AGGRESSIVE FALLBACK: Otodom URLs without clear type indicators
      # Default to mieszkanie (apartment) - most common (~65% of Otodom)
      String.contains?(url_lower, "otodom.pl") and
        not String.contains?(url_lower, "dom") and
        not String.contains?(url_lower, "dzialka") and
        not String.contains?(url_lower, "garaz") ->
        "mieszkanie"

      # FINAL FALLBACK: Default to mieszkanie for any unmatched property
      # Statistics show ~65% of Otodom listings are apartments
      true -> 
        Logger.debug("Otodom: Could not determine property_type, defaulting to mieszkanie")
        "mieszkanie"
    end
  end

  # Extract transaction type from text (URL, title)
  defp extract_transaction_type_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      # Rent patterns
      String.contains?(text_lower, "/wynajem") -> "wynajem"
      String.contains?(text_lower, "wynajem") -> "wynajem"
      String.contains?(text_lower, "/rent") -> "wynajem"
      String.contains?(text_lower, "rent") -> "wynajem"
      String.contains?(text_lower, "do-wynajecia") -> "wynajem"
      String.contains?(text_lower, "/mies") -> "wynajem"
      String.contains?(text_lower, "mc.") -> "wynajem"
      
      # Sale patterns
      String.contains?(text_lower, "/sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "/sale") -> "sprzedaż"
      String.contains?(text_lower, "/sell") -> "sprzedaż"
      String.contains?(text_lower, "na-sprzedaz") -> "sprzedaż"
      
      # Default for Otodom: if no clear rent indicators, assume sale
      String.contains?(text_lower, "otodom.pl") -> "sprzedaż"
      
      # FINAL FALLBACK: Default to sprzedaż for any unmatched transaction
      # Statistics show ~75% of all Otodom listings are for sale
      true -> 
        Logger.debug("Otodom: Could not determine transaction_type, defaulting to sprzedaż")
        "sprzedaż"
    end
  end

  # Validate/correct transaction type based on price
  # Catches misclassified listings from OLX/Otodom
  defp validate_transaction_type_by_price(transaction_type, price) when is_nil(price), do: transaction_type
  
  defp validate_transaction_type_by_price(transaction_type, price) do
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
        Logger.debug("Otodom: Setting transaction_type from price: #{price_float} zł → rent")
        "wynajem"
        
      is_nil(transaction_type) and price_float >= 30_000 ->
        Logger.debug("Otodom: Setting transaction_type from price: #{price_float} zł → sale")
        "sprzedaż"
        
      # Price < 30,000 zł - almost certainly rent, not sale
      price_float < 30_000 and transaction_type == "sprzedaż" ->
        Logger.info("Otodom: Correcting transaction_type: #{price_float} zł marked as sale → rent")
        "wynajem"
        
      # Price > 100,000 zł - almost certainly sale, not rent  
      price_float > 100_000 and transaction_type == "wynajem" ->
        Logger.info("Otodom: Correcting transaction_type: #{price_float} zł marked as rent → sale")
        "sprzedaż"
        
      true -> 
        transaction_type
    end
  end

  # Extract property type from text (title, URL, description)
  defp extract_property_type_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      # PRIORITY 1: URL patterns (most reliable)
      # Commercial properties
      String.contains?(text_lower, "/lokal-uzytkowy/") -> "lokal użytkowy"
      String.contains?(text_lower, "/lokal/") -> "lokal użytkowy"
      String.contains?(text_lower, "/biuro/") -> "lokal użytkowy"
      String.contains?(text_lower, "/biura/") -> "lokal użytkowy"
      String.contains?(text_lower, "-lokal-") -> "lokal użytkowy"
      String.contains?(text_lower, "-biuro-") -> "lokal użytkowy"

      # Apartment URL patterns
      String.contains?(text_lower, "/mieszkanie/") -> "mieszkanie"
      String.contains?(text_lower, "/mieszkania/") -> "mieszkanie"
      String.contains?(text_lower, "-mieszkanie-") -> "mieszkanie"
      String.contains?(text_lower, ",mieszkanie,") -> "mieszkanie"

      # House URL patterns
      String.contains?(text_lower, "/dom/") -> "dom"
      String.contains?(text_lower, "/domy/") -> "dom"
      String.contains?(text_lower, "-dom-") -> "dom"
      String.contains?(text_lower, ",dom,") -> "dom"

      # Plot URL patterns
      String.contains?(text_lower, "/dzialka/") -> "działka"
      String.contains?(text_lower, "/dzialki/") -> "działka"
      String.contains?(text_lower, "-dzialka-") -> "działka"

      # Garage URL patterns
      String.contains?(text_lower, "/garaz/") -> "garaż"
      String.contains?(text_lower, "/garaze/") -> "garaż"
      String.contains?(text_lower, "-garaz-") -> "garaż"
      String.contains?(text_lower, "-miejsce-parkingowe-") -> "garaż"

      # PRIORITY 2: Text-based detection
      # Apartment (mieszkanie) - most common, many variations
      String.contains?(text_lower, "mieszkan") -> "mieszkanie"
      String.contains?(text_lower, "kawalerka") -> "mieszkanie"
      String.contains?(text_lower, "apartament") -> "mieszkanie"
      String.match?(text_lower, ~r/\d+[\s-]*pokoj/) -> "mieszkanie"
      String.match?(text_lower, ~r/\b[1-9]-?pokojowe\b/) -> "mieszkanie"
      String.contains?(text_lower, "m²") && String.contains?(text_lower, "pokój") -> "mieszkanie"
      String.contains?(text_lower, "m2") && String.contains?(text_lower, "pokój") -> "mieszkanie"
      String.match?(text_lower, ~r/\b[2-6][\s-]?pok\.?\b/) -> "mieszkanie"
      String.contains?(text_lower, "-m-") -> "mieszkanie"
      String.contains?(text_lower, "studio") -> "mieszkanie"
      String.contains?(text_lower, "loft") -> "mieszkanie"
      String.contains?(text_lower, "penthouse") -> "mieszkanie"
      String.contains?(text_lower, "dwupokojowe") -> "mieszkanie"
      String.contains?(text_lower, "trzypokojowe") -> "mieszkanie"
      String.contains?(text_lower, "czteropokojowe") -> "mieszkanie"
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
      String.contains?(text_lower, "jednorodzinny") -> "dom"
      String.contains?(text_lower, "wolnostojący") -> "dom"
      String.contains?(text_lower, "rezydencja") -> "dom"

      # Room (pokój)
      String.contains?(text_lower, "pokój ") -> "pokój"
      String.contains?(text_lower, " pokój") -> "pokój"
      String.match?(text_lower, ~r/\bpokój\b/) -> "pokój"
      String.contains?(text_lower, "pokoj ") -> "pokój"
      String.match?(text_lower, ~r/\bpokoj\b/) -> "pokój"
      String.contains?(text_lower, "stancja") -> "pokój"
      String.contains?(text_lower, "kwatera") -> "pokój"
      String.contains?(text_lower, "dla studenta") -> "pokój"

      # Garage (garaż)
      String.contains?(text_lower, "garaż") -> "garaż"
      String.contains?(text_lower, "garaz") -> "garaż"
      String.contains?(text_lower, "miejsce postojowe") -> "garaż"
      String.contains?(text_lower, "miejsce parkingowe") -> "garaż"
      String.match?(text_lower, ~r/\bmiejsce\s+(w\s+)?parking/) -> "garaż"
      String.contains?(text_lower, "hala garażowa") -> "garaż"

      # Plot/land (działka)
      String.contains?(text_lower, "działka") -> "działka"
      String.contains?(text_lower, "dzialka") -> "działka"
      String.match?(text_lower, ~r/\bgrunt\b/) -> "działka"
      String.match?(text_lower, ~r/\bteren\b/) -> "działka"
      String.contains?(text_lower, "budowlana") -> "działka"
      String.contains?(text_lower, "rolna") -> "działka"
      String.match?(text_lower, ~r/\b\d+\s*ar\b/) -> "działka"
      String.match?(text_lower, ~r/\b\d+\s*ha\b/) -> "działka"

      # Commercial space (lokal użytkowy) - check text keywords
      String.contains?(text_lower, "lokal użytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "biura i lokale") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal handlowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal usługowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal biurowy") -> "lokal użytkowy"
      String.match?(text_lower, ~r/\blokal\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bbiuro\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bbiura\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bsklep\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bmagazyn\b/) -> "lokal użytkowy"
      String.match?(text_lower, ~r/\bhala\b/) -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia biurowa") -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia handlowa") -> "lokal użytkowy"
      String.contains?(text_lower, "powierzchnia magazynowa") -> "lokal użytkowy"

      # AGGRESSIVE FALLBACK: If still no match and it's Otodom
      # Default to mieszkanie - most common property type
      String.contains?(text_lower, "otodom.pl") and
        not String.contains?(text_lower, "dom") and
        not String.contains?(text_lower, "dzialka") ->
        "mieszkanie"

      # FINAL FALLBACK: Default to mieszkanie for any unmatched property
      true ->
        Logger.debug("Otodom: extract_property_type_from_text defaulting to mieszkanie")
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
