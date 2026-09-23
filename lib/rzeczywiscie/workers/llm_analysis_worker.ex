defmodule Rzeczywiscie.Workers.LLMAnalysisWorker do
  @moduledoc """
  Oban worker for automated LLM property analysis.
  
  Runs the full analysis workflow automatically:
  1. Fetch descriptions for top-scored properties missing them
  2. Ask Jev (Services.Jev) about listings with descriptions; it owns the
     judgment columns (condition, motivation, urgency, red flags for what is
     really on offer)
  3. Run GPT on them for the summary, investment score and extracted numbers

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
  # Admin's "Jev Analysis": step 3 alone, on up to jev_limit listings
  def perform(%Oban.Job{args: %{"jev_only" => true} = args} = job) do
    progress = fn msg -> Rzeczywiscie.JobProgress.report(job, msg) end
    jev_result = run_jev(progress, args["jev_limit"])
    Logger.info("🧪 Jev only: #{jev_result}")
    progress.("done - #{jev_result}")
    :ok
  end

  def perform(%Oban.Job{args: args} = job) do
    limit = Map.get(args, "limit", 30)
    progress = fn step, msg -> Rzeczywiscie.JobProgress.report(job, "step #{step}/3 - " <> msg) end

    Logger.info("🤖 LLM Analysis Worker starting (limit: #{limit})")

    # Step 1: Fetch descriptions for properties that need them
    progress.(1, "fetching descriptions (up to #{limit})")
    fetch_result = fetch_descriptions(limit, &progress.(1, &1))
    Logger.info("📝 Description fetch: #{fetch_result}")

    # Step 2: Jev judges every listing with a description
    jev_result = run_jev(&progress.(2, &1))
    Logger.info("🧪 Jev: #{jev_result}")

    # Step 3: GPT writes what Jev can't - summary, investment score, extracted numbers
    api_key = Application.get_env(:rzeczywiscie, :openai_api_key, "")
    gpt_result = if api_key == "" do
      Logger.warning("⚠️ LLM Analysis skipped: OpenAI API key not configured")
      "GPT skipped: no OpenAI key"
    else
      llm_result = run_llm_analysis(limit, &progress.(3, &1))
      Logger.info("🤖 LLM analysis: #{llm_result}")
      llm_result
    end

    Rzeczywiscie.JobProgress.report(job, "done - #{fetch_result}; #{jev_result}; #{gpt_result}")
    :ok
  end

  # Newest listings first, so each run's fresh ones are covered and the backlog
  # drains @jev_batch at a time (a Jev call takes ~300ms).
  @jev_batch 200

  defp run_jev(progress, limit \\ nil) do
    alias Rzeczywiscie.Services.Jev

    if Jev.configured?() do
      properties = from(p in Property,
        where: p.active == true and
               not is_nil(p.description) and
               fragment("length(?)", p.description) > 50 and
               is_nil(p.jev_analyzed_at),
        order_by: [desc: p.inserted_at],
        limit: ^(limit || @jev_batch)
      )
      |> Repo.all()

      total = length(properties)

      {ok, failed, last_error} = properties
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, nil}, fn {property, idx}, {ok, failed, last_error} ->
        progress.("Jev #{idx}/#{total} (#{ok} ok, #{failed} failed)")

        # A failure leaves jev_analyzed_at unset, so the next run retries it
        case Jev.analyze_and_store(property) do
          {:ok, _} ->
            {ok + 1, failed, last_error}

          {:error, reason} ->
            Logger.warning("  ✗ Jev failed for ##{property.id}: #{inspect(reason)}")
            {ok, failed + 1, reason}
        end
      end)

      result = "Jev #{ok}/#{total} analyzed"
      if failed > 0, do: result <> ", #{failed} failed (last: #{inspect(last_error)})", else: result
    else
      "Jev skipped: no TypeSafe key"
    end
  end

  defp fetch_descriptions(limit, progress \\ fn _ -> :ok end) do
    alias Rzeczywiscie.Services.DescriptionFetcher
    
    case DescriptionFetcher.fetch_top_deals(limit: limit, delay: 2500, progress: progress) do
      {:ok, %{total: total, fetched: fetched, failed: failed}} ->
        "#{fetched}/#{total} fetched (#{failed} failed)"
      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  defp run_llm_analysis(limit, progress \\ fn _ -> :ok end) do
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
      {successful, failed, last_error} = properties
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, nil}, fn {property, idx}, {ok, failed, last_error} ->
        Logger.info("[#{idx}/#{total}] Analyzing property ##{property.id}...")
        progress.("analyzing #{idx}/#{total} (#{ok} ok, #{failed} failed)")

        context = build_context(property)
        
        case analyze_with_timeout(property.description, context) do
          {:ok, signals} ->
            signals = Rzeczywiscie.Services.Jev.overlay(signals, property.jev_signals)
            save_analysis(property, signals)
            {ok + 1, failed, last_error}
            
          {:error, reason} ->
            Logger.warning("  ✗ Failed: #{inspect(reason)}")
            {ok, failed + 1, reason}
        end
      end)
      
      result = "#{successful}/#{total} analyzed"
      result = if failed > 0, do: result <> ", #{failed} failed (last: #{inspect(last_error)})", else: result
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
  Manually trigger the LLM analysis job. `jev_only: true` runs step 2 alone,
  on up to `jev_limit` listings.
  """
  def trigger(opts \\ []) do
    opts
    |> Keyword.put_new(:limit, 30)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> __MODULE__.new()
    |> Oban.insert()
  end
end

