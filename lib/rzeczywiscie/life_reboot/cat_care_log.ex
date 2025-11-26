defmodule Rzeczywiscie.LifeReboot.CatCareLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cat_care_logs" do
    field :cat_name, :string
    field :activity, :string
    field :logged_at, :utc_datetime
    field :duration_minutes, :integer
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @activities ["fed", "played", "brushed", "vet", "cuddle", "cleaned_litter", "treats", "medication"]

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:cat_name, :activity, :logged_at, :duration_minutes, :notes])
    |> validate_required([:activity, :logged_at])
    |> validate_inclusion(:activity, @activities)
  end

  @doc """
  Returns emoji for activity type
  """
  def activity_emoji(activity) do
    case activity do
      "fed" -> "🍽️"
      "played" -> "🎾"
      "brushed" -> "🪮"
      "vet" -> "🏥"
      "cuddle" -> "🤗"
      "cleaned_litter" -> "🧹"
      "treats" -> "🍬"
      "medication" -> "💊"
      _ -> "🐱"
    end
  end

  @doc """
  Returns all available activities
  """
  def activities, do: @activities
end

