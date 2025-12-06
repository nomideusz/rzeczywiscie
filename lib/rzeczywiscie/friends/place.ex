defmodule Rzeczywiscie.Friends.Place do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_places" do
    field :user_id, :string
    field :user_name, :string
    field :user_color, :string
    field :name, :string
    field :description, :string
    field :lat, :float
    field :lng, :float
    field :emoji, :string, default: "📍"

    belongs_to :room, Rzeczywiscie.Friends.Room

    timestamps()
  end

  @doc false
  def changeset(place, attrs) do
    place
    |> cast(attrs, [:room_id, :user_id, :user_name, :user_color, :name, :description, :lat, :lng, :emoji])
    |> validate_required([:user_id, :name, :lat, :lng])
    |> validate_length(:name, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_number(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
  end
end

