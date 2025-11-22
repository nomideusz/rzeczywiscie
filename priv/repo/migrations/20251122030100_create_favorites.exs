defmodule Rzeczywiscie.Repo.Migrations.CreateFavorites do
  use Ecto.Migration

  def change do
    create table(:favorites) do
      add :property_id, references(:properties, on_delete: :delete_all), null: false
      add :user_id, :string  # For now, use session ID or browser fingerprint
      add :notes, :text
      add :alert_on_price_drop, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:favorites, [:property_id])
    create index(:favorites, [:user_id])
    create unique_index(:favorites, [:property_id, :user_id])
  end
end
