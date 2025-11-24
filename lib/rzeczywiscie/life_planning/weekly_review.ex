defmodule Rzeczywiscie.LifePlanning.WeeklyReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "weekly_reviews" do
    field :week_start_date, :date
    field :wins, :string
    field :challenges, :string
    field :learnings, :string
    field :next_week_focus, :string
    field :notes, :string
    field :completed_tasks_count, :integer, default: 0
    field :projects_reviewed, {:array, :integer}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(weekly_review, attrs) do
    weekly_review
    |> cast(attrs, [:week_start_date, :wins, :challenges, :learnings, :next_week_focus, :notes, :completed_tasks_count, :projects_reviewed])
    |> validate_required([:week_start_date])
    |> unique_constraint(:week_start_date)
  end

  @doc """
  Gets the start of the week (Monday) for a given date.
  """
  def week_start(date \\ Date.utc_today()) do
    day_of_week = Date.day_of_week(date)
    # Monday = 1, Sunday = 7
    days_to_subtract = day_of_week - 1
    Date.add(date, -days_to_subtract)
  end
end
