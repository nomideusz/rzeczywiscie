defmodule Rzeczywiscie.Repo.Migrations.CreateDailyLogs do
  use Ecto.Migration

  def change do
    create table(:daily_logs) do
      add :date, :date, null: false
      add :notes, :text
      add :tasks_completed_count, :integer, default: 0
      add :mood, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_logs, [:date])
  end
end
