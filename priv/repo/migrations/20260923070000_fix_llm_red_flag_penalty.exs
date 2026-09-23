defmodule Rzeczywiscie.Repo.Migrations.FixLlmRedFlagPenalty do
  use Ecto.Migration

  # LLMAnalyzer.calculate_signal_score/1 capped the red-flag penalty with min
  # instead of max, so every GPT-analyzed listing lost at least 9 Hot Deals
  # points (no flags scored -9, not 0). Swap that one term on the rows the
  # formula scored, from the flags stored alongside the score.
  #
  # The garbage (score 0) and metadata-only (score 3) paths never ran the
  # formula, but can leave a stale llm_condition behind from an earlier
  # analysis, so they're told apart by the summary they write.
  @formula_rows """
  llm_analyzed_at IS NOT NULL AND llm_condition IS NOT NULL
    AND llm_summary IS DISTINCT FROM 'Skipped: description contains CSS/navigation garbage'
    AND llm_summary IS DISTINCT FROM 'Tylko metadane - brak pełnego opisu nieruchomości'
  """
  @penalty_now "GREATEST(COALESCE(cardinality(llm_red_flags), 0) * -3, -9)"
  @penalty_before "LEAST(COALESCE(cardinality(llm_red_flags), 0) * -3, -9)"

  def up do
    execute "UPDATE properties SET llm_score = llm_score - #{@penalty_before} + #{@penalty_now} WHERE #{@formula_rows}"
  end

  def down do
    execute "UPDATE properties SET llm_score = llm_score - #{@penalty_now} + #{@penalty_before} WHERE #{@formula_rows}"
  end
end
