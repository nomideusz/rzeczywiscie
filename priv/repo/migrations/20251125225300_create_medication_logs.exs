defmodule Rzeczywiscie.Repo.Migrations.CreateMedicationLogs do
  use Ecto.Migration

  def change do
    create table(:medication_logs) do
      add :medication_name, :string, null: false, default: "Concerta"
      add :prescribed_dose_mg, :integer  # What you're supposed to take
      add :actual_dose_mg, :integer      # What you actually took (honesty mode)
      add :taken_at, :utc_datetime, null: false
      add :scheduled_time, :time         # When you should have taken it
      add :feeling_before, :integer      # 1-5 scale before taking
      add :feeling_after, :integer       # 1-5 scale hours after
      add :crash_time, :time             # When did the crash happen?
      add :crash_severity, :integer      # 1-5 how bad was the crash
      add :notes, :text                  # Any context
      add :is_as_prescribed, :boolean, default: true  # Quick flag
      add :trigger, :string              # What triggered taking more/less? (stress, work, boredom)

      timestamps(type: :utc_datetime)
    end

    create index(:medication_logs, [:taken_at])
    create index(:medication_logs, [:is_as_prescribed])

    # Medication settings/config
    create table(:medication_settings) do
      add :medication_name, :string, null: false, default: "Concerta"
      add :prescribed_dose_mg, :integer, null: false
      add :scheduled_time, :time, null: false
      add :prescriber, :string
      add :started_at, :date
      add :notes, :text
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end
  end
end
