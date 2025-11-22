defmodule Rzeczywiscie.Repo.Migrations.CleanupInvalidAreaData do
  use Ecto.Migration

  def up do
    # Clean up properties with obviously wrong area values
    # Set to NULL if area is:
    # - Greater than 100,000 m² (unrealistic for residential properties)
    # - Less than 1 m² (too small to be valid)

    execute """
    UPDATE properties
    SET area_sqm = NULL
    WHERE area_sqm > 100000 OR area_sqm < 1
    """
  end

  def down do
    # Cannot restore bad data, so this is a no-op
    :ok
  end
end
