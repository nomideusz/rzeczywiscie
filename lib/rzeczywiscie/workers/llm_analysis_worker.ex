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
    
    # Get properties with descriptions pending analysis
    all_properties = from(p in Property,
      where: p.active == true and 
             not is_nil(p.description) and 
             fragment("length(?)", p.description) > 100 and
             is_nil(p.llm_analyzed_at),
      order_by: [desc: p.inserted_at],
      limit: ^(limit * 2)  # Fetch more, filter CSS garbage
    )
    |> Repo.all()
    
    # Filter out CSS garbage
    {valid_properties, css_garbage} = Enum.split_with(all_properties, &is_valid_description?(&1.description))
    
    # Mark CSS garbage as analyzed
    Enum.each(css_garbage, fn p ->
      RealEstate.update_property(p, %{
        llm_analyzed_at: DateTime.utc_now(),
        llm_score: 0,
        llm_summary: "Skipped: description contains CSS/invalid content"
      })
    end)
    
    properties = Enum.take(valid_properties, limit)
    total = length(properties)
    
    if total == 0 do
      "No properties pending analysis"
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
      
      "#{successful}/#{total} analyzed"
    end
  end

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
      llm_floor_info: signals[:floor_info]
    }
    
    case RealEstate.update_property(property, updates) do
      {:ok, _} ->
        Logger.info("  ✓ Property ##{property.id} analyzed (investment: #{signals[:investment_score] || "?"}/10)")
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

  defp is_valid_description?(nil), do: false
  defp is_valid_description?(desc) when byte_size(desc) < 50, do: false
  defp is_valid_description?(desc) do
    desc_lower = String.downcase(desc)
    first_100 = String.slice(desc_lower, 0, 100)
    
    css_patterns = ["@media", "@keyframes", ".css-", "{text-decoration", "{display:", 
                    "{color:", "{background", ":hover{", "!important", "var(--",
                    "oklch(", "rgba(", "font-family:", "font-size:"]
    
    has_css = Enum.any?(css_patterns, &String.contains?(first_100, &1))
    
    css_char_ratio = (String.graphemes(desc) 
      |> Enum.count(fn c -> c in ["{", "}", ":", ";"] end)) / max(String.length(desc), 1)
    
    not has_css and css_char_ratio < 0.05
  end

  @doc """
  Manually trigger the LLM analysis job.
  """
  def trigger(opts \\ []) do
    %{"limit" => Keyword.get(opts, :limit, 30)}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end

