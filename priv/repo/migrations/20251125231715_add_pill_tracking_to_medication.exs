defmodule Rzeczywiscie.Repo.Migrations.AddPillTrackingToMedication do
  use Ecto.Migration

  def change do
    alter table(:medication_logs) do
      add :pills_taken, :integer, default: 1
    end

    alter table(:medication_settings) do
      add :pills_per_day_prescribed, :integer, default: 2
      add :pills_per_day_max_allowed, :integer, default: 2
      add :taper_start_date, :date
      add :taper_end_date, :date
      add :taper_from_pills, :integer
      add :taper_to_pills, :integer
    end

    # Index already exists from earlier migration
  end
end
