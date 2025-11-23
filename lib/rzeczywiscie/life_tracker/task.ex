defmodule Rzeczywiscie.LifeTracker.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "not_started"
    field :phase, :string
    field :order, :integer, default: 0
    field :estimated_days, :integer
    field :actual_days, :integer
    field :dependencies, {:array, :integer}, default: []
    field :completed_at, :utc_datetime

    belongs_to :project, Rzeczywiscie.LifeTracker.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :project_id,
      :title,
      :description,
      :status,
      :phase,
      :order,
      :estimated_days,
      :actual_days,
      :dependencies,
      :completed_at
    ])
    |> validate_required([:project_id, :title])
    |> validate_inclusion(:status, ["not_started", "in_progress", "blocked", "completed"])
    |> foreign_key_constraint(:project_id)
  end
end
