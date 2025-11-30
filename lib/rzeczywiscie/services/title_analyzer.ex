defmodule Rzeczywiscie.Services.TitleAnalyzer do
  @moduledoc """
  Regex-based title analyzer for extracting signals from property titles.
  Free alternative to LLM for basic signal detection.
  """

  @doc """
  Analyzes a property title and returns extracted signals.
  Returns a map with urgency, condition, motivation, red_flags, and positive_signals.
  """
  def analyze(nil), do: empty_result()
  def analyze(""), do: empty_result()
  
  def analyze(title) when is_binary(title) do
    title_lower = String.downcase(title)
    
    %{
      urgency: calculate_urgency(title_lower),
      condition: detect_condition(title_lower),
      motivation: detect_motivation(title_lower),
      red_flags: detect_red_flags(title_lower),
      positive_signals: detect_positive_signals(title_lower),
      analyzed_by: "regex"
    }
  end

  defp empty_result do
    %{
      urgency: 0,
      condition: nil,
      motivation: "standard",
      red_flags: [],
      positive_signals: [],
      analyzed_by: "regex"
    }
  end

  # Urgency scoring (0-10)
  defp calculate_urgency(text) do
    urgency_patterns = [
      # High urgency (3 points each)
      {~r/\bpilne\b|\bpilna\b|\bpilnie\b|\bpilno\b/, 3},
      {~r/musz[eę]\s*(sprzeda|wynaj)/, 3},
      {~r/likwidacja/, 3},
      {~r/szybka\s+sprzeda[zż]/, 3},
      
      # Medium urgency (2 points each)
      {~r/wyjazd/, 2},
      {~r/przeprowadzk/, 2},
      {~r/poni[żz]ej\s+(ceny\s+)?rynk/, 2},
      {~r/okazj[aą]/, 2},
      {~r/super\s+cen[aą]/, 2},
      {~r/ostatni[ea]?\s+szans[aą]/, 2},
      
      # Low urgency (1 point each)
      {~r/do\s+negocjacj/, 1},
      {~r/negocjuj/, 1},
      {~r/cena\s+do\s+uzgodnienia/, 1},
      {~r/obni[żz][oa]n[aąy]/, 1},
      {~r/nowa\s+cena/, 1},
      {~r/promocj/, 1},
      {~r/taniej/, 1},
      {~r/bezpo[śs]rednio/, 1}
    ]
    
    score = Enum.reduce(urgency_patterns, 0, fn {pattern, points}, acc ->
      if Regex.match?(pattern, text), do: acc + points, else: acc
    end)
    
    # Cap at 10
    min(score, 10)
  end

  # Condition detection
  defp detect_condition(text) do
    cond do
      Regex.match?(~r/do\s+remontu|wymaga\s+remontu|do\s+odnowienia/, text) -> "needs_renovation"
      Regex.match?(~r/stan\s+deweloperski|do\s+wyko[nń]czenia|surowy/, text) -> "to_finish"
      Regex.match?(~r/po\s+remoncie|po\s+generalnym|[śs]wie[żz]o\s+odnowion/, text) -> "renovated"
      Regex.match?(~r/wysoki\s+standard|luksus|premium|ekskluzyw/, text) -> "renovated"
      Regex.match?(~r/now[ey]\b|nowoczesn|z\s+\d{4}\s*r/, text) -> "new"
      Regex.match?(~r/dobry\s+stan|zadbany|utrzyman/, text) -> "good"
      true -> nil
    end
  end

  # Motivation detection  
  defp detect_motivation(text) do
    very_motivated_patterns = [
      ~r/pilne|pilna|pilnie/,
      ~r/musz[eę]/,
      ~r/likwidacja/,
      ~r/wyjazd\s+za\s+granic/,
      ~r/szybka\s+sprzeda/,
      ~r/spadek|dziedzicz/,
      ~r/rozw[oó]d/
    ]
    
    motivated_patterns = [
      ~r/okazj[aą]/,
      ~r/negocjuj|do\s+negocjacj/,
      ~r/obni[żz]k/,
      ~r/poni[żz]ej/,
      ~r/zamian[aą]/,
      ~r/bezpo[śs]rednio/
    ]
    
    cond do
      Enum.any?(very_motivated_patterns, &Regex.match?(&1, text)) -> "very_motivated"
      Enum.any?(motivated_patterns, &Regex.match?(&1, text)) -> "motivated"
      true -> "standard"
    end
  end

  # Red flags detection
  defp detect_red_flags(text) do
    red_flag_patterns = [
      {~r/problem|sporn|s[ąa]dow/, "legal_issues"},
      {~r/g[łl]o[śs]n|ha[łl]a[śs]|ruchliw/, "noisy_area"},
      {~r/bez\s+parkingu|brak\s+parking/, "no_parking"},
      {~r/wysoki\s+czynsz|du[żz]y\s+czynsz/, "high_fees"},
      {~r/parter\b.*(?!ogr[óo]d)/, "ground_floor"},
      {~r/do\s+remontu\s+generalnego/, "major_renovation"},
      {~r/wilgo[ćc]|grzyb|zaciek/, "moisture_issues"},
      {~r/bez\s+windy.*pi[ęe]tr[oa]\s+[4-9]/, "no_elevator_high"},
      {~r/uci[ąa][żz]liw/, "problematic_neighbors"}
    ]
    
    red_flag_patterns
    |> Enum.filter(fn {pattern, _flag} -> Regex.match?(pattern, text) end)
    |> Enum.map(fn {_pattern, flag} -> flag end)
  end

  # Positive signals detection
  defp detect_positive_signals(text) do
    positive_patterns = [
      {~r/balkon/, "balcony"},
      {~r/taras/, "terrace"},
      {~r/ogr[oó]d|ogr[oó]dek/, "garden"},
      {~r/parking|gara[żz]|miejsce\s+postojowe/, "parking"},
      {~r/piwnic/, "basement"},
      {~r/wind[aą]/, "elevator"},
      {~r/cichy|cich[aą]|spokojna/, "quiet_area"},
      {~r/ziele[nń]|park|las/, "green_area"},
      {~r/centrum|[śs]r[oó]dmie[śs]cie/, "central_location"},
      {~r/tramwaj|metro|komunikacj/, "good_transport"},
      {~r/klimatyzacj/, "air_conditioning"},
      {~r/widok|panoram/, "view"},
      {~r/s[łl]oneczn/, "sunny"},
      {~r/roz[łl]o[żz]on|funkcjonaln|praktyczn/, "good_layout"},
      {~r/bezpo[śs]rednio|bez\s+prowizji|0%\s+prowizji/, "no_commission"},
      {~r/nowe\s+okna|wymienion/, "renovated_elements"},
      {~r/umeblowane|wyposa[żz]on/, "furnished"}
    ]
    
    positive_patterns
    |> Enum.filter(fn {pattern, _signal} -> Regex.match?(pattern, text) end)
    |> Enum.map(fn {_pattern, signal} -> signal end)
  end

  @doc """
  Calculate a score based on the analysis results.
  """
  def calculate_score(analysis) do
    urgency_score = analysis.urgency * 2  # 0-20 points
    
    condition_score = case analysis.condition do
      "needs_renovation" -> 5  # Potential for value-add
      "to_finish" -> 3
      "renovated" -> 2
      "new" -> 1
      _ -> 0
    end
    
    motivation_score = case analysis.motivation do
      "very_motivated" -> 10
      "motivated" -> 5
      _ -> 0
    end
    
    positive_score = length(analysis.positive_signals) * 2  # 2 points each
    red_flag_penalty = length(analysis.red_flags) * 3  # -3 points each
    
    max(0, urgency_score + condition_score + motivation_score + positive_score - red_flag_penalty)
  end
end

