defmodule Rzeczywiscie.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for transaction_type filtering (common in queries)
    create_if_not_exists index(:properties, [:transaction_type])

    # Index for property_type filtering (common in queries)
    create_if_not_exists index(:properties, [:property_type])

    # Composite index for the most common query pattern:
    # WHERE active = true ORDER BY inserted_at DESC
    create_if_not_exists index(:properties, [:active, :inserted_at])

    # Index for source filtering
    create_if_not_exists index(:properties, [:source])

    # Composite index for active properties with coordinates (for map queries)
    create_if_not_exists index(:properties, [:active, :latitude, :longitude])
  end
end
