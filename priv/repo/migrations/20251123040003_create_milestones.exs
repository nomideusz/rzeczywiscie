defmodule Rzeczywiscie.Repo.Migrations.CreateMilestones do
  use Ecto.Migration

  def change do
    create table(:milestones) do
      add :project_id, references(:projects, on_delete: :delete_all)
      add :title, :string, null: false
      add :description, :text
      add :date_achieved, :date
      add :target_date, :date

      timestamps(type: :utc_datetime)
    end

    create index(:milestones, [:project_id])
    create index(:milestones, [:date_achieved])
  end
end
