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
  # DISABLED - fallback was grabbing CSS/JS content
  defp find_largest_text_block(_document) do
    nil
  end

  defp clean_description(text) do
    cleaned = text
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.replace(~r/[\r\n]+/, "\n")  # Normalize newlines
    |> String.trim()
    |> String.slice(0, 5000)  # Limit to 5000 chars
    
    # Validate the description is actual content, not CSS/JS/garbage
    if is_valid_description?(cleaned), do: cleaned, else: nil
  end
  
  # Check if text looks like a real description (not CSS, JS, or garbage)
  defp is_valid_description?(text) when is_binary(text) do
    cond do
      # Too short
      String.length(text) < 50 -> false
      
      # Contains CSS patterns
      String.contains?(text, [".css-", "{color:", "{font-", "font-weight:", "text-align:", "line-height:"]) -> false
      
      # Contains JS patterns  
      String.contains?(text, ["function(", "var ", "const ", "let ", "=>"]) -> false
      
      # Contains HTML tags or entities
      String.match?(text, ~r/<[a-z]+|&[a-z]+;/) -> false
      
      # Too many special characters (likely code/garbage)
      special_char_ratio(text) > 0.15 -> false
      
      # Contains mostly non-Polish characters
      polish_char_ratio(text) < 0.7 -> false
      
      # Looks valid
      true -> true
    end
  end
  defp is_valid_description?(_), do: false
  
  # Calculate ratio of special characters ({};:=) to total length
  defp special_char_ratio(text) do
    special_count = text
    |> String.graphemes()
    |> Enum.count(&(&1 in ["{", "}", ";", ":", "=", "<", ">", "(", ")"]))
    
    special_count / max(String.length(text), 1)
  end
  
  # Calculate ratio of Polish/Latin characters to total
  defp polish_char_ratio(text) do
    # Polish letters + common punctuation + spaces
    polish_pattern = ~r/[a-zA-ZąćęłńóśźżĄĆĘŁŃÓŚŹŻ0-9\s.,!?;:\-–—'"„""]/
    
    polish_count = text
    |> String.graphemes()
    |> Enum.count(&Regex.match?(polish_pattern, &1))
    
    polish_count / max(String.length(text), 1)
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

