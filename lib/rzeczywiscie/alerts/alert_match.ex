defmodule Rzeczywiscie.Alerts.AlertMatch do
  @moduledoc """
  One listing already reported by one alert.

  The unique index on `[alert_id, property_id]` is what keeps the alert worker
  idempotent - retries and overlapping runs cannot re-send a listing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "property_alert_matches" do
    belongs_to :alert, Rzeczywiscie.Alerts.Alert
    belongs_to :property, Rzeczywiscie.RealEstate.Property

    field :notified_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(match, attrs) do
    match
    |> cast(attrs, [:alert_id, :property_id, :notified_at])
    |> validate_required([:alert_id, :property_id, :notified_at])
    |> unique_constraint([:alert_id, :property_id])
    |> foreign_key_constraint(:alert_id)
    |> foreign_key_constraint(:property_id)
  end
end
