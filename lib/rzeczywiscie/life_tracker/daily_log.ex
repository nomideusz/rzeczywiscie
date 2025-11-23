defmodule Rzeczywiscie.LifeTracker.DailyLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_logs" do
    field :date, :date
    field :notes, :string
    field :tasks_completed_count, :integer, default: 0
    field :mood, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daily_log, attrs) do
    daily_log
    |> cast(attrs, [:date, :notes, :tasks_completed_count, :mood])
    |> validate_required([:date])
    |> unique_constraint(:date)
  end
end
