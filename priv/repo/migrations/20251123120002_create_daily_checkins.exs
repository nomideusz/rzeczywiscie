defmodule Rzeczywiscie.Repo.Migrations.CreateDailyCheckins do
  use Ecto.Migration

  def change do
    create table(:daily_checkins) do
      add :date, :date, null: false
      add :completed_task_ids, {:array, :integer}, default: []
      add :tomorrow_focus, :text
      add :tomorrow_project_id, references(:life_projects, on_delete: :nilify_all)
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_checkins, [:date])
  end
end
