defmodule Rzeczywiscie.LifeReboot.HonestCheckin do
  use Ecto.Schema
  import Ecto.Changeset

  schema "honest_checkins" do
    field :date, :date
    field :completed_at, :utc_datetime

    # Medication honesty
    field :meds_taken_as_prescribed, :boolean
    field :meds_notes, :string

    # Job situation
    field :job_dread_level, :integer
    field :applied_to_jobs, :integer, default: 0
    field :job_search_minutes, :integer, default: 0
    field :job_notes, :string

    # Financial honesty
    field :unnecessary_spending, :decimal
    field :debt_payment_made, :boolean
    field :money_notes, :string

    # Social/isolation
    field :talked_to_friend, :boolean
    field :left_apartment, :boolean
    field :loneliness_level, :integer

    # Cat care (accountability anchor)
    field :fed_cats, :boolean
    field :played_with_cats, :boolean

    # Wins and struggles
    field :small_win, :string
    field :biggest_struggle, :string
    field :tomorrow_intention, :string

    # Overall
    field :overall_day_rating, :integer
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(checkin, attrs) do
    checkin
    |> cast(attrs, [
      :date, :completed_at, :meds_taken_as_prescribed, :meds_notes,
      :job_dread_level, :applied_to_jobs, :job_search_minutes, :job_notes,
      :unnecessary_spending, :debt_payment_made, :money_notes,
      :talked_to_friend, :left_apartment, :loneliness_level,
      :fed_cats, :played_with_cats, :small_win, :biggest_struggle,
      :tomorrow_intention, :overall_day_rating, :notes
    ])
    |> validate_required([:date])
    |> validate_number(:job_dread_level, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:loneliness_level, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:overall_day_rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:applied_to_jobs, greater_than_or_equal_to: 0)
    |> validate_number(:job_search_minutes, greater_than_or_equal_to: 0)
    |> unique_constraint(:date)
  end

  @doc """
  Calculate a "life score" for the day based on key indicators
  """
  def life_score(%__MODULE__{} = checkin) do
    scores = [
      if(checkin.meds_taken_as_prescribed, do: 20, else: 0),
      if(checkin.talked_to_friend, do: 15, else: 0),
      if(checkin.left_apartment, do: 10, else: 0),
      if(checkin.fed_cats, do: 10, else: 0),
      if(checkin.played_with_cats, do: 5, else: 0),
      if(checkin.debt_payment_made, do: 15, else: 0),
      if(checkin.applied_to_jobs && checkin.applied_to_jobs > 0, do: 15, else: 0),
      if(checkin.small_win && String.trim(checkin.small_win) != "", do: 10, else: 0)
    ]

    Enum.sum(scores)
  end

  @doc """
  Returns encouragement message based on life score
  """
  def encouragement_message(%__MODULE__{} = checkin) do
    score = life_score(checkin)

    cond do
      score >= 80 -> "🌟 Incredible day! You're doing amazing!"
      score >= 60 -> "💪 Great progress! Keep this momentum!"
      score >= 40 -> "👍 Solid effort today. Every step counts!"
      score >= 20 -> "🌱 You showed up. That matters."
      true -> "🫂 Tough day. Tomorrow is a fresh start."
    end
  end

  @doc """
  Identify areas that need attention
  """
  def attention_areas(%__MODULE__{} = checkin) do
    areas = []

    areas = if !checkin.meds_taken_as_prescribed, do: ["medication" | areas], else: areas
    areas = if !checkin.talked_to_friend && checkin.loneliness_level && checkin.loneliness_level >= 7, do: ["social" | areas], else: areas
    areas = if !checkin.left_apartment, do: ["isolation" | areas], else: areas
    areas = if checkin.job_dread_level && checkin.job_dread_level >= 8, do: ["job" | areas], else: areas
    areas = if checkin.unnecessary_spending && Decimal.compare(checkin.unnecessary_spending, Decimal.new(0)) == :gt, do: ["spending" | areas], else: areas

    areas
  end
end

