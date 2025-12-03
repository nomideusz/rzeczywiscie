defmodule Rzeczywiscie.Repo.Migrations.AddLlmDataQualityFields do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :llm_data_issues, {:array, :string}, default: []
      add :llm_listing_quality, :integer
      add :llm_is_agency, :boolean
    end
  end
end

