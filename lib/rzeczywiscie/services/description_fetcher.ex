defmodule Rzeczywiscie.Services.DescriptionFetcher do
  @moduledoc """
  Fetches full property descriptions from source URLs.
  Used for top deals to get more signal for LLM analysis.
  """

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.DealScorer
  alias Rzeczywiscie.Scrapers.ExtractionHelpers

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
    
    # Filter to properties without descriptions
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
  Fetch description for a single property from OLX or Otodom.
  """
  def fetch_description(property) do
    case property.source do
      "olx" -> fetch_olx_description(property)
      "otodom" -> fetch_otodom_description(property)
      _ -> {:error, :unsupported_source}
    end
  end

  defp fetch_olx_description(property) do
    case ExtractionHelpers.fetch_olx_description(property.url) do
      {:ok, description} when is_binary(description) and description != "" ->
        # Check if description looks like archived/unavailable message
        if String.contains?(description, ["nie istnieje", "zakończone", "nieaktualna"]) do
          Logger.info("  OLX listing is archived, marking inactive")
          RealEstate.update_property(property, %{active: false})
          {:error, :listing_archived}
        else
          if String.length(description) > 50 do
            update_description(property, description)
          else
            Logger.warning("No substantial description found for OLX property ##{property.id}")
            {:error, :no_description}
          end
        end

      {:ok, nil} ->
        Logger.warning("No description found for OLX property ##{property.id}")
        {:error, :no_description}

      {:error, reason} ->
        Logger.error("Failed to fetch OLX page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_otodom_description(property) do
    case ExtractionHelpers.fetch_otodom_description(property.url) do
      {:ok, description} when is_binary(description) and description != "" ->
        # Check if description looks like archived/unavailable message
        if String.contains?(description, ["niedostępne", "nieaktualna"]) do
          Logger.info("  Otodom listing is archived, marking inactive")
          RealEstate.update_property(property, %{active: false})
          {:error, :listing_archived}
        else
          if String.length(description) > 50 do
            update_description(property, description)
          else
            Logger.warning("No substantial description found for Otodom property ##{property.id}")
            {:error, :no_description}
          end
        end

      {:ok, nil} ->
        Logger.warning("No description found for Otodom property ##{property.id}")
        {:error, :no_description}

      {:error, reason} ->
        Logger.error("Failed to fetch Otodom page: #{inspect(reason)}")
        {:error, reason}
    end
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

