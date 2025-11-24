defmodule Rzeczywiscie.Repo.Migrations.CreateWeeklyReviews do
  use Ecto.Migration

  def change do
    create table(:weekly_reviews) do
      add :week_start_date, :date, null: false
      add :wins, :text
      add :challenges, :text
      add :learnings, :text
      add :next_week_focus, :text
      add :notes, :text
      add :completed_tasks_count, :integer, default: 0
      add :projects_reviewed, {:array, :integer}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_reviews, [:week_start_date])
    create index(:weekly_reviews, [:inserted_at])
  end
end
