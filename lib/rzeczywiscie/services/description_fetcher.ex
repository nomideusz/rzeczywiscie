defmodule Rzeczywiscie.Services.DescriptionFetcher do
  @moduledoc """
  Fetches full property descriptions from source URLs.
  Used for top deals to get more signal for LLM analysis.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.DealScorer

  @doc """
  Fetch descriptions for top deals.
  
  Options:
    * `:limit` - Number of top deals to process (default: 50)
    * `:delay` - Delay between requests in ms (default: 2000)
    * `:min_score` - Minimum deal score to consider (default: 40)
  """
  def fetch_top_deals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    delay = Keyword.get(opts, :delay, 2000)
    min_score = Keyword.get(opts, :min_score, 40)

    Logger.info("Fetching descriptions for top #{limit} deals (min score: #{min_score})")

    # Get top deals that don't have descriptions yet
    deals = DealScorer.get_hot_deals(limit: limit * 2, min_score: min_score)
    
    # Filter to only those without descriptions
    deals_needing_desc = deals
    |> Enum.filter(fn {property, _score_data} -> 
      is_nil(property.description) or String.length(property.description || "") < 100
    end)
    |> Enum.take(limit)

    Logger.info("Found #{length(deals_needing_desc)} deals needing descriptions")

    if length(deals_needing_desc) == 0 do
      {:ok, %{total: 0, fetched: 0, failed: 0}}
    else
      results = 
        deals_needing_desc
        |> Enum.with_index(1)
        |> Enum.map(fn {{property, _score_data}, index} ->
          Logger.info("[#{index}/#{length(deals_needing_desc)}] Fetching description for ##{property.id}")
          
          result = fetch_description(property)
          
          # Add delay between requests
          if index < length(deals_needing_desc), do: Process.sleep(delay)
          
          result
        end)

      fetched = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("✓ Fetch completed: #{fetched} fetched, #{failed} failed")
      
      {:ok, %{total: length(deals_needing_desc), fetched: fetched, failed: failed}}
    end
  end

  @doc """
  Fetch description for a single property.
  """
  def fetch_description(property) do
    case property.source do
      "olx" -> fetch_olx_description(property)
      "otodom" -> fetch_otodom_description(property)
      _ -> {:error, :unsupported_source}
    end
  end

  defp fetch_olx_description(property) do
    case fetch_page(property.url) do
      {:ok, html} ->
        document = Floki.parse_document!(html)
        description = extract_olx_description(document)
        
        if description && String.length(description) > 50 do
          update_description(property, description)
        else
          Logger.warning("No substantial description found for OLX property ##{property.id}")
          {:error, :no_description}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch OLX page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_otodom_description(property) do
    case fetch_page(property.url) do
      {:ok, html} ->
        document = Floki.parse_document!(html)
        description = extract_otodom_description(document)
        
        if description && String.length(description) > 50 do
          update_description(property, description)
        else
          Logger.warning("No substantial description found for Otodom property ##{property.id}")
          {:error, :no_description}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch Otodom page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_page(url) do
    headers = [
      {"user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
      {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"accept-language", "pl,en-US;q=0.7,en;q=0.3"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # OLX description extraction
  defp extract_olx_description(document) do
    # OLX stores description in a div with data-cy="ad_description"
    selectors = [
      "[data-cy='ad_description']",
      "[data-testid='ad-description']",
      "div[class*='descriptionContent']",
      "div[class*='description-content']",
      "div[class*='css-'] > div > p",
      "section[data-testid='ad-description-section']"
    ]
    
    description = Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        elements -> 
          text = elements
          |> Floki.text()
          |> String.trim()
          |> clean_description()
          
          if String.length(text) > 50, do: text, else: nil
      end
    end)
    
    # Fallback: try to find any large text block
    description || find_largest_text_block(document)
  end

  # Otodom description extraction
  defp extract_otodom_description(document) do
    # Otodom stores description in a specific section
    selectors = [
      "[data-cy='adPageDescription']",
      "[data-testid='content.description']",
      "div[class*='Description'] p",
      "section[class*='description']",
      "[class*='description-wrapper']",
      "div[class*='css-'] section p"
    ]
    
    description = Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        elements -> 
          text = elements
          |> Floki.text()
          |> String.trim()
          |> clean_description()
          
          if String.length(text) > 50, do: text, else: nil
      end
    end)
    
    # Fallback: try to find any large text block
    description || find_largest_text_block(document)
  end

  # Find the largest text block on the page (likely the description)
  defp find_largest_text_block(document) do
    # Look for <p> tags with substantial content
    paragraphs = document
    |> Floki.find("p, div.description, div[class*='desc']")
    |> Enum.map(fn elem -> 
      text = Floki.text(elem) |> String.trim() |> clean_description()
      {String.length(text), text}
    end)
    |> Enum.filter(fn {len, _} -> len > 100 end)
    |> Enum.sort_by(fn {len, _} -> -len end)
    
    case paragraphs do
      [{_, text} | _] -> text
      [] -> nil
    end
  end

  defp clean_description(text) do
    text
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.replace(~r/[\r\n]+/, "\n")  # Normalize newlines
    |> String.trim()
    |> String.slice(0, 5000)  # Limit to 5000 chars
  end

  defp update_description(property, description) do
    # Reload the full property to get changeset
    full_property = RealEstate.get_property(property.id)
    
    case RealEstate.update_property(full_property, %{description: description}) do
      {:ok, updated} ->
        Logger.info("✓ Updated description for ##{property.id} (#{String.length(description)} chars)")
        {:ok, updated}
      {:error, changeset} ->
        Logger.error("✗ Failed to update description for ##{property.id}: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
end

