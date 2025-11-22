defmodule Rzeczywiscie.AirQuality.Cache do
  use Ecto.Schema
  import Ecto.Changeset

  schema "air_quality_cache" do
    field :lat, :decimal
    field :lng, :decimal
    field :aqi, :integer
    field :category, :string
    field :dominant_pollutant, :string
    field :pm25, :decimal
    field :pm10, :decimal
    field :o3, :decimal
    field :no2, :decimal
    field :fetched_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, [
      :lat,
      :lng,
      :aqi,
      :category,
      :dominant_pollutant,
      :pm25,
      :pm10,
      :o3,
      :no2,
      :fetched_at,
      :expires_at
    ])
    |> validate_required([:lat, :lng, :fetched_at, :expires_at])
    |> validate_number(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:lng, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> unique_constraint([:lat, :lng])
  end
end
