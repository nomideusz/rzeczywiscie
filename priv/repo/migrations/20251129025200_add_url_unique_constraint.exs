defmodule Rzeczywiscie.Repo.Migrations.AddUrlUniqueConstraint do
  use Ecto.Migration

  def change do
    # Add unique constraint on URL to prevent same property URL from being added multiple times
    # This prevents duplicates across different sources (e.g., same property on OLX and Otodom)
    create unique_index(:properties, [:url], name: :properties_url_index)
  end
end

