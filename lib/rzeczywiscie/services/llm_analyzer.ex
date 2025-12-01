defmodule Rzeczywiscie.Services.LLMAnalyzer do
  @moduledoc """
  LLM-based property analysis to extract signals that regex misses.
  
  Uses OpenAI GPT-4o-mini for cost-effective analysis (~$0.15/1M input tokens).
  
  Two modes:
  1. Title analysis - fast, cheap, for all properties (via regex fallback)
  2. Description analysis - deeper, for top deals only (uses LLM)
  
  Extracts signals like:
  - Urgency level (motivated seller indicators)
  - Property condition (renovation needed, newly renovated, etc.)
  - Red flags (legal issues, problems mentioned)
  - Positive signals (quiet, green area, good neighborhood)
  """
  
  require Logger
  
  @openai_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-4o-mini"
  
  # System prompt for title analysis (kept for backwards compatibility)
  @system_prompt """
  You are a Polish real estate analyst. Analyze property listing titles and extract signals.
  
  Respond ONLY with valid JSON in this exact format:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated"
  }
  
  Scoring guide:
  - urgency 0: no urgency signals
  - urgency 3-5: mild urgency ("okazja", "do negocjacji")
  - urgency 6-8: clear urgency ("pilne", "szybka sprzedaż", "wyjazd")
  - urgency 9-10: extreme urgency ("musi się sprzedać", "likwidacja")
  
  Condition signals in Polish:
  - "do remontu", "do wykończenia" = needs_renovation/to_finish
  - "po remoncie", "odnowione" = renovated
  - "nowe", "deweloper", "od dewelopera" = new
  - "stan bardzo dobry", "gotowe do zamieszkania" = good
  
  Red flags: "spółdzielcze", "zadłużone", "hałas", "problem", "wada"
  Positive: "cichy", "zielony", "park", "spokojny", "widok", "balkon", "taras", "ogród"
  
  Motivation signals:
  - "bezpośrednio", "bez pośredników" = standard (common marketing)
  - "pilne", "wyjazd", "przeprowadzka" = motivated
  - "musi się sprzedać", "likwidacja", "poniżej rynku" = very_motivated
  """
  
  # Enhanced prompt for full description analysis with structured data extraction
  @description_prompt """
  You are a Polish real estate investment analyst. Analyze this property listing description.
  
  Extract ALL relevant signals for an investor looking for good deals.
  
  Respond ONLY with valid JSON in this exact format:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated",
    "hidden_costs": [],
    "negotiation_hints": [],
    "investment_score": 0-10,
    "summary": "1-2 sentence summary in Polish",
    "monthly_fee": null or number,
    "year_built": null or number,
    "floor_info": null or "X/Y"
  }
  
  EXTRACTION RULES:
  
  NUMERIC VALUES (extract if mentioned):
  - monthly_fee: Extract czynsz/opłaty in PLN (e.g. "czynsz 450 zł" → 450)
  - year_built: Extract year built (e.g. "z 1985 roku", "budynek z 2020" → 1985/2020)
  - floor_info: Extract floor/total (e.g. "3 piętro z 5" → "3/5", "parter" → "0")
  
  URGENCY SIGNALS (0-10):
  - 0: No urgency signals
  - 3-5: "okazja", "do negocjacji"  
  - 6-8: "pilne", "szybka sprzedaż", "wyjazd"
  - 9-10: "musi się sprzedać", "likwidacja"
  
  CONDITION:
  - "do remontu", "wymaga remontu" → needs_renovation
  - "stan deweloperski", "do wykończenia" → to_finish
  - "po generalnym remoncie" → renovated
  - "nowe budownictwo", "od dewelopera" → new
  - "dobry stan", "gotowe do zamieszkania" → good
  
  RED FLAGS:
  - High fees (>500 PLN/month for apartment)
  - Legal issues: "spółdzielcze własnościowe", "bez księgi wieczystej"
  - Problems: "hałas", "ruchliwa ulica"
  - Ground floor without garden
  
  POSITIVE SIGNALS:
  - Location: "cicha okolica", "blisko centrum", "park"
  - Features: "balkon", "taras", "ogród", "piwnica", "parking"
  - Quality: "nowe okna", "klimatyzacja", "po remoncie"
  - Transport: "tramwaj", "metro", "dobra komunikacja"
  
  HIDDEN COSTS (strings, e.g. "Czynsz 450 PLN/mies", "Brak miejsca parkingowego"):
  - Monthly administration fees
  - Required renovations
  - Missing parking costs
  
  NEGOTIATION HINTS:
  - "cena do negocjacji", "bezpośrednio", long time on market
  
  SUMMARY: Write 1-2 sentences in Polish summarizing key investment points.
  """
  
  # Context-aware prompt template (filled in dynamically)
  @context_prompt_template """
  You are a Polish real estate investment analyst. Analyze this property listing.
  
  PROPERTY CONTEXT (USE THIS DATA, DO NOT INVENT LOCATIONS):
  - Listed Price: %{price} PLN
  - Area: %{area} m²
  - Price per m²: %{price_per_sqm} PLN/m²
  - District: %{district}
  - Market avg price/m² in this district: %{market_avg} PLN/m²
  - Transaction type: %{transaction_type}
  
  IMPORTANT: Use the EXACT district name "%{district}" in your summary. Do NOT use any other district or location names.
  
  Given this context, analyze the description and assess if this is a good deal.
  
  Respond ONLY with valid JSON in this exact format:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated",
    "hidden_costs": [],
    "negotiation_hints": [],
    "investment_score": 0-10,
    "summary": "1-2 sentence summary in Polish using district %{district}",
    "monthly_fee": null or number,
    "year_built": null or number,
    "floor_info": null or "X/Y"
  }
  
  INVESTMENT SCORE GUIDELINES (considering the property context):
  - 8-10: Significantly below market price, motivated seller, good condition
  - 5-7: Fair price with some upside potential
  - 3-4: Average deal, at market price
  - 0-2: Overpriced or significant red flags
  
  Be especially attentive to:
  1. Is %{price_per_sqm} PLN/m² below or above market avg of %{market_avg} PLN/m²?
  2. Hidden costs that would increase effective price
  3. Renovation needs that would add costs
  4. Urgency signals suggesting negotiation room
  
  CRITICAL: In the summary, refer to the property location as "%{district}" - do NOT make up or use different location names!
  """
  
  @doc """
  Analyze a single property title and return extracted signals.
  Returns {:ok, signals} or {:error, reason}.
  """
  def analyze_title(title) when is_binary(title) and title != "" do
    api_key = get_api_key()
    
    if api_key == "" do
      {:error, :api_key_not_configured}
    else
      call_openai(title, api_key, @system_prompt, "Analyze this title: ")
    end
  end
  
  def analyze_title(_), do: {:error, :invalid_title}
  
  @doc """
  Analyze a full property description for deeper insights.
  More expensive but extracts much more signal than title-only analysis.
  Returns {:ok, signals} or {:error, reason}.
  """
  def analyze_description(description) when is_binary(description) and byte_size(description) > 50 do
    api_key = get_api_key()
    
    if api_key == "" do
      {:error, :api_key_not_configured}
    else
      # Limit description to ~3000 chars to control costs
      truncated = String.slice(description, 0, 3000)
      call_openai(truncated, api_key, @description_prompt, "Analyze this property description:\n\n")
    end
  end
  
  def analyze_description(_), do: {:error, :description_too_short}
  
  @doc """
  Analyze a property description with full property context for smarter analysis.
  Passes price, area, district and market data to help LLM make better investment judgments.
  
  Context map should include:
  - :price - Listed price in PLN
  - :area - Area in m²
  - :district - District name
  - :market_avg_price_per_sqm - Average price/m² in the district
  - :transaction_type - "sprzedaż" or "wynajem"
  
  Returns {:ok, signals} or {:error, reason}.
  """
  def analyze_description_with_context(description, context) when is_binary(description) and byte_size(description) > 50 do
    api_key = get_api_key()
    
    if api_key == "" do
      {:error, :api_key_not_configured}
    else
      price = context[:price] || 0
      area = context[:area] || 0
      price_per_sqm = if area > 0, do: round(price / area), else: 0
      market_avg = context[:market_avg_price_per_sqm] || 0
      
      # Build context-aware prompt
      system_prompt = @context_prompt_template
      |> String.replace("%{price}", format_number(price))
      |> String.replace("%{area}", format_number(area))
      |> String.replace("%{price_per_sqm}", format_number(price_per_sqm))
      |> String.replace("%{district}", context[:district] || "Unknown")
      |> String.replace("%{market_avg}", format_number(market_avg))
      |> String.replace("%{transaction_type}", context[:transaction_type] || "sprzedaż")
      
      truncated = String.slice(description, 0, 3000)
      call_openai(truncated, api_key, system_prompt, "Property description:\n\n")
    end
  end
  
  def analyze_description_with_context(_, _), do: {:error, :description_too_short}
  
  defp format_number(num) when is_number(num), do: :erlang.float_to_binary(num * 1.0, decimals: 0)
  defp format_number(%Decimal{} = num), do: Decimal.to_string(num, :normal)
  defp format_number(_), do: "0"
  
  @doc """
  Analyze a property with both title and description.
  Uses description if available (better signal), falls back to title.
  """
  def analyze_property(property) do
    cond do
      # Prefer description analysis if available
      property.description && String.length(property.description) > 100 ->
        case analyze_description(property.description) do
          {:ok, signals} -> {:ok, Map.put(signals, :analysis_type, :description)}
          {:error, _} -> fallback_to_title(property.title)
        end
        
      # Fall back to title
      property.title && String.length(property.title) > 5 ->
        fallback_to_title(property.title)
        
      true ->
        {:error, :no_content}
    end
  end
  
  defp fallback_to_title(title) do
    case analyze_title(title) do
      {:ok, signals} -> {:ok, Map.put(signals, :analysis_type, :title)}
      error -> error
    end
  end
  
  @doc """
  Analyze multiple property titles in batch.
  More efficient than individual calls - combines into one prompt.
  Returns list of {property_id, signals} tuples.
  """
  def analyze_titles_batch(properties, opts \\ []) do
    api_key = get_api_key()
    batch_size = Keyword.get(opts, :batch_size, 20)
    
    if api_key == "" do
      {:error, :api_key_not_configured}
    else
      properties
      |> Enum.chunk_every(batch_size)
      |> Enum.flat_map(fn batch -> 
        case analyze_batch(batch, api_key) do
          {:ok, results} -> results
          {:error, _} -> []
        end
      end)
    end
  end
  
  # Analyze a batch of properties in a single API call
  defp analyze_batch(properties, api_key) do
    # Build prompt with numbered titles
    titles_text = properties
    |> Enum.with_index(1)
    |> Enum.map(fn {p, idx} -> "#{idx}. #{p.title}" end)
    |> Enum.join("\n")
    
    batch_prompt = """
    Analyze these #{length(properties)} Polish property listing titles.
    Return a JSON array with one object per title, in the same order.
    
    Titles:
    #{titles_text}
    """
    
    case call_openai_batch(batch_prompt, api_key) do
      {:ok, results} when is_list(results) ->
        # Pair results with property IDs
        paired = Enum.zip(properties, results)
        |> Enum.map(fn {property, signals} -> {property.id, signals} end)
        {:ok, paired}
        
      {:ok, _} ->
        {:error, :invalid_response_format}
        
      error ->
        error
    end
  end
  
  defp call_openai(content, api_key, system_prompt \\ @system_prompt, user_prefix \\ "Analyze this title: ") do
    # Adjust max_tokens based on content length (descriptions need more)
    max_tokens = if String.length(content) > 500, do: 800, else: 200
    
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: "#{user_prefix}#{content}"}
      ],
      temperature: 0.1,  # Low temperature for consistent results
      max_tokens: max_tokens
    }
    
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]
    
    Logger.info("  Calling OpenAI API (#{String.slice(content, 0, 50)}...)")

    case Req.post(@openai_url, json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("  ✓ OpenAI response received")
        parse_response(response)

      {:ok, %{status: 401}} ->
        Logger.error("  ✗ OpenAI API: Invalid API key (401 Unauthorized)")
        {:error, :invalid_api_key}

      {:ok, %{status: 429}} ->
        Logger.warning("  ✗ OpenAI rate limit hit (429) - slow down requests")
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.error("  ✗ OpenAI API error #{status}: #{inspect(body)}")
        {:error, :api_error}

      {:error, %{reason: :timeout}} ->
        Logger.error("  ✗ OpenAI request timed out after 30 seconds")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("  ✗ OpenAI request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
  
  defp call_openai_batch(prompt, api_key) do
    batch_system = @system_prompt <> "\n\nFor batch analysis, return a JSON ARRAY of objects."
    
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: batch_system},
        %{role: "user", content: prompt}
      ],
      temperature: 0.1,
      max_tokens: 2000  # More tokens for batch response
    }
    
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]
    
    case Req.post(@openai_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        parse_batch_response(response)
        
      {:ok, %{status: 429}} ->
        Logger.warning("OpenAI rate limit hit")
        {:error, :rate_limited}
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, :api_error}
        
      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end
  
  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    # Extract JSON from response (may have markdown code blocks)
    json_str = extract_json(content)
    
    case Jason.decode(json_str) do
      {:ok, signals} -> {:ok, normalize_signals(signals)}
      {:error, _} -> {:error, :invalid_json}
    end
  end
  
  defp parse_response(_), do: {:error, :invalid_response}
  
  defp parse_batch_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    json_str = extract_json(content)
    
    case Jason.decode(json_str) do
      {:ok, signals} when is_list(signals) -> 
        {:ok, Enum.map(signals, &normalize_signals/1)}
      {:ok, _} -> 
        {:error, :expected_array}
      {:error, _} -> 
        {:error, :invalid_json}
    end
  end
  
  defp parse_batch_response(_), do: {:error, :invalid_response}
  
  # Extract JSON from potential markdown code blocks
  defp extract_json(content) do
    content
    |> String.trim()
    |> String.replace(~r/^```json\s*/, "")
    |> String.replace(~r/^```\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end
  
  # Normalize signals to expected format with defaults
  defp normalize_signals(signals) when is_map(signals) do
    base = %{
      urgency: normalize_integer(Map.get(signals, "urgency", 0)),
      condition: normalize_condition(Map.get(signals, "condition", "unknown")),
      red_flags: Map.get(signals, "red_flags", []) |> List.wrap(),
      positive_signals: Map.get(signals, "positive_signals", []) |> List.wrap(),
      seller_motivation: normalize_motivation(Map.get(signals, "seller_motivation", "unknown"))
    }
    
    # Add description-specific fields if present
    base
    |> maybe_add_field(signals, "hidden_costs", :hidden_costs, [])
    |> maybe_add_field(signals, "negotiation_hints", :negotiation_hints, [])
    |> maybe_add_field(signals, "investment_score", :investment_score, nil)
    |> maybe_add_field(signals, "summary", :summary, nil)
    # New extracted numeric fields
    |> maybe_add_field(signals, "monthly_fee", :monthly_fee, nil)
    |> maybe_add_field(signals, "year_built", :year_built, nil)
    |> maybe_add_field(signals, "floor_info", :floor_info, nil)
  end
  
  defp normalize_signals(_), do: default_signals()
  
  defp normalize_integer(val) when is_integer(val), do: val
  defp normalize_integer(val) when is_float(val), do: round(val)
  defp normalize_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp normalize_integer(_), do: 0
  
  defp maybe_add_field(map, signals, json_key, atom_key, default) do
    value = Map.get(signals, json_key, default)
    if value != nil and value != default do
      normalized_value = case atom_key do
        key when key in [:monthly_fee, :year_built, :investment_score] -> 
          normalize_integer(value)
        _ when is_list(default) -> 
          List.wrap(value)
        _ -> 
          value
      end
      Map.put(map, atom_key, normalized_value)
    else
      map
    end
  end
  
  defp default_signals do
    %{
      urgency: 0,
      condition: :unknown,
      red_flags: [],
      positive_signals: [],
      seller_motivation: :unknown
    }
  end
  
  defp normalize_condition("needs_renovation"), do: :needs_renovation
  defp normalize_condition("to_finish"), do: :to_finish
  defp normalize_condition("good"), do: :good
  defp normalize_condition("renovated"), do: :renovated
  defp normalize_condition("new"), do: :new
  defp normalize_condition(_), do: :unknown
  
  defp normalize_motivation("standard"), do: :standard
  defp normalize_motivation("motivated"), do: :motivated
  defp normalize_motivation("very_motivated"), do: :very_motivated
  defp normalize_motivation(_), do: :unknown
  
  defp get_api_key do
    Application.get_env(:rzeczywiscie, :openai_api_key, "")
  end
  
  @doc """
  Calculate score bonus from LLM signals.
  Returns a score from -10 to +20 based on extracted signals.
  """
  def calculate_signal_score(signals) when is_map(signals) do
    urgency_score = signals.urgency  # 0-10
    
    condition_score = case signals.condition do
      :needs_renovation -> -5  # Needs work = discount expected
      :to_finish -> -3
      :good -> 0
      :renovated -> 3  # Recently renovated = premium
      :new -> 5
      _ -> 0
    end
    
    motivation_score = case signals.seller_motivation do
      :very_motivated -> 5
      :motivated -> 3
      :standard -> 0
      _ -> 0
    end
    
    red_flag_penalty = min(length(signals.red_flags) * -3, -9)  # Max -9
    positive_bonus = min(length(signals.positive_signals) * 2, 6)  # Max +6
    
    # Total: urgency (0-10) + condition (-5 to +5) + motivation (0-5) 
    #        + red_flags (-9 to 0) + positive (0 to +6)
    # Range: approximately -14 to +26, but typically -5 to +15
    urgency_score + condition_score + motivation_score + red_flag_penalty + positive_bonus
  end
  
  def calculate_signal_score(_), do: 0
end

