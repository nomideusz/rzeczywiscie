defmodule Rzeczywiscie.RealEstate.Favorite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "favorites" do
    belongs_to :property, Rzeczywiscie.RealEstate.Property

    field :user_id, :string
    field :notes, :string
    field :alert_on_price_drop, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:property_id, :user_id, :notes, :alert_on_price_drop])
    |> validate_required([:property_id, :user_id])
    |> unique_constraint([:property_id, :user_id])
    |> foreign_key_constraint(:property_id)
  end
end
