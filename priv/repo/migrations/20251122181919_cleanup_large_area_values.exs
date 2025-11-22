defmodule Rzeczywiscie.Repo.Migrations.CleanupLargeAreaValues do
  use Ecto.Migration

  def up do
    # Clean up properties with unrealistically large area values
    # These are parsing errors from the scraper (e.g., dates matched as areas)
    # Set to NULL if area is greater than 10,000 m² (realistic max for residential)
    # Values like 45,160 m², 2,045 m², 3,510 m² are clearly wrong

    execute """
    UPDATE properties
    SET area_sqm = NULL
    WHERE area_sqm > 10000
    """
  end

  def down do
    # Cannot restore bad data, so this is a no-op
    :ok
  end
end
