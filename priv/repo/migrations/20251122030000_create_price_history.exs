defmodule Rzeczywiscie.Repo.Migrations.CreatePriceHistory do
  use Ecto.Migration

  def change do
    create table(:price_history) do
      add :property_id, references(:properties, on_delete: :delete_all), null: false
      add :price, :decimal, null: false
      add :price_per_sqm, :decimal
      add :currency, :string, default: "PLN"
      add :change_percentage, :decimal
      add :detected_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:price_history, [:property_id])
    create index(:price_history, [:detected_at])
    create index(:price_history, [:property_id, :detected_at])
  end
end
