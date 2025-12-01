defmodule Rzeczywiscie.Repo.Migrations.AddLlmEnhancedAnalysisFields do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      # Additional LLM analysis fields that were being generated but not stored
      add :llm_investment_score, :integer  # 0-10, AI's overall investment rating
      add :llm_summary, :text  # AI-generated 1-2 sentence summary
      add :llm_hidden_costs, {:array, :string}, default: []  # Monthly fees, renovation costs
      add :llm_negotiation_hints, {:array, :string}, default: []  # Price negotiation signals
      
      # Extracted numeric values from description
      add :llm_monthly_fee, :integer  # Czynsz in PLN (if mentioned)
      add :llm_year_built, :integer  # Year built (if mentioned)
      add :llm_floor_info, :string  # e.g. "3/5" (floor/total floors)
    end
    
    # Index for filtering by investment score
    create index(:properties, [:llm_investment_score])
  end
end

