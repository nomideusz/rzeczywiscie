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
    field :deadline, :date

    belongs_to :project, Rzeczywiscie.LifePlanning.LifeProject

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :phase, :completed, :completed_at, :order, :is_next_action, :project_id, :deadline])
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
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
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

  @doc """
  Calculates the urgency level of a task based on its deadline.
  Returns: :overdue, :today, :this_week, :soon, :future, or nil
  """
  def urgency_level(task) do
    if task.completed || is_nil(task.deadline) do
      nil
    else
      today = Date.utc_today()
      days_until = Date.diff(task.deadline, today)

      cond do
        days_until < 0 -> :overdue
        days_until == 0 -> :today
        days_until <= 7 -> :this_week
        days_until <= 14 -> :soon
        true -> :future
      end
    end
  end

  @doc """
  Returns a CSS class for urgency badge based on urgency level.
  """
  def urgency_badge_class(urgency) do
    case urgency do
      :overdue -> "badge-error"
      :today -> "badge-warning"
      :this_week -> "badge-info"
      :soon -> "badge-ghost"
      :future -> "badge-ghost"
      _ -> ""
    end
  end

  @doc """
  Returns a human-readable text for urgency level.
  """
  def urgency_text(urgency) do
    case urgency do
      :overdue -> "Overdue!"
      :today -> "Due Today"
      :this_week -> "This Week"
      :soon -> "Due Soon"
      :future -> "Future"
      _ -> ""
    end
  end
end
