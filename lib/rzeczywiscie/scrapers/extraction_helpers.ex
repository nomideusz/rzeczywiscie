defmodule Rzeczywiscie.Scrapers.ExtractionHelpers do
  @moduledoc """
  Shared extraction helpers for scraping property data.
  Used by OlxScraper, OtodomScraper, and PropertyRescraper to ensure
  consistent parsing of prices, areas, and room counts.
  """

  require Logger

  @doc """
  Parse price text to Decimal.
  Handles formats like: "1 200 zł", "1,200.50 PLN", "1200", "1 200,50"
  
  Returns nil if price is out of range (1 to 99,999,999 PLN) or unparseable.
  """
  def parse_price(text) when is_binary(text) do
    # Use regex to extract price pattern first, before stripping chars
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
    regex_before = ~r/(?<![0-9-])(\d{1,4}(?:[,\.]\d{1,2})?)\s*#{area_unit_pattern}/iu

    case Regex.run(regex_before, text) do
      [_, number_str] ->
        # For fallback, use stricter validation
        parse_area_number(number_str, max_area: 2000, min_area: 5)

      _ ->
        # Also try format with number separated: "75 m 2" or with space before
        regex_spaced = ~r/(\d{1,4}(?:[,\.]\d{1,2})?)\s+m\s*[\^²2]/iu

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
  """
  def extract_price_from_full_text(text) when is_binary(text) do
    # Look for price with zł to be specific
    regex = ~r/(\d{1,3}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*(?:zł|PLN)/i

    case Regex.run(regex, text) do
      [full_match, _] -> parse_price(full_match)
      _ -> nil
    end
  end

  def extract_price_from_full_text(_), do: nil
end

