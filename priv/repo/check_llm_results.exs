# Check LLM Analysis Results
# Run with: mix run priv/repo/check_llm_results.exs

alias Rzeczywiscie.Repo
alias Rzeczywiscie.RealEstate.Property
import Ecto.Query

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🤖 LLM ANALYSIS RESULTS")
IO.puts(String.duplicate("=", 60))

# Get analyzed properties
analyzed = from(p in Property,
  where: not is_nil(p.llm_analyzed_at),
  order_by: [desc: p.llm_score]
)
|> Repo.all()

IO.puts("\n📊 SUMMARY")
IO.puts("   Analyzed: #{length(analyzed)} properties")

if length(analyzed) > 0 do
  # Score distribution
  scores = Enum.map(analyzed, & &1.llm_score)
  avg_score = Enum.sum(scores) / length(scores)
  max_score = Enum.max(scores)
  min_score = Enum.min(scores)
  
  IO.puts("   Avg Score: #{Float.round(avg_score, 1)}")
  IO.puts("   Max Score: #{max_score}")
  IO.puts("   Min Score: #{min_score}")
  
  # Condition breakdown
  IO.puts("\n📋 CONDITION BREAKDOWN")
  conditions = analyzed
  |> Enum.group_by(& &1.llm_condition)
  |> Enum.map(fn {cond, props} -> {cond || "unknown", length(props)} end)
  |> Enum.sort_by(fn {_, count} -> -count end)
  
  for {cond, count} <- conditions do
    IO.puts("   #{cond}: #{count}")
  end
  
  # Motivation breakdown
  IO.puts("\n💪 MOTIVATION BREAKDOWN")
  motivations = analyzed
  |> Enum.group_by(& &1.llm_motivation)
  |> Enum.map(fn {mot, props} -> {mot || "unknown", length(props)} end)
  |> Enum.sort_by(fn {_, count} -> -count end)
  
  for {mot, count} <- motivations do
    IO.puts("   #{mot}: #{count}")
  end
  
  # Urgency distribution
  IO.puts("\n⚡ URGENCY DISTRIBUTION")
  urgencies = analyzed
  |> Enum.group_by(& &1.llm_urgency)
  |> Enum.sort_by(fn {u, _} -> u end)
  
  for {urgency, props} <- urgencies do
    bar = String.duplicate("█", length(props))
    IO.puts("   #{urgency}: #{bar} (#{length(props)})")
  end
  
  # Top scored properties
  IO.puts("\n🔥 TOP 10 BY LLM SCORE")
  IO.puts(String.duplicate("-", 60))
  
  top_10 = Enum.take(analyzed, 10)
  for p <- top_10 do
    title = String.slice(p.title || "", 0, 40)
    flags = if p.llm_red_flags && length(p.llm_red_flags) > 0, do: "🚩", else: ""
    positive = if p.llm_positive_signals && length(p.llm_positive_signals) > 0, do: "✨", else: ""
    
    IO.puts("")
    IO.puts("   Score: #{p.llm_score} #{flags}#{positive}")
    IO.puts("   Title: #{title}...")
    IO.puts("   Urgency: #{p.llm_urgency}/10 | Condition: #{p.llm_condition || "?"} | Motivation: #{p.llm_motivation || "?"}")
    
    if p.llm_positive_signals && length(p.llm_positive_signals) > 0 do
      IO.puts("   Positive: #{Enum.join(p.llm_positive_signals, ", ")}")
    end
    
    if p.llm_red_flags && length(p.llm_red_flags) > 0 do
      IO.puts("   Red flags: #{Enum.join(p.llm_red_flags, ", ")}")
    end
  end
  
  # Properties with red flags
  with_flags = Enum.filter(analyzed, fn p -> 
    p.llm_red_flags && length(p.llm_red_flags) > 0 
  end)
  
  if length(with_flags) > 0 do
    IO.puts("\n\n🚩 PROPERTIES WITH RED FLAGS (#{length(with_flags)})")
    IO.puts(String.duplicate("-", 60))
    
    for p <- Enum.take(with_flags, 5) do
      IO.puts("")
      IO.puts("   #{String.slice(p.title || "", 0, 50)}...")
      IO.puts("   Flags: #{Enum.join(p.llm_red_flags, ", ")}")
    end
  end
  
  # Properties with positive signals
  with_positive = Enum.filter(analyzed, fn p -> 
    p.llm_positive_signals && length(p.llm_positive_signals) > 0 
  end)
  
  if length(with_positive) > 0 do
    IO.puts("\n\n✨ PROPERTIES WITH POSITIVE SIGNALS (#{length(with_positive)})")
    IO.puts(String.duplicate("-", 60))
    
    # Count most common positive signals
    all_positives = with_positive
    |> Enum.flat_map(& &1.llm_positive_signals)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.take(10)
    
    IO.puts("\n   Most common:")
    for {signal, count} <- all_positives do
      IO.puts("   - #{signal}: #{count}")
    end
  end
  
  # Very motivated sellers
  very_motivated = Enum.filter(analyzed, & &1.llm_motivation == "very_motivated")
  
  if length(very_motivated) > 0 do
    IO.puts("\n\n🎯 VERY MOTIVATED SELLERS (#{length(very_motivated)})")
    IO.puts(String.duplicate("-", 60))
    
    for p <- very_motivated do
      IO.puts("")
      IO.puts("   #{String.slice(p.title || "", 0, 50)}...")
      IO.puts("   Urgency: #{p.llm_urgency}/10 | Score: #{p.llm_score}")
    end
  end
  
else
  IO.puts("\n   No properties analyzed yet.")
  IO.puts("   Run LLM analysis from Admin panel first.")
end

IO.puts("\n" <> String.duplicate("=", 60) <> "\n")

