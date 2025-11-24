defmodule Rzeczywiscie.Repo.Migrations.AddDeadlineToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :deadline, :date
    end

    # Add index for querying tasks by deadline
    create index(:tasks, [:deadline])
    create index(:tasks, [:deadline, :completed])
  end
end
