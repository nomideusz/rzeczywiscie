defmodule Rzeczywiscie.Scrapers.PropertyRescraper do
  @moduledoc """
  Re-scrapes individual property pages to update missing data.
  Fetches the original URL and extracts price, area, rooms, etc.
  """

  require Logger
  alias Rzeczywiscie.RealEstate

  @doc """
  Re-scrape properties missing specific fields.
  
  Options:
    * `:limit` - Maximum properties to re-scrape (default: 50)
    * `:delay` - Delay between requests in ms (default: 2000)
    * `:missing` - Which field to target: :price, :area, :rooms, :all (default: :price)
  """
  def rescrape_missing(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    delay = Keyword.get(opts, :delay, 2000)
    missing_field = Keyword.get(opts, :missing, :price)

    Logger.info("Starting re-scrape for properties missing #{missing_field}")
    Logger.info("Limit: #{limit}, Delay: #{delay}ms")

    # Get properties to re-scrape
    properties = get_properties_to_rescrape(missing_field, limit)

    Logger.info("Found #{length(properties)} properties to re-scrape")

    if length(properties) == 0 do
      {:ok, %{total: 0, updated: 0, failed: 0}}
    else
      results = 
        Enum.with_index(properties, 1)
        |> Enum.map(fn {property, index} ->
          Logger.info("[#{index}/#{length(properties)}] Re-scraping property ##{property.id} (#{property.source})")
          
          result = rescrape_property(property)
          
          # Add delay between requests
          if index < length(properties), do: Process.sleep(delay)
          
          result
        end)

      updated = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("✓ Re-scrape completed: #{updated} updated, #{failed} failed out of #{length(properties)}")
      
      {:ok, %{total: length(properties), updated: updated, failed: failed}}
    end
  end

  defp get_properties_to_rescrape(missing_field, limit) do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    query = from(p in Property,
      where: p.active == true,
      order_by: [desc: p.inserted_at],
      limit: ^limit,
      select: %{
        id: p.id,
        url: p.url,
        source: p.source,
        external_id: p.external_id,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms
      }
    )

    query = case missing_field do
      :price -> where(query, [p], is_nil(p.price))
      :area -> where(query, [p], is_nil(p.area_sqm))
      :rooms -> where(query, [p], is_nil(p.rooms))
      :all -> where(query, [p], is_nil(p.price) or is_nil(p.area_sqm) or is_nil(p.rooms))
    end

    Repo.all(query)
  end

  defp rescrape_property(property) do
    case property.source do
      "olx" -> rescrape_olx(property)
      "otodom" -> rescrape_otodom(property)
      _ -> {:error, :unsupported_source}
    end
  end

  defp rescrape_olx(property) do
    Logger.info("Fetching OLX page: #{String.slice(property.url, 0, 60)}...")

    case fetch_page(property.url) do
      {:ok, html} ->
        extracted = parse_olx_detail_page(html)
        update_property_with_extracted_data(property, extracted)

      {:error, reason} ->
        Logger.error("Failed to fetch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp rescrape_otodom(property) do
    Logger.info("Fetching Otodom page: #{String.slice(property.url, 0, 60)}...")

    case fetch_page(property.url) do
      {:ok, html} ->
        extracted = parse_otodom_detail_page(html)
        update_property_with_extracted_data(property, extracted)

      {:error, reason} ->
        Logger.error("Failed to fetch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_page(url) do
    case Req.get(url, headers: [{"user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_olx_detail_page(html) do
    document = Floki.parse_document!(html)

    %{
      price: extract_olx_price(document),
      area_sqm: extract_olx_area(document),
      rooms: extract_olx_rooms(document)
    }
  end

  defp parse_otodom_detail_page(html) do
    document = Floki.parse_document!(html)

    %{
      price: extract_otodom_price(document),
      area_sqm: extract_otodom_area(document),
      rooms: extract_otodom_rooms(document)
    }
  end

  defp extract_olx_price(document) do
    # Try multiple selectors for price on detail page
    selectors = [
      "h3[data-testid='ad-price-container']",
      "[data-testid='ad-price']",
      "h3[class*='price']",
      "div[class*='price'] h3",
      "h3[class*='Price']",
      "[class*='priceContainer']",
      "h3", # Try all h3 tags
      "strong" # Try strong tags
    ]

    price_text = Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) |> Floki.text() do
        "" -> nil
        text -> 
          # Check if this text contains a price pattern
          if String.match?(text, ~r/\d+.*(?:zł|PLN)/i) do
            text
          else
            nil
          end
      end
    end)

    # Parse the price text to Decimal
    if price_text do
      parse_price_text(price_text)
    else
      # If no price found, search entire document
      extract_price_from_document_text(document)
    end
  end

  defp extract_otodom_price(document) do
    # Otodom uses structured data - try multiple approaches
    selectors = [
      "strong[data-cy='ad.top-information.price']",
      "[data-cy='ad.top-information.price']",
      "strong[aria-label*='Cena']",
      "div[aria-label*='Cena']",
      "strong[class*='Price']",
      "div[class*='price'] strong",
      "div[class*='Price'] strong",
      "[class*='priceInfo'] strong",
      "strong", # Try all strong tags as fallback
      "h3"  # Sometimes price is in h3
    ]

    price_text = Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) |> Floki.text() do
        "" -> nil
        text -> 
          # Check if this text contains a price pattern
          if String.match?(text, ~r/\d+.*(?:zł|PLN)/i) do
            text
          else
            nil
          end
      end
    end)

    # Parse the price text to Decimal (same as extract_olx_price)
    if price_text do
      parse_price_text(price_text)
    else
      # If no price found, search entire document
      extract_price_from_document_text(document)
    end
  end

  defp extract_olx_area(document) do
    # Look for area in parameters/details section
    text = Floki.text(document)
    
    # Try patterns: "Powierzchnia: 50 m²", "50 m²", "50m2"
    regex = ~r/(\d+(?:[,\.]\d+)?)\s*(?:m²|m2|mkw)/i
    
    case Regex.run(regex, text) do
      [_, area_str] ->
        clean = String.replace(area_str, ",", ".")
        case Decimal.parse(clean) do
          {decimal, _} -> 
            # Validate reasonable range (5-2000 m²)
            if Decimal.compare(decimal, 5) != :lt and Decimal.compare(decimal, 2000) != :gt do
              decimal
            else
              nil
            end
          :error -> nil
        end
      _ -> nil
    end
  end

  defp extract_otodom_area(document) do
    # Otodom typically shows area in details
    extract_olx_area(document)  # Same logic works
  end

  defp extract_olx_rooms(document) do
    text = Floki.text(document)
    extract_rooms_from_text(text)
  end

  defp extract_otodom_rooms(document) do
    text = Floki.text(document)
    extract_rooms_from_text(text)
  end

  defp extract_rooms_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      # "Liczba pokoi: 3" or "Pokoi: 3"
      match = Regex.run(~r/(?:liczba\s+)?pokoi?:\s*(\d+)/, text_lower) ->
        [_, num] = match
        String.to_integer(num)

      # "3-pokojowe", "2 pokojowe"
      match = Regex.run(~r/(\d+)[\s-]*pokojow/, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "3 pokoje", "2-pokoje"
      match = Regex.run(~r/(\d+)[\s-]*pokoje/, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "3-pok", "2 pok."
      match = Regex.run(~r/(\d+)[\s-]*pok\.?(?!oj)/, text_lower) ->
        [_, num] = match
        String.to_integer(num)

      # Polish word numbers
      String.contains?(text_lower, "jednopokojow") -> 1
      String.contains?(text_lower, "dwupokojow") -> 2
      String.contains?(text_lower, "trzypokojow") -> 3
      String.contains?(text_lower, "czteropokojow") -> 4

      # Single room
      String.contains?(text_lower, "kawalerka") -> 1
      String.contains?(text_lower, "studio") -> 1

      true -> nil
    end
  end

  defp extract_price_from_document_text(document) do
    # Get all text and look for price patterns
    full_text = Floki.text(document)
    
    # Look for price with zł to be specific
    regex = ~r/(\d{1,3}(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)\s*(?:zł|PLN)/i
    
    case Regex.run(regex, full_text) do
      [full_match, _] -> parse_price_text(full_match)
      _ -> nil
    end
  end

  defp parse_price_text(text) do
    # Remove all whitespace and extract number
    regex = ~r/(\d+(?:[\s,.]\d{3})*(?:[,.]\d{1,2})?)/
    
    case Regex.run(regex, text) do
      [_, price_str] ->
        clean = price_str
          |> String.replace(~r/\s+/, "")
          |> String.replace(",", ".")
        
        case Decimal.parse(clean) do
          {decimal, _} ->
            # Validate reasonable price range (100 PLN to 99M PLN)
            if Decimal.compare(decimal, 100) != :lt and Decimal.compare(decimal, 99999999) != :gt do
              decimal
            else
              nil
            end
          :error -> nil
        end
      _ -> nil
    end
  end

  defp update_property_with_extracted_data(property, extracted) do
    # Only update fields that are currently nil
    updates = %{}
    
    # DEBUG: Log what we extracted
    if extracted.price do
      price_type = if is_struct(extracted.price, Decimal), do: "Decimal", else: inspect(extracted.price)
      Logger.info("  DEBUG: Extracted price = #{inspect(extracted.price)} (type: #{price_type})")
    end
    
    updates = if is_nil(property.price) and extracted.price, do: Map.put(updates, :price, extracted.price), else: updates
    updates = if is_nil(property.area_sqm) and extracted.area_sqm, do: Map.put(updates, :area_sqm, extracted.area_sqm), else: updates
    updates = if is_nil(property.rooms) and extracted.rooms, do: Map.put(updates, :rooms, extracted.rooms), else: updates

    if map_size(updates) > 0 do
      Logger.info("  Attempting update with: #{inspect(updates)}")
      
      case RealEstate.update_property(
        RealEstate.get_property(property.id),
        updates
      ) do
        {:ok, updated_property} ->
          Logger.info("✓ Updated property ##{property.id}: #{inspect(updates)}")
          {:ok, updated_property}
        {:error, changeset} ->
          Logger.error("✗ Failed to update property ##{property.id}: #{inspect(changeset.errors)}")
          Logger.error("  Updates that failed: #{inspect(updates)}")
          {:error, changeset}
      end
    else
      Logger.info("- No new data found for property ##{property.id}")
      {:ok, :no_changes}
    end
  end
end

