defmodule Rzeczywiscie.RealEstate.DealScorer do
  @moduledoc """
  Scores properties to identify "hot deals" based on various factors:
  - Price vs district average
  - Price per sqm vs district average
  - Recent price drops
  - Urgency keywords in title/description
  - Days on market
  
  Filters out non-residential property types and validates data quality.
  """
  
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.{Property, PriceHistory}
  
  require Logger

  # Property types to EXCLUDE from hot deals (non-residential)
  # These are filtered both in the query and in validation
  @excluded_types ~w(działka garaż magazyn hala blaszak boks kontener biuro lokal)
  
  # Price thresholds by transaction type (PLN)
  # Below these values, the listing is likely an error or non-standard
  @min_price_sale 30_000      # Minimum 30k for sale
  @min_price_rent 200         # Minimum 200 PLN/month for rent
  @max_price_rent 50_000      # Max 50k/month for rent (above = likely sale)
  
  # Area thresholds (m²) - properties outside these ranges are likely misclassified
  @max_area_apartment 300     # Apartments rarely exceed 300m²
  @max_area_room 50           # Rooms rarely exceed 50m²
  @min_area_house 30          # Houses are at least 30m²
  @max_area_house 1000        # Houses rarely exceed 1000m² (above = likely plot)

  @doc """
  Score a single property and return a map with scores breakdown.
  Returns nil if the property fails validation checks.
  """
  def score_property(%Property{} = property, market_context \\ nil) do
    # Validate property data quality first
    if valid_for_scoring?(property) do
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
    else
      nil
    end
  end
  
  @doc """
  Check if a property passes data quality validation for scoring.
  """
  def valid_for_scoring?(%Property{} = p) do
    valid_property_type?(p) and
    valid_price_range?(p) and
    valid_area_range?(p)
  end
  
  # Check if property type is suitable for hot deals (residential focus)
  defp valid_property_type?(%Property{property_type: nil}), do: false
  defp valid_property_type?(%Property{property_type: type, title: title}) do
    type_lower = String.downcase(type)
    title_lower = String.downcase(title || "")
    
    # Exclude if type is in excluded list
    excluded = Enum.any?(@excluded_types, fn excluded_type ->
      String.contains?(type_lower, excluded_type) or
      String.contains?(title_lower, excluded_type)
    end)
    
    not excluded
  end
  
  # Check if price is within reasonable range for the transaction type
  defp valid_price_range?(%Property{price: nil}), do: false
  defp valid_price_range?(%Property{price: price, transaction_type: "sprzedaż"}) do
    price_float = Decimal.to_float(price)
    price_float >= @min_price_sale
  end
  defp valid_price_range?(%Property{price: price, transaction_type: "wynajem"}) do
    price_float = Decimal.to_float(price)
    price_float >= @min_price_rent and price_float <= @max_price_rent
  end
  defp valid_price_range?(_), do: true
  
  # Check if area is within reasonable range for the property type
  defp valid_area_range?(%Property{area_sqm: nil}), do: true  # Allow missing area
  defp valid_area_range?(%Property{area_sqm: area, property_type: type}) when not is_nil(type) do
    area_float = Decimal.to_float(area)
    type_lower = String.downcase(type)
    
    cond do
      String.contains?(type_lower, "mieszkanie") or String.contains?(type_lower, "apartament") ->
        area_float > 0 and area_float <= @max_area_apartment
      String.contains?(type_lower, "pokój") or String.contains?(type_lower, "kawalerka") ->
        area_float > 0 and area_float <= @max_area_room
      String.contains?(type_lower, "dom") ->
        area_float >= @min_area_house and area_float <= @max_area_house
      true ->
        area_float > 0 and area_float <= 500  # Default reasonable max
    end
  end
  defp valid_area_range?(_), do: true

  @doc """
  Get top hot deals - properties with highest scores.
  
  Options:
  - :limit - max results (default 50)
  - :transaction_type - "sprzedaż" or "wynajem"
  - :property_type - filter by type
  - :min_score - minimum score threshold (default 20)
  - :include_all_types - if true, include non-residential (default false)
  """
  def get_hot_deals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    transaction_type = Keyword.get(opts, :transaction_type)
    property_type = Keyword.get(opts, :property_type)
    min_score = Keyword.get(opts, :min_score, 20)
    include_all_types = Keyword.get(opts, :include_all_types, false)
    
    # Get active properties with price and complete type info
    base_query = from p in Property,
      where: p.active == true and 
             not is_nil(p.price) and
             not is_nil(p.property_type) and
             not is_nil(p.transaction_type)
    
    # Apply transaction type filter
    base_query = if transaction_type do
      where(base_query, [p], p.transaction_type == ^transaction_type)
    else
      base_query
    end
    
    # Apply property type filter
    base_query = if property_type do
      where(base_query, [p], p.property_type == ^property_type)
    else
      base_query
    end
    
    # Exclude non-residential types unless explicitly requested
    base_query = unless include_all_types do
      # Exclude działka, garaż, magazyn, etc. by checking type and title
      excluded_pattern = "%działk%" 
      base_query
      |> where([p], not ilike(p.property_type, ^excluded_pattern))
      |> where([p], not ilike(p.property_type, "%garaż%"))
      |> where([p], not ilike(p.property_type, "%magazyn%"))
      |> where([p], not ilike(p.property_type, "%hala%"))
      |> where([p], not ilike(p.property_type, "%blaszak%"))
      |> where([p], not ilike(p.property_type, "%boks%"))
      |> where([p], not ilike(p.property_type, "%kontener%"))
      |> where([p], not ilike(p.property_type, "%biuro%"))
      |> where([p], not ilike(p.property_type, "%lokal%"))
      |> where([p], not ilike(p.title, "%działk%"))
      |> where([p], not ilike(p.title, "%garaż%"))
      |> where([p], not ilike(p.title, "%magazyn%"))
      |> where([p], not ilike(p.title, "%blaszak%"))
    else
      base_query
    end
    
    # Get all matching properties
    properties = Repo.all(base_query)
    
    # Calculate market context once per district/type combo
    context_cache = build_context_cache(properties)
    
    # Score all properties (score_property returns nil for invalid properties)
    scored = properties
    |> Enum.map(fn p -> 
      context = Map.get(context_cache, {p.district, p.property_type, p.transaction_type})
      {p, score_property(p, context)}
    end)
    |> Enum.reject(fn {_p, score} -> is_nil(score) end)  # Remove invalid properties
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
    
    # Use proper minimum prices by transaction type
    # For price drops, we need current price to be reasonable
    min_rent_price = Decimal.new(@min_price_rent)  # 200 PLN
    min_sale_price = Decimal.new(@min_price_sale)  # 30,000 PLN
    min_history_price = Decimal.new("500")  # History price should also be reasonable
    
    from(ph in PriceHistory,
      join: p in Property,
      on: ph.property_id == p.id,
      where: p.active == true and 
             not is_nil(p.price) and
             not is_nil(p.transaction_type) and
             # Current price must meet minimum for transaction type
             ((p.transaction_type == "wynajem" and p.price >= ^min_rent_price) or
              (p.transaction_type == "sprzedaż" and p.price >= ^min_sale_price) or
              (p.transaction_type not in ["wynajem", "sprzedaż"] and p.price >= ^min_history_price)) and
             # History price should also be reasonable
             ph.price >= ^min_history_price and
             ph.detected_at >= ^cutoff and 
             ph.change_percentage < 0 and
             ph.change_percentage > -70,  # Tighter filter: drops > 70% are likely errors
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
    # Base price thresholds to exclude outliers from market averages
    {min_price, max_price} = case transaction_type do
      "sprzedaż" -> {Decimal.new(@min_price_sale), Decimal.new("50000000")}  # 30k - 50M
      "wynajem" -> {Decimal.new(@min_price_rent), Decimal.new(@max_price_rent)}  # 200 - 50k
      _ -> {Decimal.new("100"), Decimal.new("50000000")}
    end
    
    query = from p in Property,
      where: p.active == true and 
             not is_nil(p.price) and
             p.price >= ^min_price and
             p.price <= ^max_price
    
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
    
    # Also filter out non-residential from context calculation
    query = query
    |> where([p], not ilike(p.property_type, "%działk%"))
    |> where([p], not ilike(p.property_type, "%garaż%"))
    |> where([p], not ilike(p.property_type, "%magazyn%"))
    |> where([p], not ilike(p.title, "%działk%"))
    
    stats = from(p in query,
      select: %{
        count: count(p.id),
        avg_price: avg(p.price),
        min_price: min(p.price),
        max_price: max(p.price)
      }
    )
    |> Repo.one()
    
    # Calculate avg price per sqm (with reasonable area bounds)
    sqm_stats = from(p in query,
      where: not is_nil(p.area_sqm) and p.area_sqm > 5 and p.area_sqm < 500,
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

  defp score_price_drop(%Property{id: property_id, price: current_price}) do
    # Get full price history for trend analysis
    history = from(ph in PriceHistory,
      where: ph.property_id == ^property_id,
      order_by: [asc: ph.detected_at]
    )
    |> Repo.all()
    
    case history do
      [] -> 0
      entries ->
        # Analyze the full price history
        analyze_price_history(entries, current_price)
    end
  end
  
  defp analyze_price_history(history, current_price) when is_list(history) do
    # Count price drops (negative change_percentage)
    drop_count = Enum.count(history, fn h -> 
      h.change_percentage && Decimal.compare(h.change_percentage, Decimal.new("0")) == :lt
    end)
    
    # Get the original (first) price
    original_price = case List.first(history) do
      %{price: price} when not is_nil(price) -> price
      _ -> nil
    end
    
    # Calculate total drop from original to current
    total_drop_pct = if original_price && current_price do
      orig = Decimal.to_float(original_price)
      curr = Decimal.to_float(current_price)
      if orig > 0 do
        ((orig - curr) / orig) * 100
      else
        0
      end
    else
      0
    end
    
    # Check for recent activity (drop in last 14 days)
    recent_cutoff = DateTime.utc_now() |> DateTime.add(-14 * 24 * 3600, :second)
    has_recent_drop = Enum.any?(history, fn h ->
      h.change_percentage && 
      Decimal.compare(h.change_percentage, Decimal.new("0")) == :lt &&
      DateTime.compare(h.detected_at, recent_cutoff) == :gt
    end)
    
    # Score components:
    # 1. Multiple drops bonus (motivated seller): 0-10 pts
    drop_count_score = case drop_count do
      0 -> 0
      1 -> 3
      2 -> 6
      3 -> 8
      _ -> 10  # 4+ drops = very motivated
    end
    
    # 2. Total drop from original: 0-15 pts
    total_drop_score = cond do
      total_drop_pct >= 30 -> 15  # 30%+ total drop = desperate
      total_drop_pct >= 25 -> 12
      total_drop_pct >= 20 -> 10
      total_drop_pct >= 15 -> 8
      total_drop_pct >= 10 -> 6
      total_drop_pct >= 5 -> 4
      total_drop_pct > 0 -> 2
      true -> 0
    end
    
    # 3. Recent drop bonus: 0-5 pts
    recent_drop_score = if has_recent_drop, do: 5, else: 0
    
    # Total: max 30 pts (increased from 25 to reflect importance)
    drop_count_score + total_drop_score + recent_drop_score
  end

  # Strong urgency signals (rare, high intent)
  @strong_urgency_keywords ~w(
    pilne pilna pilnie musi się sprzedać likwidacja
    wyjazd za granicę przeprowadzka szybka sprzedaż
    poniżej rynku poniżej ceny rynkowej
  )
  
  # Moderate urgency signals (somewhat common)
  @moderate_urgency_keywords ~w(
    okazja okazyjna obniżka obniżona cena nowa cena
    negocjuj negocjacja do negocjacji
  )
  
  # NOTE: Removed very common marketing phrases that appear in most listings:
  # "bezpośrednio", "bez prowizji", "bez pośredników" - too common, not urgency
  # "super cena", "wyjątkowa oferta", "promocja" - generic marketing

  defp score_urgency_keywords(%Property{title: title, description: desc}) do
    text = String.downcase("#{title} #{desc || ""}")
    
    strong_matches = @strong_urgency_keywords
    |> Enum.count(fn keyword -> String.contains?(text, keyword) end)
    
    moderate_matches = @moderate_urgency_keywords
    |> Enum.count(fn keyword -> String.contains?(text, keyword) end)
    
    # Max 10 points (reduced from 15)
    cond do
      strong_matches >= 2 -> 10  # Multiple strong signals
      strong_matches >= 1 -> 8   # One strong signal
      moderate_matches >= 3 -> 6 # Multiple moderate signals
      moderate_matches >= 1 -> 3 # One moderate signal
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

