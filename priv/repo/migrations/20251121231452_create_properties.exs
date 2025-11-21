defmodule Rzeczywiscie.Repo.Migrations.CreateProperties do
  use Ecto.Migration

  def change do
    create table(:properties) do
      add :source, :string, null: false
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :price, :decimal, precision: 10, scale: 2
      add :currency, :string, default: "PLN"
      add :area_sqm, :decimal, precision: 8, scale: 2
      add :rooms, :integer
      add :floor, :integer

      # Location fields
      add :city, :string
      add :district, :string
      add :street, :string
      add :postal_code, :string
      add :voivodeship, :string, default: "małopolskie"

      # Coordinates for map integration
      add :latitude, :decimal, precision: 10, scale: 8
      add :longitude, :decimal, precision: 11, scale: 8

      # Original data
      add :url, :string, null: false
      add :image_url, :string
      add :raw_data, :map

      # Status tracking
      add :active, :boolean, default: true
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Unique constraint per source
    create unique_index(:properties, [:source, :external_id])

    # Index for location queries
    create index(:properties, [:city])
    create index(:properties, [:voivodeship])

    # Index for price range queries
    create index(:properties, [:price])

    # Index for area queries
    create index(:properties, [:area_sqm])

    # Index for active properties
    create index(:properties, [:active])

    # Spatial index for coordinates (if we use PostGIS later)
    create index(:properties, [:latitude, :longitude])
  end
end
