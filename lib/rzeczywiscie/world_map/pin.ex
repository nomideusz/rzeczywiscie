defmodule Rzeczywiscie.WorldMap.Pin do
  use Ecto.Schema
  import Ecto.Changeset

  schema "world_map_pins" do
    field :user_name, :string
    field :user_color, :string
    field :lat, :float
    field :lng, :float
    field :message, :string
    field :emoji, :string
    field :ip_address, :string
    field :country, :string
    field :city, :string
    timestamps()
  end

  @doc false
  def changeset(pin, attrs) do
    pin
    |> cast(attrs, [:user_name, :user_color, :lat, :lng, :message, :emoji, :ip_address, :country, :city])
    |> validate_required([:user_name, :user_color, :lat, :lng])
    |> validate_number(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
  end
end
