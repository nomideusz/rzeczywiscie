defmodule Rzeczywiscie.Repo.Migrations.AddLlmAnalysisToProperties do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      # LLM analysis results
      add :llm_urgency, :integer, default: 0  # 0-10 scale
      add :llm_condition, :string  # unknown, needs_renovation, to_finish, good, renovated, new
      add :llm_motivation, :string  # unknown, standard, motivated, very_motivated
      add :llm_red_flags, {:array, :string}, default: []
      add :llm_positive_signals, {:array, :string}, default: []
      add :llm_score, :integer, default: 0  # Calculated score from LLM signals
      add :llm_analyzed_at, :utc_datetime  # When analysis was performed
    end
    
    # Index for finding properties that need analysis
    create index(:properties, [:llm_analyzed_at])
  end
end
