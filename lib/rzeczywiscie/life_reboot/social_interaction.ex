defmodule Rzeczywiscie.LifeReboot.SocialInteraction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "social_interactions" do
    field :interaction_type, :string
    field :duration_minutes, :integer
    field :quality, :integer
    field :initiated_by_me, :boolean, default: true
    field :location, :string
    field :left_house, :boolean, default: false
    field :interacted_at, :utc_datetime
    field :notes, :string
    field :mood_before, :integer
    field :mood_after, :integer

    belongs_to :contact, Rzeczywiscie.LifeReboot.SocialContact

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [
      :contact_id, :interaction_type, :duration_minutes, :quality,
      :initiated_by_me, :location, :left_house, :interacted_at,
      :notes, :mood_before, :mood_after
    ])
    |> validate_required([:interaction_type, :interacted_at])
    |> validate_inclusion(:interaction_type, ["call", "text", "in_person", "video", "voice_message"])
    |> validate_number(:quality, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:mood_before, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:mood_after, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end

  @doc """
  Check if this interaction was meaningful (quality >= 3 and lasted > 10 min)
  """
  def meaningful?(%__MODULE__{} = interaction) do
    (interaction.quality || 0) >= 3 and (interaction.duration_minutes || 0) > 10
  end
end

