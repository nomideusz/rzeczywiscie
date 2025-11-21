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
    saved =
      Enum.map(results, fn property_data ->
        case RealEstate.upsert_property(property_data) do
          {:ok, property} ->
            {:ok, property}

          {:error, changeset} ->
            Logger.error("Failed to save property: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      end)

    successful = Enum.count(saved, fn {status, _} -> status == :ok end)
    Logger.info("OLX scrape completed: #{successful}/#{length(results)} properties saved")

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
          Logger.warn("Response seems short (#{String.length(body)} bytes) - might be blocked")
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
        Logger.warn("Could not save debug HTML: #{inspect(reason)}")
    end
  end

  defp parse_listings(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Debug: Check what we received
        Logger.info("HTML length: #{String.length(html)}")

        # Check if we got blocked/captcha
        if String.contains?(html, ["captcha", "robot", "blocked"]) do
          Logger.warn("Possible bot detection - page contains captcha/robot keywords")
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

    Logger.warn("⚠️  No listings found! Available data-cy values: #{inspect(data_cy_values)}")

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
      external_id = extract_id_from_url(url) || generate_id_from_card(card)

      %{
        source: "olx",
        external_id: external_id,
        title: String.trim(title),
        url: ensure_absolute_url(url),
        price: extract_price(card),
        currency: "PLN",
        area_sqm: extract_area(card),
        rooms: extract_rooms(card),
        city: extract_city(card),
        district: extract_district(card),
        voivodeship: "małopolskie",
        image_url: extract_image(card),
        description: extract_description(card),
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
    # OLX URLs typically contain ID like /d/ogloszenie/TITLE-ID12345678.html
    case Regex.run(~r/ID([A-Za-z0-9]+)/, url) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp generate_id_from_card(card) do
    # Fallback: use hash of card content
    card
    |> Floki.text()
    |> String.slice(0, 100)
    |> :erlang.phash2()
    |> Integer.to_string()
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
    text
    |> String.replace(~r/[^\d,]/, "")
    |> String.replace(",", ".")
    |> case do
      "" -> nil
      price_str ->
        case Decimal.parse(price_str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp extract_area(card) do
    card
    |> Floki.text()
    |> extract_number_with_unit("m²")
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

  defp ensure_absolute_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      @base_url <> url
    end
  end
end
