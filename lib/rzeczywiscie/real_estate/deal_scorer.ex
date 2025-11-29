defmodule Rzeczywiscie.RealEstate.DealScorer do
  @moduledoc """
  Scores properties to identify "hot deals" based on various factors:
  - Price vs district average
  - Price per sqm vs district average
  - Recent price drops
  - Urgency keywords in title/description
  - Days on market
  """
  
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.{Property, PriceHistory}
  
  require Logger

  @doc """
  Score a single property and return a map with scores breakdown.
  """
  def score_property(%Property{} = property, market_context \\ nil) do
    context = market_context || get_market_context(property)
    
    scores = %{
      price_vs_avg: score_price_vs_avg(property, context),
      price_per_sqm: score_price_per_sqm(property, context),
      price_drop: score_price_drop(property),
      urgency_keywords: score_urgency_keywords(property),
      days_on_market: score_days_on_market(property)
    }
    
    total = Enum.reduce(scores, 0, fn {_k, v}, acc -> acc + v end)
    
    %{
      property_id: property.id,
      scores: scores,
      total_score: total,
      market_context: context
    }
  end

  @doc """
  Get top hot deals - properties with highest scores.
  """
  def get_hot_deals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    transaction_type = Keyword.get(opts, :transaction_type)
    property_type = Keyword.get(opts, :property_type)
    min_score = Keyword.get(opts, :min_score, 20)
    
    # Get active properties with price and complete type info
    base_query = from p in Property,
      where: p.active == true and 
             not is_nil(p.price) and
             not is_nil(p.property_type) and
             not is_nil(p.transaction_type)
    
    # Apply filters
    base_query = if transaction_type do
      where(base_query, [p], p.transaction_type == ^transaction_type)
    else
      base_query
    end
    
    base_query = if property_type do
      where(base_query, [p], p.property_type == ^property_type)
    else
      base_query
    end
    
    # Get all matching properties
    properties = Repo.all(base_query)
    
    # Calculate market context once per district/type combo
    context_cache = build_context_cache(properties)
    
    # Score all properties
    scored = properties
    |> Enum.map(fn p -> 
      context = Map.get(context_cache, {p.district, p.property_type, p.transaction_type})
      {p, score_property(p, context)}
    end)
    |> Enum.filter(fn {_p, score} -> score.total_score >= min_score end)
    |> Enum.sort_by(fn {_p, score} -> score.total_score end, :desc)
    |> Enum.take(limit)
    
    scored
  end

  @doc """
  Get properties with recent price drops.
  Filters out:
  - Properties with nil current price
  - Price history entries with price < 100 PLN (extraction errors)
  - Price drops > 90% (likely data errors, not real drops)
  """
  def get_price_drops(days \\ 7, limit \\ 20) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 3600, :second)
    min_valid_price = Decimal.new("100")
    
    from(ph in PriceHistory,
      join: p in Property,
      on: ph.property_id == p.id,
      where: p.active == true and 
             not is_nil(p.price) and
             p.price >= ^min_valid_price and
             ph.price >= ^min_valid_price and
             ph.detected_at >= ^cutoff and 
             ph.change_percentage < 0 and
             ph.change_percentage > -90,  # Filter out extreme drops (data errors)
      order_by: [asc: ph.change_percentage],
      limit: ^limit,
      select: {p, ph}
    )
    |> Repo.all()
  end

  # Private functions

  defp build_context_cache(properties) do
    properties
    |> Enum.map(fn p -> {p.district, p.property_type, p.transaction_type} end)
    |> Enum.uniq()
    |> Enum.map(fn key -> {key, get_market_context_for_key(key)} end)
    |> Map.new()
  end

  defp get_market_context(%Property{} = property) do
    get_market_context_for_key({property.district, property.property_type, property.transaction_type})
  end

  defp get_market_context_for_key({district, property_type, transaction_type}) do
    query = from p in Property,
      where: p.active == true and not is_nil(p.price)
    
    # Add property type filter if available (handle nil)
    query = if property_type do
      where(query, [p], p.property_type == ^property_type)
    else
      where(query, [p], is_nil(p.property_type))
    end
    
    # Add transaction type filter if available (handle nil)
    query = if transaction_type do
      where(query, [p], p.transaction_type == ^transaction_type)
    else
      where(query, [p], is_nil(p.transaction_type))
    end
    
    # Add district filter if available
    query = if district && district != "" do
      where(query, [p], p.district == ^district)
    else
      query
    end
    
    stats = from(p in query,
      select: %{
        count: count(p.id),
        avg_price: avg(p.price),
        min_price: min(p.price),
        max_price: max(p.price)
      }
    )
    |> Repo.one()
    
    # Calculate avg price per sqm
    sqm_stats = from(p in query,
      where: not is_nil(p.area_sqm) and p.area_sqm > 0,
      select: avg(p.price / p.area_sqm)
    )
    |> Repo.one()
    
    %{
      district: district,
      property_type: property_type,
      transaction_type: transaction_type,
      count: stats.count || 0,
      avg_price: stats.avg_price && Decimal.to_float(stats.avg_price),
      min_price: stats.min_price && Decimal.to_float(stats.min_price),
      max_price: stats.max_price && Decimal.to_float(stats.max_price),
      avg_price_per_sqm: sqm_stats && Decimal.to_float(sqm_stats)
    }
  end

  # Scoring functions - each returns 0-30 points

  defp score_price_vs_avg(%Property{price: price}, _context) when is_nil(price), do: 0
  defp score_price_vs_avg(%Property{price: _price}, %{avg_price: avg}) when is_nil(avg), do: 0
  defp score_price_vs_avg(%Property{price: price}, %{avg_price: avg_price}) do
    price_float = Decimal.to_float(price)
    diff_pct = (avg_price - price_float) / avg_price * 100
    
    cond do
      diff_pct >= 30 -> 30  # 30%+ below average - amazing deal
      diff_pct >= 25 -> 25
      diff_pct >= 20 -> 20
      diff_pct >= 15 -> 15
      diff_pct >= 10 -> 10
      diff_pct >= 5 -> 5
      true -> 0
    end
  end

  defp score_price_per_sqm(%Property{price: price, area_sqm: area}, _context) 
       when is_nil(price) or is_nil(area), do: 0
  defp score_price_per_sqm(%Property{price: _price, area_sqm: _area}, %{avg_price_per_sqm: avg}) 
       when is_nil(avg), do: 0
  defp score_price_per_sqm(%Property{price: price, area_sqm: area}, %{avg_price_per_sqm: avg_sqm}) do
    price_float = Decimal.to_float(price)
    area_float = Decimal.to_float(area)
    
    if area_float > 0 do
      price_per_sqm = price_float / area_float
      diff_pct = (avg_sqm - price_per_sqm) / avg_sqm * 100
      
      cond do
        diff_pct >= 25 -> 25  # 25%+ below avg price/m² - great value
        diff_pct >= 20 -> 20
        diff_pct >= 15 -> 15
        diff_pct >= 10 -> 10
        diff_pct >= 5 -> 5
        true -> 0
      end
    else
      0
    end
  end

  defp score_price_drop(%Property{id: property_id}) do
    # Check for recent price drops (last 14 days)
    cutoff = DateTime.utc_now() |> DateTime.add(-14 * 24 * 3600, :second)
    
    recent_drop = from(ph in PriceHistory,
      where: ph.property_id == ^property_id and 
             ph.detected_at >= ^cutoff and 
             ph.change_percentage < 0,
      order_by: [desc: ph.detected_at],
      limit: 1
    )
    |> Repo.one()
    
    case recent_drop do
      nil -> 0
      %{change_percentage: pct} ->
        drop = Decimal.to_float(pct) |> abs()
        cond do
          drop >= 20 -> 25  # 20%+ drop - huge signal
          drop >= 15 -> 20
          drop >= 10 -> 15
          drop >= 5 -> 10
          true -> 5
        end
    end
  end

  @urgency_keywords ~w(
    okazja pilne pilna szybka sprzedaż szybko tanio taniej promocja 
    negocjuj negocjacja cena do uzgodnienia do negocjacji obniżka 
    obniżona cena nowa cena super cena wyjątkowa oferta okazyjna
    likwidacja przeprowadzka wyjazd za granicę musi się sprzedać
    poniżej rynku poniżej ceny rynkowej dużo taniej
  )

  defp score_urgency_keywords(%Property{title: title, description: desc}) do
    text = String.downcase("#{title} #{desc || ""}")
    
    matches = @urgency_keywords
    |> Enum.count(fn keyword -> String.contains?(text, keyword) end)
    
    cond do
      matches >= 4 -> 15  # Multiple urgency signals
      matches >= 2 -> 10
      matches >= 1 -> 5
      true -> 0
    end
  end

  defp score_days_on_market(%Property{inserted_at: inserted_at}) when is_nil(inserted_at), do: 0
  defp score_days_on_market(%Property{inserted_at: inserted_at}) do
    days = DateTime.diff(DateTime.utc_now(), inserted_at, :day)
    
    cond do
      days >= 60 -> 10  # Long time on market - seller might be motivated
      days >= 30 -> 5
      true -> 0
    end
  end

  @doc """
  Get summary stats for hot deals dashboard.
  """
  def get_hot_deals_summary do
    # Count properties with significant price drops (excluding data errors)
    cutoff = DateTime.utc_now() |> DateTime.add(-7 * 24 * 3600, :second)
    min_valid_price = Decimal.new("100")
    
    price_drops = from(ph in PriceHistory,
      join: p in Property,
      on: ph.property_id == p.id,
      where: p.active == true and 
             not is_nil(p.price) and
             p.price >= ^min_valid_price and
             ph.price >= ^min_valid_price and
             ph.detected_at >= ^cutoff and 
             ph.change_percentage < -5 and
             ph.change_percentage > -90,  # Exclude extreme drops (errors)
      select: count(fragment("DISTINCT ?", p.id))
    )
    |> Repo.one()
    
    # Count properties with valid prices
    below_market = from(p in Property,
      where: p.active == true and 
             not is_nil(p.price) and
             p.price >= ^min_valid_price,
      select: count(p.id)
    )
    |> Repo.one()
    
    %{
      recent_price_drops: price_drops || 0,
      total_active_with_price: below_market || 0
    }
  end
end

