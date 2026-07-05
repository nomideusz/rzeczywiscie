defmodule Rzeczywiscie.Repo.Migrations.AddPricePositionToProperties do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      # percent vs archive median zł/m² for comparable listings (negative = below median)
      add :price_vs_median, :integer
      # sample size the median was computed from
      add :price_median_n, :integer
    end
  end
end
