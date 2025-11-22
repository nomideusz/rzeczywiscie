defmodule Rzeczywiscie.Repo.Migrations.FixNumericPrecision do
  use Ecto.Migration

  def up do
    # Fix area_sqm precision in properties table
    # Old: precision: 8, scale: 2 (max 999,999.99)
    # New: precision: 10, scale: 2 (max 99,999,999.99)
    alter table(:properties) do
      modify :area_sqm, :decimal, precision: 10, scale: 2
    end

    # Add precision to price_history decimal fields
    # These were created without precision/scale specified
    alter table(:price_history) do
      modify :price, :decimal, precision: 12, scale: 2, null: false
      modify :price_per_sqm, :decimal, precision: 10, scale: 2
      modify :change_percentage, :decimal, precision: 5, scale: 2
    end
  end

  def down do
    # Revert changes
    alter table(:properties) do
      modify :area_sqm, :decimal, precision: 8, scale: 2
    end

    alter table(:price_history) do
      modify :price, :decimal, null: false
      modify :price_per_sqm, :decimal
      modify :change_percentage, :decimal
    end
  end
end
