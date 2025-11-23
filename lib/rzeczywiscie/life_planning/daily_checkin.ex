defmodule Rzeczywiscie.LifePlanning.DailyCheckin do
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_checkins" do
    field :date, :date
    field :completed_task_ids, {:array, :integer}, default: []
    field :tomorrow_focus, :string
    field :notes, :string

    belongs_to :tomorrow_project, Rzeczywiscie.LifePlanning.LifeProject

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daily_checkin, attrs) do
    daily_checkin
    |> cast(attrs, [:date, :completed_task_ids, :tomorrow_focus, :tomorrow_project_id, :notes])
    |> validate_required([:date])
    |> unique_constraint(:date)
  end
end
