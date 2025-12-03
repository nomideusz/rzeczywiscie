defmodule Rzeczywiscie.Friends.Room do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_rooms" do
    field :code, :string
    field :name, :string
    field :emoji, :string, default: "📸"
    field :created_by, :string

    has_many :photos, Rzeczywiscie.Friends.Photo

    timestamps()
  end

  @doc false
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:code, :name, :emoji, :created_by])
    |> validate_required([:code])
    |> validate_length(:code, min: 2, max: 32)
    |> validate_format(:code, ~r/^[a-z0-9-]+$/, message: "only lowercase letters, numbers, and dashes")
    |> unique_constraint(:code)
  end

  @doc """
  Generate a random room code.
  """
  def generate_code do
    adjectives = ~w(happy sunny cozy wild chill rad cool epic fresh groovy funky mellow)
    nouns = ~w(cats dogs pizza tacos vibes crew gang squad fam peeps homies)
    
    adj = Enum.random(adjectives)
    noun = Enum.random(nouns)
    num = :rand.uniform(99)
    
    "#{adj}-#{noun}-#{num}"
  end
end

