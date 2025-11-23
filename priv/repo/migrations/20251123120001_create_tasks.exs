defmodule Rzeczywiscie.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :project_id, references(:life_projects, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :phase, :string
      add :completed, :boolean, default: false
      add :completed_at, :utc_datetime
      add :order, :integer, default: 0
      add :is_next_action, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:completed])
    create index(:tasks, [:is_next_action])
    create index(:tasks, [:project_id, :order])
  end
end
