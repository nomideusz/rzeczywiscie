defmodule Rzeczywiscie.LifePlanning.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :phase, :string
    field :completed, :boolean, default: false
    field :completed_at, :utc_datetime
    field :order, :integer, default: 0
    field :is_next_action, :boolean, default: false

    belongs_to :project, Rzeczywiscie.LifePlanning.LifeProject

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :phase, :completed, :completed_at, :order, :is_next_action, :project_id])
    |> validate_required([:title, :project_id])
    |> validate_number(:order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for marking a task as completed
  """
  def complete_changeset(task) do
    task
    |> change(%{
      completed: true,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for marking a task as incomplete
  """
  def incomplete_changeset(task) do
    task
    |> change(%{
      completed: false,
      completed_at: nil
    })
  end
end
