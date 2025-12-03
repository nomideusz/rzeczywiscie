defmodule Rzeczywiscie.Repo.Migrations.AddLlmDataQualityFieldsV2 do
  use Ecto.Migration

  def up do
    # Use execute with IF NOT EXISTS to handle case where columns may or may not exist
    execute "ALTER TABLE properties ADD COLUMN IF NOT EXISTS llm_data_issues text[] DEFAULT '{}'"
    execute "ALTER TABLE properties ADD COLUMN IF NOT EXISTS llm_listing_quality integer"
    execute "ALTER TABLE properties ADD COLUMN IF NOT EXISTS llm_is_agency boolean"
  end

  def down do
    alter table(:properties) do
      remove_if_exists :llm_data_issues, {:array, :string}
      remove_if_exists :llm_listing_quality, :integer
      remove_if_exists :llm_is_agency, :boolean
    end
  end
end

