defmodule Rzeczywiscie.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :title, :string, null: false
      add :description, :text
      add :color, :string, default: "#3b82f6"
      add :status, :string, default: "active"
      add :progress_pct, :integer, default: 0
      add :target_date, :date
      add :order, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:order])
    create index(:projects, [:status])
  end
end
