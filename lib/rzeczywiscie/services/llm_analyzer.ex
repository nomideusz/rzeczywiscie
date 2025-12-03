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
  You're scanning property titles for an investor. Extract signals quickly.
  
  Respond ONLY with valid JSON:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated"
  }
  
  URGENCY: 0=none, 3-5=mild ("okazja"), 6-8=clear ("pilne"), 9-10=extreme ("likwidacja")
  
  CONDITION: "do remontu"=needs_renovation, "po remoncie"=renovated, "od dewelopera"=new
  
  NOT REAL ESTATE (major red flag!):
  - "dom szkieletowy/modułowy/prefabrykowany/mobilny" = PREFAB PRODUCT
  - "garaż blaszany/blaszak" = METAL SHED PRODUCT
  - "pawilon" without land = TEMPORARY STRUCTURE
  - "z montażem" = IT'S A PRODUCT FOR SALE
  
  Red flags: "spółdzielcze", "zadłużone", "hałas", "problem"
  Positive: "cichy", "park", "balkon", "taras", "ogród", "widok"
  
  Motivation: "pilne/wyjazd"=motivated, "musi się sprzedać"=very_motivated
  """
  
  # Enhanced prompt for full description analysis with structured data extraction
  @description_prompt """
  You are a sharp-eyed Polish real estate scout writing quick notes for investors.
  
  Respond ONLY with valid JSON:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated",
    "hidden_costs": [],
    "negotiation_hints": [],
    "investment_score": 0-10,
    "summary": "Your note in Polish - see rules below",
    "monthly_fee": null or number,
    "year_built": null or number,
    "floor_info": null or "X/Y"
  }
  
  EXTRACTION:
  - monthly_fee: czynsz/opłaty in PLN
  - year_built: rok budowy
  - floor_info: "3/5" format
  
  RED FLAGS (score 0-2 if found):
  - "dom szkieletowy/modułowy/prefabrykowany" = PREFAB PRODUCT, not real estate!
  - "garaż blaszany/blaszak" = Metal shed product, not property!
  - High fees (>500 PLN/month)
  - "bez księgi wieczystej", "spółdzielcze"
  
  SUMMARY RULES - THIS IS CRITICAL:
  Write like a friend texting about a property they just saw. Be specific and unique.
  
  ❌ FORBIDDEN PHRASES (never use these):
  - "Nieruchomość w X oferuje/jest..."
  - "co czyni tę ofertę atrakcyjną"
  - "co jest znacznie poniżej średniej rynkowej"
  - "atrakcyjna cena/inwestycja"
  - "w dzielnicy X"
  - "stanowi dobrą okazję"
  - Any generic filler phrases
  
  ✅ GOOD SUMMARIES (be like this):
  - "Świeży remont, balkon na południe. Przy AGH = pewny wynajem studentom."
  - "Parter bez ogrodu, hałas od ulicy - stąd niska cena. Trzeba sprawdzić osobiście."
  - "Czynsz 600zł zjada zysk. Lepiej szukać dalej."
  - "Wielki balkon, garaż w cenie. Sprzedający się spieszy - można targować."
  - "Blaszak za 15k - to produkt z marketu, nie nieruchomość!"
  - "Po remoncie, ale w bloku z wielkiej płyty. Cena ok, nic specjalnego."
  
  Be direct. Be specific. Point out the ONE thing that matters most.
  """
  
  # Context-aware prompt template (filled in dynamically)
  @context_prompt_template """
  You're a sharp real estate scout AND data quality checker. Analyze this listing.
  
  LISTING DATA (from scraper - may have errors!):
  - Price: %{price} PLN | Area: %{area} m² | Per m²: %{price_per_sqm} PLN
  - Location: %{district}, %{city}
  - Rooms: %{rooms}
  - Market avg in area: %{market_avg} PLN/m²
  - Type: %{transaction_type}
  
  %{location_instruction}
  
  Respond ONLY with valid JSON:
  {
    "urgency": 0-10,
    "condition": "unknown" | "needs_renovation" | "to_finish" | "good" | "renovated" | "new",
    "red_flags": [],
    "positive_signals": [],
    "seller_motivation": "unknown" | "standard" | "motivated" | "very_motivated",
    "hidden_costs": [],
    "negotiation_hints": [],
    "investment_score": 0-10,
    "summary": "Your quick note in Polish",
    "monthly_fee": null or number,
    "year_built": null or number,
    "floor_info": null or "X/Y",
    "street": null or "Street Name" or "Street Name 123",
    "extracted_city": null or "City Name",
    "extracted_district": null or "District Name",
    "data_issues": [],
    "corrected_area": null or number,
    "corrected_rooms": null or number,
    "corrected_transaction_type": null or "sprzedaż" or "wynajem",
    "is_agency": null or true or false,
    "listing_quality": 1-5
  }
  
  DATA QUALITY CHECKS - Look for these issues:
  1. WRONG AREA: If description says "45m2" but we have 1325m², extract corrected_area
  2. WRONG ROOMS: If "kawalerka" (studio) but rooms=5, correct it
  3. WRONG TRANSACTION: Monthly price (2000-5000 PLN) marked as sale? It's probably rent
  4. MISSING LOCATION: Extract city/district from description if we don't have it
  5. SUSPICIOUS DATA: Area 1m² or 10000m² for apartment? Flag it!
  
  Add to data_issues array (Polish):
  - "Błędna powierzchnia - w opisie X m²"
  - "Błędna liczba pokoi - opis wskazuje na Y"
  - "Prawdopodobnie wynajem, nie sprzedaż"
  - "Podejrzanie niska/wysoka cena za m²"
  - "Brak opisu - trudno ocenić"
  
  STREET EXTRACTION (any Polish city):
  - Look for: "ul.", "ulica", "al.", "aleja", "os.", "osiedle", "pl.", "plac"
  - Extract street name + number if present
  - Works for Kraków, Warsaw, Gdańsk, any city!
  
  LOCATION EXTRACTION:
  - If city/district mentioned in text, extract them
  - Kraków districts: Podgórze, Krowodrza, Nowa Huta, Prądnik, etc.
  - Other cities: extract what you find
  
  IS_AGENCY DETECTION:
  - true if: "biuro nieruchomości", "pośrednik", agency name, "prowizja X%"
  - false if: "bez pośredników", "prywatnie", "od właściciela"
  - null if unclear
  
  LISTING_QUALITY (1-5):
  - 5: Detailed description, photos mentioned, clear terms, complete info
  - 4: Good description, most info present
  - 3: Basic description, some info missing
  - 2: Sparse description, key info missing
  - 1: Almost no description, red flags, suspicious
  
  INSTANT RED FLAGS (score 0-2):
  - "dom szkieletowy/modułowy/prefabrykowany/mobilny" = PREFAB PRODUCT!
  - "garaż blaszany/blaszak/wiata" = Metal shed, not property!
  - "z montażem w X godzin" = It's a product being sold!
  - "pawilon handlowy" without land = Temporary structure!
  
  SCORE GUIDE:
  - 8-10: Way below market, seller motivated, ready to move in
  - 5-7: Fair deal, some upside
  - 3-4: Market price, nothing special  
  - 0-2: Overpriced, red flags, or NOT REAL ESTATE (prefab/shed)
  
  SUMMARY - WRITE LIKE A FRIEND TEXTING (Polish):
  - Include data issues if found! "Uwaga: w tytule 45m², system ma 1325m²"
  - Be direct about problems
  - Focus on THE ONE THING that matters most
  %{summary_instruction}
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
      
      # Check if district is actually known (not nil, empty, or "Unknown")
      district = context[:district]
      has_district = district && district != "" && String.downcase(district) != "unknown"
      
      # Build location-aware instructions
      {location_instruction, summary_location_hint, summary_instruction} = 
        if has_district do
          {
            "IMPORTANT: Use the EXACT district name \"#{district}\" in your summary. Do NOT use any other district or location names.",
            " - mention the district \"#{district}\"",
            "CRITICAL: In the summary, refer to the property location as \"#{district}\" - do NOT make up or use different location names!"
          }
        else
          {
            "NOTE: The district/location is unknown. Do NOT mention any specific district or location names in the summary. Focus on the property features and price.",
            " - do NOT mention any district or location",
            "CRITICAL: Do NOT mention any district, location, or area names in the summary since we don't know the exact location. Focus only on property features, condition, and price."
          }
        end
      
      # Build context-aware prompt
      system_prompt = @context_prompt_template
      |> String.replace("%{price}", format_number(price))
      |> String.replace("%{area}", format_number(area))
      |> String.replace("%{price_per_sqm}", format_number(price_per_sqm))
      |> String.replace("%{district}", district || "Unknown")
      |> String.replace("%{city}", context[:city] || "Unknown")
      |> String.replace("%{rooms}", to_string(context[:rooms] || "?"))
      |> String.replace("%{market_avg}", format_number(market_avg))
      |> String.replace("%{transaction_type}", context[:transaction_type] || "sprzedaż")
      |> String.replace("%{location_instruction}", location_instruction)
      |> String.replace("%{summary_location_hint}", summary_location_hint)
      |> String.replace("%{summary_instruction}", summary_instruction)
      
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
      {:error, reason} -> 
        # Log the raw content for debugging
        Logger.warning("  JSON parse error: #{inspect(reason)}")
        Logger.warning("  Raw content (first 500 chars): #{String.slice(content, 0, 500)}")
        {:error, :invalid_json}
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
    content = String.trim(content)
    
    # Try to find JSON object in the response
    cond do
      # Already starts with { - assume it's JSON
      String.starts_with?(content, "{") ->
        # Find matching closing brace
        extract_json_object(content)
        
      # Has markdown code block
      String.contains?(content, "```") ->
        content
        |> String.replace(~r/^```json\s*/m, "")
        |> String.replace(~r/^```\s*/m, "")
        |> String.replace(~r/\s*```\s*$/m, "")
        |> String.trim()
        |> extract_json_object()
        
      # Try to find JSON anywhere in the response
      true ->
        case Regex.run(~r/\{[\s\S]*\}/, content) do
          [json] -> json
          _ -> content
        end
    end
  end
  
  # Extract a complete JSON object, handling nested braces
  defp extract_json_object(content) do
    case Regex.run(~r/^\{[\s\S]*\}/m, content) do
      [json] -> json
      _ -> content
    end
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
    # Extracted numeric fields
    |> maybe_add_field(signals, "monthly_fee", :monthly_fee, nil)
    |> maybe_add_field(signals, "year_built", :year_built, nil)
    |> maybe_add_field(signals, "floor_info", :floor_info, nil)
    # Location extraction fields
    |> maybe_add_field(signals, "street", :street, nil)
    |> maybe_add_field(signals, "extracted_city", :extracted_city, nil)
    |> maybe_add_field(signals, "extracted_district", :extracted_district, nil)
    # Data quality fields
    |> maybe_add_field(signals, "data_issues", :data_issues, [])
    |> maybe_add_field(signals, "corrected_area", :corrected_area, nil)
    |> maybe_add_field(signals, "corrected_rooms", :corrected_rooms, nil)
    |> maybe_add_field(signals, "corrected_transaction_type", :corrected_transaction_type, nil)
    # Agency and quality detection
    |> maybe_add_field(signals, "is_agency", :is_agency, nil)
    |> maybe_add_field(signals, "listing_quality", :listing_quality, nil)
    # Clean up summary to remove "Unknown" location references
    |> clean_summary()
  end
  
  # Clean up summary to remove "Unknown" location references that LLM may have generated
  defp clean_summary(%{summary: summary} = signals) when is_binary(summary) do
    cleaned = summary
    # Remove common patterns with "Unknown"
    |> String.replace(~r/\s*w\s+dzielnicy\s+Unknown\.?/i, "")
    |> String.replace(~r/\s*w\s+Unknown\.?/i, "")
    |> String.replace(~r/\s*w\s+okolicy\s+Unknown\.?/i, "")
    |> String.replace(~r/\s*w\s+rejonie\s+Unknown\.?/i, "")
    |> String.replace(~r/\s*na\s+terenie\s+Unknown\.?/i, "")
    |> String.replace(~r/\bUnknown\b/i, "")
    # Clean up double spaces and trailing commas
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/,\s*,/, ",")
    |> String.replace(~r/,\s*\./, ".")
    |> String.trim()
    
    %{signals | summary: cleaned}
  end
  defp clean_summary(signals), do: signals
  
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
  Check if a property title/description indicates a product being sold (not real estate).
  Returns true if the listing is for a prefab house, metal shed, or other product.
  """
  def is_prefab_house?(text) when is_binary(text) do
    text_lower = String.downcase(text)
    
    # Prefab/modular houses - products, not real estate
    prefab_patterns = [
      "dom szkieletowy",
      "dom modułowy", 
      "dom prefabrykowany",
      "dom mobilny",
      "domek mobilny",
      "domek modułowy",
      "domek szkieletowy",
      "z montażem w",
      "montaż w",
      "gotowy do montażu",
      "dom całoroczny drewniany",
      "dom drewniany całoroczny",
      "domek letniskowy",
      # Metal sheds - definitely products
      "garaż blaszany",
      "blaszak",
      "garaże blaszane",
      "wiata blaszana",
      "hala blaszana",
      # Commercial kiosks/pavilions without land
      "pawilon handlowy",
      "kiosk handlowy",
      "kontener",
      # Product indicators
      "producent",
      "całe małopolskie",  # delivery range = product
      "dostawa gratis",
      "transport w cenie"
    ]
    
    Enum.any?(prefab_patterns, fn pattern -> 
      String.contains?(text_lower, pattern)
    end)
  end
  
  def is_prefab_house?(_), do: false
  
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

