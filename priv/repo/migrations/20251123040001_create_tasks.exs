defmodule Rzeczywiscie.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "not_started"
      add :phase, :string
      add :order, :integer, default: 0
      add :estimated_days, :integer
      add :actual_days, :integer
      add :dependencies, {:array, :integer}, default: []
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:status])
    create index(:tasks, [:phase])
    create index(:tasks, [:project_id, :order])
  end
end
