defmodule Rzeczywiscie.Repo.Migrations.AddJevSignalsToProperties do
  use Ecto.Migration

  def change do
    alter table(:properties) do
      # raw TypeSafe Jev answers (Services.Jev), kept verbatim so thresholds
      # and weights can change without asking the model again
      add :jev_signals, :map
      add :jev_analyzed_at, :utc_datetime
    end
  end
end
