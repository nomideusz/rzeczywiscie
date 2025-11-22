defmodule Rzeczywiscie.Repo.Migrations.AddPropertyAndTransactionTypes do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      add :transaction_type, :string  # "sprzedaż" or "wynajem"
      add :property_type, :string     # "mieszkanie", "dom", "pokój", "garaż", etc.
    end

    # Add indexes for filtering
    create index(:properties, [:transaction_type])
    create index(:properties, [:property_type])
  end
end
