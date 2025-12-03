defmodule Rzeczywiscie.Workers.LLMAnalysisWorker do
  @moduledoc """
  Oban worker for automated LLM property analysis.
  
  Runs the full analysis workflow automatically:
  1. Fetch descriptions for top-scored properties missing them
  2. Run LLM analysis on properties with descriptions
  
  Scheduled to run every 6 hours via cron.
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 2,
    priority: 2

  require Logger
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, "limit", 30)
    
    Logger.info("🤖 LLM Analysis Worker starting (limit: #{limit})")
    
    # Check if API key is configured
    api_key = Application.get_env(:rzeczywiscie, :openai_api_key, "")
    if api_key == "" do
      Logger.warning("⚠️ LLM Analysis skipped: OpenAI API key not configured")
      :ok
    else
      # Step 1: Fetch descriptions for properties that need them
      fetch_result = fetch_descriptions(limit)
      Logger.info("📝 Description fetch: #{fetch_result}")
      
      # Small delay between steps
      Process.sleep(2000)
      
      # Step 2: Run LLM analysis on properties with descriptions
      llm_result = run_llm_analysis(limit)
      Logger.info("🤖 LLM analysis: #{llm_result}")
      
      :ok
    end
  end

  defp fetch_descriptions(limit) do
    alias Rzeczywiscie.Services.DescriptionFetcher
    
    case DescriptionFetcher.fetch_top_deals(limit: limit, delay: 2500) do
      {:ok, %{total: total, fetched: fetched, failed: failed}} ->
        "#{fetched}/#{total} fetched (#{failed} failed)"
      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  defp run_llm_analysis(limit) do
    alias Rzeczywiscie.Services.LLMAnalyzer
    alias Rzeczywiscie.Scrapers.ExtractionHelpers
    
    # Get properties with descriptions pending analysis
    all_properties = from(p in Property,
      where: p.active == true and 
             not is_nil(p.description) and 
             fragment("length(?)", p.description) > 50 and
             is_nil(p.llm_analyzed_at),
      order_by: [desc: p.inserted_at],
      limit: ^(limit * 2)  # Fetch more, filter garbage
    )
    |> Repo.all()
    
    # Categorize properties by description type
    {css_garbage, rest} = Enum.split_with(all_properties, fn p ->
      ExtractionHelpers.is_css_content?(p.description) or 
      ExtractionHelpers.is_navigation_content?(p.description)
    end)
    
    {metadata_only, valid_properties} = Enum.split_with(rest, fn p ->
      ExtractionHelpers.is_otodom_metadata?(p.description)
    end)
    
    # Mark CSS/navigation garbage as analyzed
    Enum.each(css_garbage, fn p ->
      RealEstate.update_property(p, %{
        llm_analyzed_at: DateTime.utc_now(),
        llm_score: 0,
        llm_summary: "Skipped: description contains CSS/navigation garbage"
      })
    end)
    
    # Process Otodom metadata - extract useful fields without LLM
    metadata_count = Enum.reduce(metadata_only, 0, fn p, acc ->
      metadata = ExtractionHelpers.parse_otodom_metadata(p.description)
      updates = build_metadata_updates(metadata)
      
      case RealEstate.update_property(p, updates) do
        {:ok, _} -> 
          Logger.info("  📋 Property ##{p.id} - extracted metadata (no real description)")
          acc + 1
        {:error, _} -> acc
      end
    end)
    
    properties = Enum.take(valid_properties, limit)
    total = length(properties)
    
    if total == 0 and metadata_count == 0 do
      "No properties pending analysis (#{length(css_garbage)} garbage skipped)"
    else
      successful = properties
      |> Enum.with_index(1)
      |> Enum.reduce(0, fn {property, idx}, count ->
        Logger.info("[#{idx}/#{total}] Analyzing property ##{property.id}...")
        
        context = build_context(property)
        
        case analyze_with_timeout(property.description, context) do
          {:ok, signals} ->
            signals = enhance_with_prefab_detection(signals, property)
            save_analysis(property, signals)
            count + 1
            
          {:error, reason} ->
            Logger.warning("  ✗ Failed: #{inspect(reason)}")
            count
        end
      end)
      
      result = "#{successful}/#{total} analyzed"
      result = if metadata_count > 0, do: result <> ", #{metadata_count} metadata-only", else: result
      result = if length(css_garbage) > 0, do: result <> ", #{length(css_garbage)} garbage skipped", else: result
      result
    end
  end
  
  # Build updates from parsed Otodom metadata
  defp build_metadata_updates(metadata) do
    base = %{
      llm_analyzed_at: DateTime.utc_now(),
      llm_score: 3,  # Neutral score - can't assess deal quality without real description
      llm_summary: "Tylko metadane - brak pełnego opisu nieruchomości",
      llm_listing_quality: 2  # Low quality - metadata only
    }
    
    base
    |> maybe_add_metadata(:llm_monthly_fee, metadata[:monthly_fee])
    |> maybe_add_metadata(:llm_floor_info, metadata[:floor_info])
    |> maybe_add_metadata(:llm_is_agency, metadata[:is_agency])
  end
  
  defp maybe_add_metadata(updates, _key, nil), do: updates
  defp maybe_add_metadata(updates, key, value), do: Map.put(updates, key, value)

  defp build_context(property) do
    alias Rzeczywiscie.RealEstate.DealScorer
    
    market_avg = case DealScorer.get_district_quality(property.district, property.transaction_type) do
      %{avg_price_sqm: avg} when not is_nil(avg) -> avg
      _ -> nil
    end
    
    %{
      price: property.price && Decimal.to_float(property.price),
      area: property.area_sqm && Decimal.to_float(property.area_sqm),
      district: property.district,
      city: property.city,
      rooms: property.rooms,
      market_avg_price_per_sqm: market_avg,
      transaction_type: property.transaction_type || "sprzedaż"
    }
  end

  defp analyze_with_timeout(description, context) do
    alias Rzeczywiscie.Services.LLMAnalyzer
    
    task = Task.async(fn ->
      LLMAnalyzer.analyze_description_with_context(description, context)
    end)
    
    case Task.yield(task, 35_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp enhance_with_prefab_detection(signals, property) do
    alias Rzeczywiscie.Services.LLMAnalyzer
    
    is_prefab = LLMAnalyzer.is_prefab_house?(property.title) || 
                LLMAnalyzer.is_prefab_house?(property.description || "")
    
    if is_prefab do
      red_flags = ["Dom prefabrykowany - produkt, nie nieruchomość" | (signals.red_flags || [])]
      inv_score = min(signals[:investment_score] || 5, 2)
      signals
      |> Map.put(:red_flags, red_flags)
      |> Map.put(:investment_score, inv_score)
    else
      signals
    end
  end

  defp save_analysis(property, signals) do
    alias Rzeczywiscie.Services.LLMAnalyzer
    
    # Base LLM analysis updates
    updates = %{
      llm_urgency: signals.urgency,
      llm_condition: atom_to_string(signals.condition),
      llm_motivation: atom_to_string(signals.seller_motivation),
      llm_positive_signals: signals.positive_signals || [],
      llm_red_flags: signals.red_flags || [],
      llm_score: LLMAnalyzer.calculate_signal_score(signals),
      llm_analyzed_at: DateTime.utc_now(),
      llm_investment_score: signals[:investment_score],
      llm_summary: signals[:summary],
      llm_hidden_costs: signals[:hidden_costs] || [],
      llm_negotiation_hints: signals[:negotiation_hints] || [],
      llm_monthly_fee: signals[:monthly_fee],
      llm_year_built: signals[:year_built],
      llm_floor_info: signals[:floor_info],
      # Data quality fields
      llm_data_issues: signals[:data_issues] || [],
      llm_listing_quality: signals[:listing_quality],
      llm_is_agency: signals[:is_agency]
    }
    
    # Add street if LLM extracted it and property doesn't already have one
    updates = if signals[:street] && (is_nil(property.street) || property.street == "") do
      Map.put(updates, :street, signals[:street])
    else
      updates
    end
    
    # Apply corrected area if LLM found error and current area looks wrong
    updates = if signals[:corrected_area] && is_number(signals[:corrected_area]) do
      current_area = property.area_sqm && Decimal.to_float(property.area_sqm)
      # Only correct if current area is suspiciously different (10x or more)
      if current_area && (current_area > signals[:corrected_area] * 10 || current_area < signals[:corrected_area] / 10) do
        Logger.info("  📐 Correcting area: #{current_area} → #{signals[:corrected_area]} m²")
        Map.put(updates, :area_sqm, Decimal.from_float(signals[:corrected_area] * 1.0))
      else
        updates
      end
    else
      updates
    end
    
    # Apply corrected rooms if LLM found error
    updates = if signals[:corrected_rooms] && is_integer(signals[:corrected_rooms]) do
      if property.rooms != signals[:corrected_rooms] do
        Logger.info("  🚪 Correcting rooms: #{property.rooms} → #{signals[:corrected_rooms]}")
        Map.put(updates, :rooms, signals[:corrected_rooms])
      else
        updates
      end
    else
      updates
    end
    
    # Apply corrected transaction type if LLM found error
    updates = if signals[:corrected_transaction_type] && signals[:corrected_transaction_type] in ["sprzedaż", "wynajem"] do
      if property.transaction_type != signals[:corrected_transaction_type] do
        Logger.info("  💰 Correcting transaction: #{property.transaction_type} → #{signals[:corrected_transaction_type]}")
        Map.put(updates, :transaction_type, signals[:corrected_transaction_type])
      else
        updates
      end
    else
      updates
    end
    
    # Extract city if missing and LLM found it
    updates = if signals[:extracted_city] && (is_nil(property.city) || property.city == "") do
      Logger.info("  📍 Extracted city: #{signals[:extracted_city]}")
      Map.put(updates, :city, signals[:extracted_city])
    else
      updates
    end
    
    # Extract district if missing and LLM found it
    updates = if signals[:extracted_district] && (is_nil(property.district) || property.district == "") do
      Logger.info("  📍 Extracted district: #{signals[:extracted_district]}")
      Map.put(updates, :district, signals[:extracted_district])
    else
      updates
    end
    
    case RealEstate.update_property(property, updates) do
      {:ok, _} ->
        extras = []
        extras = if signals[:street], do: ["street: #{signals[:street]}" | extras], else: extras
        extras = if signals[:data_issues] && length(signals[:data_issues]) > 0, do: ["#{length(signals[:data_issues])} issues" | extras], else: extras
        extras = if signals[:is_agency] == true, do: ["agency" | extras], else: extras
        extras_str = if length(extras) > 0, do: ", #{Enum.join(extras, ", ")}", else: ""
        Logger.info("  ✓ Property ##{property.id} analyzed (inv: #{signals[:investment_score] || "?"}/10, quality: #{signals[:listing_quality] || "?"}#{extras_str})")
        :ok
      {:error, changeset} ->
        Logger.error("  ✗ Failed to save: #{inspect(changeset.errors)}")
        :error
    end
    
    # Rate limit
    Process.sleep(500)
  end

  defp atom_to_string(val) when is_atom(val), do: Atom.to_string(val)
  defp atom_to_string(val) when is_binary(val), do: val
  defp atom_to_string(_), do: "unknown"

  @doc """
  Manually trigger the LLM analysis job.
  """
  def trigger(opts \\ []) do
    %{"limit" => Keyword.get(opts, :limit, 30)}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end

