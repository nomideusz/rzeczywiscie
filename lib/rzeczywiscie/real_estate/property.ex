defmodule Rzeczywiscie.RealEstate.Property do
  use Ecto.Schema
  import Ecto.Changeset

  schema "properties" do
    field :source, :string
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :price, :decimal
    field :currency, :string
    field :area_sqm, :decimal
    field :rooms, :integer
    field :floor, :integer

    # Property classification
    field :transaction_type, :string  # "sprzedaż", "wynajem"
    field :property_type, :string     # "mieszkanie", "dom", "pokój", "garaż", etc.

    # Location
    field :city, :string
    field :district, :string
    field :street, :string
    field :postal_code, :string
    field :voivodeship, :string

    # Coordinates
    field :latitude, :decimal
    field :longitude, :decimal

    # URLs and metadata
    field :url, :string
    field :image_url, :string
    field :raw_data, :map

    # Status
    field :active, :boolean, default: true
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(property, attrs) do
    property
    |> cast(attrs, [
      :source,
      :external_id,
      :title,
      :description,
      :price,
      :currency,
      :area_sqm,
      :rooms,
      :floor,
      :transaction_type,
      :property_type,
      :city,
      :district,
      :street,
      :postal_code,
      :voivodeship,
      :latitude,
      :longitude,
      :url,
      :image_url,
      :raw_data,
      :active,
      :last_seen_at
    ])
    |> validate_required([:source, :external_id, :title, :url])
    |> validate_inclusion(:source, ["olx", "otodom", "gratka"])
    |> validate_inclusion(:transaction_type, ["sprzedaż", "wynajem", nil])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:area_sqm, greater_than: 0)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> unique_constraint([:source, :external_id])
  end
end
