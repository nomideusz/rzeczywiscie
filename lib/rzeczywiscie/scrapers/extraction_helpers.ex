defmodule Rzeczywiscie.Scrapers.ExtractionHelpers do
  @moduledoc """
  Shared extraction helpers for scraping property data.
  Used by OlxScraper, OtodomScraper, and PropertyRescraper to ensure
  consistent parsing of prices, areas, and room counts.
  """

  require Logger

  # Minimum valid prices to avoid extracting room counts or erroneous values
  # Rent: at least 100 PLN (no one rents for less)
  # Sale: at least 10,000 PLN (no one sells for less)
  # We use 100 as base minimum since we may not know transaction type at parse time
  @min_price_pln 100
  @max_price_pln 99_999_999
  
  # Kraków districts - used to infer city from district
  @krakow_districts [
    "Stare Miasto", "Grzegórzki", "Prądnik Czerwony", "Prądnik Biały",
    "Krowodrza", "Bronowice", "Zwierzyniec", "Dębniki", "Łagiewniki",
    "Swoszowice", "Podgórze", "Bieżanów", "Prokocim", "Czyżyny",
    "Mistrzejowice", "Bieńczyce", "Wzgórza Krzesławickie", "Nowa Huta",
    # Sub-districts and alternative spellings
    "Kazimierz", "Salwator", "Wola Justowska", "Ruczaj", "Pychowice",
    "Borek Fałęcki", "Zabłocie", "Płaszów", "Rybitwy", "Łęg",
    "Kurdwanów", "Wola Duchacka", "Kliny", "Podgórze Duchackie",
    "Azory", "Olsza", "Dąbie", "Lubicz", "Wielopole", "Stradom"
  ]
  
  @doc """
  Infer city from district name. If district is a known Kraków district, return "Kraków".
  Returns the original city if provided, otherwise attempts to infer from district.
  """
  def infer_city(city, district) do
    # If city is already set and non-empty, use it
    if city && city != "" do
      city
    else
      # Try to infer city from district
      infer_city_from_district(district)
    end
  end
  
  @doc """
  Check if a district is a Kraków district and return "Kraków" if so.
  """
  def infer_city_from_district(nil), do: nil
  def infer_city_from_district(""), do: nil
  def infer_city_from_district(district) when is_binary(district) do
    district_clean = String.trim(district)
    
    # Check if district matches any known Kraków district
    if Enum.any?(@krakow_districts, fn kd -> 
      String.downcase(kd) == String.downcase(district_clean) ||
      String.contains?(String.downcase(district_clean), String.downcase(kd))
    end) do
      "Kraków"
    else
      nil
    end
  end
  def infer_city_from_district(_), do: nil

  @doc """
  Parse price text to Decimal.
  Handles formats like: "1 200 zł", "1,200.50 PLN", "1200", "1 200,50"
  
  Returns nil if:
  - Price is below #{@min_price_pln} PLN (likely room count or error)
  - Price is above #{@max_price_pln} PLN (database limit)
  - Text is unparseable
  """
  def parse_price(text) when is_binary(text) do
    # REQUIRE "zł" or "PLN" suffix to avoid matching random numbers like room counts
    # More strict regex: must end with currency indicator
    regex = ~r/(\d{1,3}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*(?:zł|PLN)/i

    case Regex.run(regex, text) do
      [_, price_str] ->
        # Clean up: remove spaces and normalize decimal separator
        clean_price =
          price_str
          |> String.replace(~r/\s+/, "")
          |> String.replace(",", ".")

        case Decimal.parse(clean_price) do
          {decimal, _} ->
            min_price = Decimal.new(@min_price_pln)
            max_price = Decimal.new(@max_price_pln)
            
            # Validate: price should be reasonable
            # - At least 100 PLN (anything less is likely a room count like "2 zł" or "3 zł")
            # - At most 99,999,999 PLN (database constraint)
            if Decimal.compare(decimal, min_price) != :lt and
                 Decimal.compare(decimal, max_price) != :gt do
              decimal
            else
              Logger.debug("Price out of range: #{clean_price} PLN (must be #{@min_price_pln}-#{@max_price_pln}) - ignoring")
              nil
            end

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  def parse_price(_), do: nil

  @doc """
  Parse area number string to Decimal with validation.
  
  Options:
    * `:min_area` - Minimum valid area (default: 5)
    * `:max_area` - Maximum valid area (default: 50000)
  """
  def parse_area_number(number_str, opts \\ []) do
    max_area = Keyword.get(opts, :max_area, 50000)
    min_area = Keyword.get(opts, :min_area, 5)

    # Clean up the number: remove spaces and replace comma with dot
    clean_number =
      number_str
      |> String.replace(~r/\s+/, "")
      |> String.replace(",", ".")

    case Decimal.parse(clean_number) do
      {decimal, _} ->
        # Validate: area should be reasonable
        if Decimal.compare(decimal, Decimal.new(min_area)) != :lt and
             Decimal.compare(decimal, Decimal.new(max_area)) != :gt do
          decimal
        else
          Logger.debug("Area out of range: #{clean_number} m² (min: #{min_area}, max: #{max_area}) - ignoring")
          nil
        end

      :error ->
        Logger.debug("Could not parse area: #{clean_number}")
        nil
    end
  end

  @doc """
  Extract area from text, prioritizing building area keywords.
  Avoids matching plot/land area when possible.
  """
  def extract_area_from_text(text) when is_binary(text) do
    # Try to find building area with specific keywords first
    building_area = extract_building_area(text)

    if building_area do
      building_area
    else
      # Fallback: find any area but validate it's reasonable for a building
      extract_any_area(text)
    end
  end

  def extract_area_from_text(_), do: nil

  defp extract_building_area(text) do
    # Keywords that indicate building/usable area (not plot)
    building_keywords = [
      "powierzchnia użytkowa",
      "pow\\. użytkowa",
      "pow\\.użytkowa",
      "powierzchnia",
      "pow\\.",
      "pow ",
      "mieszkanie",
      "dom",
      "lokal",
      "garaż",
      "pokój",
      "kawalerka"
    ]

    # Area units: m², m2, m^2, mkw, m.kw., metrów kw
    area_unit_pattern = "(?:m[\\^²2]|mkw\\.?|m\\.kw\\.?|metrów\\s*kw)"

    regex_patterns =
      Enum.map(building_keywords, fn keyword ->
        ~r/#{keyword}[:\s]*(\d{1,4}(?:[,\.]\d{1,2})?)\s*#{area_unit_pattern}/iu
      end)

    # Try each pattern
    Enum.find_value(regex_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, number_str] -> parse_area_number(number_str, max_area: 2000, min_area: 5)
        _ -> nil
      end
    end)
  end

  defp extract_any_area(text) do
    # Area units: m², m2, m^2, mkw, m.kw., metrów kw
    area_unit_pattern = "(?:m[\\^²2]|mkw\\.?|m\\.kw\\.?|metrów\\s*kw)"

    # First, try patterns with the number BEFORE the unit (most common)
    # Match: "75 m²", "45.5m2", "100 mkw"
    # IMPORTANT: negative lookbehind must include dot/comma to avoid matching "89" from "60.89"
    regex_before = ~r/(?<![0-9.,])(\d{1,4}(?:[,\.]\d{1,2})?)\s*#{area_unit_pattern}/iu

    case Regex.run(regex_before, text) do
      [_, number_str] ->
        # For fallback, use stricter validation
        parse_area_number(number_str, max_area: 2000, min_area: 5)

      _ ->
        # Also try format with number separated: "75 m 2" or with space before
        # IMPORTANT: negative lookbehind must include dot/comma to avoid matching "89" from "60.89"
        regex_spaced = ~r/(?<![0-9.,])(\d{1,4}(?:[,\.]\d{1,2})?)\s+m\s*[\^²2]/iu

        case Regex.run(regex_spaced, text) do
          [_, number_str] -> parse_area_number(number_str, max_area: 2000, min_area: 5)
          _ -> nil
        end
    end
  end

  @doc """
  Extract room count from text using Polish patterns.
  Returns an integer or nil.
  """
  def extract_rooms_from_text(text) when is_binary(text) do
    text_lower = String.downcase(text)

    room_count =
      cond do
        # Pattern: "Liczba pokoi: X" or "Pokoi: X"
        match = Regex.run(~r/(?:liczba\s+)?pokoi?:\s*(\d+)/, text_lower) ->
          [_, num] = match
          parse_room_number(num)

        # Pattern: "X-pokojowe" or "X pokojowe"
        match = Regex.run(~r/(\d+)[\s-]*pokojow/, text_lower) ->
          [_, num] = match
          parse_room_number(num)

        # Pattern: "X pokoje" or "X-pokoje"
        match = Regex.run(~r/(\d+)[\s-]*pokoje/, text_lower) ->
          [_, num] = match
          parse_room_number(num)

        # Pattern: "X-pok" or "X pok" (without period, not followed by 'oj')
        match = Regex.run(~r/(\d+)[\s-]*pok(?!oj)/, text_lower) ->
          [_, num] = match
          parse_room_number(num)

        # Abbreviated patterns: "2-pok.", "3 pok."
        match = Regex.run(~r/(\d+)[\s-]*pok\./, text_lower) ->
          [_, num] = match
          parse_room_number(num)

        # Polish word numbers
        String.contains?(text_lower, "jednopokojow") -> 1
        String.contains?(text_lower, "dwupokojow") -> 2
        String.contains?(text_lower, "trzypokojow") -> 3
        String.contains?(text_lower, "czteropokojow") -> 4
        String.contains?(text_lower, "pięciopokojow") -> 5
        String.contains?(text_lower, "sześciopokojow") -> 6

        # Pattern: "kawalerka" = 1 room
        String.contains?(text_lower, "kawalerka") -> 1

        # Pattern: "studio" = 1 room
        String.contains?(text_lower, "studio") -> 1

        # Pattern: "garsoniera" = 1 room
        String.contains?(text_lower, "garsoniera") -> 1

        # Pattern: "jednoosobowy" or "1-osobowy" = 1 room
        String.contains?(text_lower, "jednoosobowy") -> 1
        String.match?(text_lower, ~r/1[\s-]*osobow/) -> 1

        # Pattern: "X osobne pokoje"
        String.contains?(text_lower, "2 osobne pokoje") -> 2
        String.contains?(text_lower, "3 osobne pokoje") -> 3

        true -> nil
      end

    room_count
  end

  def extract_rooms_from_text(_), do: nil

  defp parse_room_number(num_str) do
    case Integer.parse(num_str) do
      {num, _} when num > 0 and num <= 20 -> num
      _ -> nil
    end
  end

  @doc """
  Extract a number that precedes a given unit.
  E.g., extract_number_with_unit("3 pokoje", "pokoje") => Decimal(3)
  """
  def extract_number_with_unit(text, unit) when is_binary(text) and is_binary(unit) do
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

  def extract_number_with_unit(_, _), do: nil

  @doc """
  Extract price from entire document text as a fallback.
  Looks for price patterns with zł/PLN suffix.
  Validates that extracted price is >= #{@min_price_pln} PLN.
  """
  def extract_price_from_full_text(text) when is_binary(text) do
    # Look for price with zł/PLN to be specific - REQUIRE currency suffix
    regex = ~r/(\d{1,3}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*(?:zł|PLN)/i

    case Regex.run(regex, text) do
      [full_match, _] -> parse_price(full_match)
      _ -> nil
    end
  end

  def extract_price_from_full_text(_), do: nil

  @doc """
  Fetch and extract description from OLX listing page.
  Note: OLX often redirects to Otodom (same company), so we detect and handle both.
  Returns {:ok, description} or {:error, reason}.
  """
  def fetch_olx_description(url) when is_binary(url) do
    case fetch_page(url) do
      {:ok, html} ->
        case Floki.parse_document(html) do
          {:ok, document} ->
            # Check if we landed on Otodom (redirect)
            page_title = Floki.find(document, "title") |> Floki.text() |> String.downcase()
            
            description = if String.contains?(page_title, "otodom") do
              Logger.info("OLX URL redirected to Otodom, using Otodom selectors")
              extract_otodom_description_from_document(document)
            else
              extract_olx_description_from_document(document)
            end
            
            {:ok, description}

          {:error, reason} ->
            Logger.warning("Failed to parse OLX page: #{inspect(reason)}")
            {:error, :parse_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_olx_description(_), do: {:error, :invalid_url}

  @doc """
  Fetch and extract description from Otodom listing page.
  Returns {:ok, description} or {:error, reason}.
  """
  def fetch_otodom_description(url) when is_binary(url) do
    case fetch_page(url) do
      {:ok, html} ->
        case Floki.parse_document(html) do
          {:ok, document} ->
            description = extract_otodom_description_from_document(document)
            {:ok, description}

          {:error, reason} ->
            Logger.warning("Failed to parse Otodom page: #{inspect(reason)}")
            {:error, :parse_error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_otodom_description(_), do: {:error, :invalid_url}

  # Fetch a web page with proper headers
  defp fetch_page(url) do
    headers = [
      {"user-agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"},
      {"accept",
       "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
      {"accept-language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"},
      {"accept-encoding", "gzip, deflate, br"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 15_000, max_redirects: 5) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.warning("HTTP #{status} when fetching #{url}")
        {:error, :http_error}

      {:error, reason} ->
        Logger.warning("Failed to fetch #{url}: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  # Extract description from OLX document
  defp extract_olx_description_from_document(document) do
    # OLX description selectors (try multiple)
    selectors = [
      "div[data-cy='ad_description'] div",
      "div[data-cy='ad_description']",
      "div.css-1o924a9",  # OLX description container class
      "div.css-bgzo2k",   # Alternative class
      "div[class*='description']",
      # New selectors for updated OLX layout
      "div[data-testid='ad-description-container']",
      "div.css-g5mtbi-Text",  # Possible new description class
      "div[class*='Ad__content']"
    ]

    description =
      Enum.reduce_while(selectors, nil, fn selector, _acc ->
        elements = Floki.find(document, selector)
        text =
          elements
          |> Floki.text()
          |> String.trim()

        if text != "" and String.length(text) > 10 do
          Logger.info("OLX description found with selector: #{selector}")
          {:halt, text}
        else
          if length(elements) > 0 do
            Logger.info("OLX selector '#{selector}' found #{length(elements)} elements but no text")
          end
          {:cont, nil}
        end
      end)

    # If no description found, log available data-cy and data-testid attributes for debugging
    if is_nil(description) do
      debug_olx_structure(document)
    end

    description
  end
  
  # Debug helper to identify what selectors are available on OLX pages
  defp debug_olx_structure(document) do
    # Find elements with data-cy or data-testid
    data_cy_elements = Floki.find(document, "[data-cy]")
    data_testid_elements = Floki.find(document, "[data-testid]")
    
    data_cy_values = 
      data_cy_elements
      |> Enum.map(fn {_tag, attrs, _} ->
        Enum.find_value(attrs, fn
          {"data-cy", value} -> value
          _ -> nil
        end)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(20)
    
    data_testid_values = 
      data_testid_elements
      |> Enum.map(fn {_tag, attrs, _} ->
        Enum.find_value(attrs, fn
          {"data-testid", value} -> value
          _ -> nil
        end)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(20)
    
    Logger.info("OLX page has data-cy: #{inspect(data_cy_values)}")
    Logger.info("OLX page has data-testid: #{inspect(data_testid_values)}")
    
    # Also check for divs with description-like classes
    description_divs = Floki.find(document, "div[class*='escription'], div[class*='Content'], div[class*='content']")
    Logger.info("OLX page has #{length(description_divs)} divs with description/content in class")
    
    # Log actual content of description divs to see what we're getting
    if length(description_divs) > 0 do
      Enum.each(Enum.take(description_divs, 3), fn div ->
        text = Floki.text(div) |> String.trim() |> String.slice(0, 200)
        {_tag, attrs, _} = div
        class = Enum.find_value(attrs, fn {"class", v} -> v; _ -> nil end) || "no-class"
        Logger.info("  Description div (class=#{String.slice(class, 0, 50)}): '#{text}'")
      end)
    end
    
    # Check page title to see if we're on the right page
    title = Floki.find(document, "title") |> Floki.text() |> String.trim()
    Logger.info("OLX page title: #{title}")
    
    # Check if there's a login wall or cookie consent
    body_text = Floki.find(document, "body") |> Floki.text() |> String.slice(0, 500)
    if String.contains?(body_text, ["logowanie", "zaloguj", "cookie", "Captcha", "robot"]) do
      Logger.warning("OLX page may have login/cookie/captcha wall")
    end
  end

  # Extract description from Otodom document
  defp extract_otodom_description_from_document(document) do
    # Try multiple strategies for Otodom descriptions

    # Strategy 1: Find description in specific div
    description = try_otodom_description_selectors(document)

    # Strategy 2: Extract from JSON-LD if available
    description = description || try_otodom_json_ld_description(document)

    description
  end

  defp try_otodom_description_selectors(document) do
    selectors = [
      # Primary Otodom description selectors
      "div[data-cy='adPageAdDescription']",
      "section[aria-label='Opis']",
      "div[data-testid='ad-description']",
      "section[data-testid='ad-description-section']",
      # Class-based selectors (Otodom uses CSS modules)
      "div.css-1wekrze",
      "div.css-1k7yu81",
      "div.css-1bi0g88",  # Possible description container
      "div.css-1t38rho",  # Another common pattern
      # Section-based selectors
      "section.css-10m5oaz",  # Description section
      "div[class*='AdDescription']",
      "div[class*='adDescription']",
      # Generic but specific enough
      "article section p",
      "main section p"
    ]

    description = Enum.reduce_while(selectors, nil, fn selector, _acc ->
      elements = Floki.find(document, selector)
      text =
        elements
        |> Floki.text()
        |> String.trim()
        |> clean_css_artifacts()  # Clean up inline CSS artifacts

      if text != "" and String.length(text) > 50 do
        Logger.info("Otodom description found with selector: #{selector} (#{String.length(text)} chars)")
        {:halt, text}
      else
        {:cont, nil}
      end
    end)
    
    # If no description found via selectors, try to find any large text block
    description = if is_nil(description) do
      Logger.info("Trying fallback: looking for any substantial text block")
      try_find_any_description_block(document)
    else
      description
    end
    
    # If still no description found, log debug info
    if is_nil(description) do
      Logger.info("No Otodom description found with any selector")
      debug_otodom_structure(document)
    end
    
    description
  end
  
  # Clean up CSS-in-JS artifacts that sometimes appear in scraped text
  defp clean_css_artifacts(text) do
    text
    |> String.replace(~r/\.css-[a-z0-9]+\{[^}]+\}/i, "")
    |> String.replace(~r/-webkit-[^;]+;/i, "")
    |> String.replace(~r/-ms-[^;]+;/i, "")
    |> String.replace(~r/flex-shrink:[^;]+;/i, "")
    |> String.trim()
  end
  
  # Try to find any block of text that looks like a description
  defp try_find_any_description_block(document) do
    # Find all paragraphs and divs, look for one with substantial text
    candidates = 
      Floki.find(document, "p, div") 
      |> Enum.map(fn el -> 
        text = Floki.text(el) |> String.trim() |> clean_css_artifacts()
        {el, text, String.length(text)}
      end)
      |> Enum.filter(fn {_el, text, len} -> 
        len > 200 and  # Substantial length
        not String.contains?(text, ["Cookie", "Polityka prywatności", "Regulamin"]) and  # Not legal text
        String.contains?(text, [" ", "."]) # Has spaces and sentences
      end)
      |> Enum.sort_by(fn {_, _, len} -> -len end)  # Longest first
      |> Enum.take(1)
    
    case candidates do
      [{_el, text, len}] -> 
        Logger.info("Found description fallback: #{len} chars")
        text
      _ -> 
        nil
    end
  end
  
  # Debug helper for Otodom pages
  defp debug_otodom_structure(document) do
    # Find sections with aria-label
    sections = Floki.find(document, "section[aria-label]")
    aria_labels = Enum.map(sections, fn {_, attrs, _} ->
      Enum.find_value(attrs, fn {"aria-label", v} -> v; _ -> nil end)
    end) |> Enum.reject(&is_nil/1) |> Enum.take(10)
    Logger.info("Otodom sections with aria-label: #{inspect(aria_labels)}")
    
    # Find data-testid elements
    testid_elements = Floki.find(document, "[data-testid]")
    testids = Enum.map(testid_elements, fn {_, attrs, _} ->
      Enum.find_value(attrs, fn {"data-testid", v} -> v; _ -> nil end)
    end) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.take(15)
    Logger.info("Otodom data-testid values: #{inspect(testids)}")
  end

  defp try_otodom_json_ld_description(document) do
    # Find JSON-LD script tags
    json_ld_scripts = Floki.find(document, "script[type='application/ld+json']")

    Enum.reduce_while(json_ld_scripts, nil, fn {_tag, _attrs, children}, _acc ->
      content = case children do
        [single_content] when is_binary(single_content) -> single_content
        multiple -> Enum.join(multiple, "")
      end

      case Jason.decode(content) do
        {:ok, json_data} ->
          description = extract_description_from_json(json_data)
          if description && String.length(description) > 10 do
            {:halt, description}
          else
            {:cont, nil}
          end

        {:error, _} ->
          {:cont, nil}
      end
    end)
  end

  defp extract_description_from_json(%{"description" => desc}) when is_binary(desc), do: desc
  defp extract_description_from_json(%{"@graph" => graph}) when is_list(graph) do
    Enum.find_value(graph, fn item -> extract_description_from_json(item) end)
  end
  defp extract_description_from_json(_), do: nil
end

