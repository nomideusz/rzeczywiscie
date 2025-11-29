defmodule Rzeczywiscie.Scrapers.PropertyRescraper do
  @moduledoc """
  Re-scrapes individual property pages to update missing data.
  Fetches the original URL and extracts price, area, rooms, etc.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Scrapers.ExtractionHelpers

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

  # Price extraction for OLX detail pages using shared helpers
  defp extract_olx_price(document) do
    selectors = [
      "h3[data-testid='ad-price-container']",
      "[data-testid='ad-price']",
      "h3[class*='price']",
      "div[class*='price'] h3",
      "h3[class*='Price']",
      "[class*='priceContainer']",
      "h3",
      "strong"
    ]

    price_text = find_price_text_in_selectors(document, selectors)

    if price_text do
      ExtractionHelpers.parse_price(price_text)
    else
      full_text = Floki.text(document)
      ExtractionHelpers.extract_price_from_full_text(full_text)
    end
  end

  # Price extraction for Otodom detail pages using shared helpers
  defp extract_otodom_price(document) do
    selectors = [
      "strong[data-cy='ad.top-information.price']",
      "[data-cy='ad.top-information.price']",
      "strong[aria-label*='Cena']",
      "div[aria-label*='Cena']",
      "strong[class*='Price']",
      "div[class*='price'] strong",
      "div[class*='Price'] strong",
      "[class*='priceInfo'] strong",
      "strong",
      "h3"
    ]

    price_text = find_price_text_in_selectors(document, selectors)

    if price_text do
      ExtractionHelpers.parse_price(price_text)
    else
      full_text = Floki.text(document)
      ExtractionHelpers.extract_price_from_full_text(full_text)
    end
  end

  defp find_price_text_in_selectors(document, selectors) do
    Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) |> Floki.text() do
        "" -> nil
        text ->
          if String.match?(text, ~r/\d+.*(?:zł|PLN)/i), do: text, else: nil
      end
    end)
  end

  # Area extraction using shared helpers
  defp extract_olx_area(document) do
    text = Floki.text(document)
    ExtractionHelpers.extract_area_from_text(text)
  end

  defp extract_otodom_area(document) do
    text = Floki.text(document)
    ExtractionHelpers.extract_area_from_text(text)
  end

  # Rooms extraction using shared helpers
  defp extract_olx_rooms(document) do
    text = Floki.text(document)
    ExtractionHelpers.extract_rooms_from_text(text)
  end

  defp extract_otodom_rooms(document) do
    text = Floki.text(document)
    ExtractionHelpers.extract_rooms_from_text(text)
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

