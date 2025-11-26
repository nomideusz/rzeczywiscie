defmodule Rzeczywiscie.LifeReboot.SocialContact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "social_contacts" do
    field :name, :string
    field :relationship, :string
    field :emoji, :string, default: "👤"
    field :contact_frequency_days, :integer, default: 14
    field :preferred_contact_method, :string
    field :notes, :string
    field :active, :boolean, default: true

    has_many :interactions, Rzeczywiscie.LifeReboot.SocialInteraction, foreign_key: :contact_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:name, :relationship, :emoji, :contact_frequency_days, :preferred_contact_method, :notes, :active])
    |> validate_required([:name])
    |> validate_number(:contact_frequency_days, greater_than: 0)
    |> validate_inclusion(:relationship, ["friend", "family", "colleague", "acquaintance", "other"])
    |> validate_inclusion(:preferred_contact_method, ["call", "text", "in_person", "video", "voice_message"])
  end
end

