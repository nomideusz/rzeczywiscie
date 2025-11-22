defmodule Rzeczywiscie.Repo.Migrations.CreateAirQualityCache do
  use Ecto.Migration

  def change do
    create table(:air_quality_cache) do
      # Location (rounded to grid for efficient caching)
      add :lat, :decimal, precision: 10, scale: 6, null: false
      add :lng, :decimal, precision: 11, scale: 6, null: false

      # Air Quality Index data
      add :aqi, :integer
      add :category, :string  # Good, Moderate, Unhealthy, etc.
      add :dominant_pollutant, :string  # pm25, pm10, o3, etc.

      # Detailed pollutant data (optional)
      add :pm25, :decimal, precision: 10, scale: 2
      add :pm10, :decimal, precision: 10, scale: 2
      add :o3, :decimal, precision: 10, scale: 2
      add :no2, :decimal, precision: 10, scale: 2

      # Cache metadata
      add :fetched_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # Index for location lookup (grid-based)
    create index(:air_quality_cache, [:lat, :lng])

    # Index for finding expired entries
    create index(:air_quality_cache, [:expires_at])

    # Composite unique index to prevent duplicate cache entries
    create unique_index(:air_quality_cache, [:lat, :lng])
  end
end
