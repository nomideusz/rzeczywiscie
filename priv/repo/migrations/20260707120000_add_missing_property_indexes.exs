defmodule Rzeczywiscie.Repo.Migrations.AddMissingPropertyIndexes do
  use Ecto.Migration

  # district is filtered/grouped all over (deal scorer, price positions,
  # stats); the composite covers the most common listing filter combo.
  def change do
    create index(:properties, [:district])
    create index(:properties, [:active, :transaction_type, :property_type])
  end
end
