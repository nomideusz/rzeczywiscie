defmodule Rzeczywiscie.Repo.Migrations.AddGridAndTrgmIndexes do
  use Ecto.Migration

  def up do
    # AQI joins/counts match on ROUND(lat/lng::numeric, 2); an expression
    # index makes them indexable without touching the queries.
    execute """
    CREATE INDEX properties_grid_coords_index
    ON properties (ROUND(latitude::numeric, 2), ROUND(longitude::numeric, 2))
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    """

    # Text search uses ILIKE '%term%' — only trigram GIN indexes can serve
    # leading-wildcard matches.
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    execute "CREATE INDEX properties_title_trgm_index ON properties USING gin (title gin_trgm_ops)"
    execute "CREATE INDEX properties_description_trgm_index ON properties USING gin (description gin_trgm_ops)"
  end

  def down do
    execute "DROP INDEX IF EXISTS properties_description_trgm_index"
    execute "DROP INDEX IF EXISTS properties_title_trgm_index"
    execute "DROP INDEX IF EXISTS properties_grid_coords_index"
  end
end
