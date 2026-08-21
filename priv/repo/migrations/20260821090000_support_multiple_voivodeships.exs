defmodule Rzeczywiscie.Repo.Migrations.SupportMultipleVoivodeships do
  use Ecto.Migration

  # The app now aggregates more than one region (małopolskie + podkarpackie),
  # so a column default of "małopolskie" would silently mislabel any row
  # inserted without an explicit voivodeship. Both scrapers always set it now;
  # anything else is better off NULL than wrong.
  #
  # The listing page always filters on active, so region filtering wants the
  # composite rather than the standalone voivodeship index.
  def up do
    alter table(:properties) do
      modify :voivodeship, :string, default: nil
    end

    create index(:properties, [:active, :voivodeship])
  end

  def down do
    drop index(:properties, [:active, :voivodeship])

    alter table(:properties) do
      modify :voivodeship, :string, default: "małopolskie"
    end
  end
end
