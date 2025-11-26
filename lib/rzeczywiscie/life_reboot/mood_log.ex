defmodule Rzeczywiscie.LifeReboot.MoodLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mood_logs" do
    field :logged_at, :utc_datetime
    field :mood, :integer
    field :energy, :integer
    field :anxiety, :integer
    field :focus, :integer

    # Context flags
    field :took_meds, :boolean
    field :slept_well, :boolean
    field :ate_today, :boolean
    field :exercised, :boolean
    field :went_outside, :boolean
    field :talked_to_someone, :boolean
    field :worked_on_goals, :boolean

    # Job-specific
    field :job_dread, :integer
    field :at_work, :boolean

    # Financial
    field :spent_money_impulsively, :boolean
    field :worried_about_money, :boolean

    field :notes, :string
    field :gratitude, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :logged_at, :mood, :energy, :anxiety, :focus,
      :took_meds, :slept_well, :ate_today, :exercised,
      :went_outside, :talked_to_someone, :worked_on_goals,
      :job_dread, :at_work, :spent_money_impulsively,
      :worried_about_money, :notes, :gratitude
    ])
    |> validate_required([:logged_at, :mood])
    |> validate_number(:mood, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:energy, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:anxiety, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:focus, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:job_dread, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  @doc """
  Returns emoji for mood level
  """
  def mood_emoji(level) do
    case level do
      1 -> "😢"
      2 -> "😔"
      3 -> "😐"
      4 -> "🙂"
      5 -> "😊"
      _ -> "❓"
    end
  end

  @doc """
  Returns color class for mood level
  """
  def mood_color(level) do
    case level do
      1 -> "text-error"
      2 -> "text-warning"
      3 -> "text-base-content"
      4 -> "text-info"
      5 -> "text-success"
      _ -> "text-base-content"
    end
  end
end

