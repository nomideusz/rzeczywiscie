defmodule Rzeczywiscie.RealEstate.PriceHistory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "price_history" do
    belongs_to :property, Rzeczywiscie.RealEstate.Property

    field :price, :decimal
    field :price_per_sqm, :decimal
    field :currency, :string
    field :change_percentage, :decimal
    field :detected_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(price_history, attrs) do
    price_history
    |> cast(attrs, [:property_id, :price, :price_per_sqm, :currency, :change_percentage, :detected_at])
    |> validate_required([:property_id, :price, :detected_at])
    |> foreign_key_constraint(:property_id)
  end
end
