defmodule Rzeczywiscie.Repo.Migrations.CreateCounters do
  use Ecto.Migration

  def change do
    create table(:counters) do
      add :name, :string, null: false
      add :value, :integer, default: 0, null: false
      timestamps()
    end

    create unique_index(:counters, [:name])
  end
end
