defmodule Rzeczywiscie.LifeTracker.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :title, :string
    field :description, :string
    field :color, :string, default: "#3b82f6"
    field :status, :string, default: "active"
    field :progress_pct, :integer, default: 0
    field :target_date, :date
    field :order, :integer, default: 0

    has_many :tasks, Rzeczywiscie.LifeTracker.Task
    has_many :milestones, Rzeczywiscie.LifeTracker.Milestone

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :title,
      :description,
      :color,
      :status,
      :progress_pct,
      :target_date,
      :order
    ])
    |> validate_required([:title])
    |> validate_inclusion(:status, ["active", "paused", "completed", "archived"])
    |> validate_number(:progress_pct, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
