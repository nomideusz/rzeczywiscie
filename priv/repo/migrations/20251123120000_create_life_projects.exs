defmodule Rzeczywiscie.Repo.Migrations.CreateLifeProjects do
  use Ecto.Migration

  def change do
    create table(:life_projects) do
      add :name, :string, null: false
      add :emoji, :string
      add :timeline_months, :integer
      add :color, :string
      add :order, :integer, default: 0
      add :archived, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:life_projects, [:order])
    create index(:life_projects, [:archived])
  end
end
