defmodule Rzeczywiscie.Alerts.Alert do
  @moduledoc """
  A saved search the owner wants to be emailed about.

  `criteria` holds the same filter keys the listing page sends
  (`Rzeczywiscie.RealEstate.list_properties/1`), stored as a plain map with
  string keys so it round-trips through jsonb. `Rzeczywiscie.Alerts.to_filters/1`
  is the only thing that turns it back into query options, and it whitelists
  every key — nothing here reaches the query builder unchecked.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Rzeczywiscie.RealEstate.Voivodeships
  alias Rzeczywiscie.Services.Jev

  # jev_yes / jev_no: lists of Jev yes/no question ids the answer must match
  @criteria_keys ~w(search city voivodeship min_price max_price min_area max_area rooms source transaction_type property_type jev_yes jev_no)

  schema "property_alerts" do
    field :name, :string
    field :criteria, :map, default: %{}
    field :enabled, :boolean, default: true
    # Listings at or below this id existed before the alert; never reported
    field :since_property_id, :integer, default: 0
    field :last_run_at, :utc_datetime
    field :last_notified_at, :utc_datetime
    field :notified_count, :integer, default: 0

    has_many :matches, Rzeczywiscie.Alerts.AlertMatch, foreign_key: :alert_id

    timestamps(type: :utc_datetime)
  end

  @doc "Filter keys an alert may carry."
  def criteria_keys, do: @criteria_keys

  @doc false
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :name,
      :criteria,
      :enabled,
      :since_property_id,
      :last_run_at,
      :last_notified_at,
      :notified_count
    ])
    |> update_change(:criteria, &clean_criteria/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_criteria()
    |> validate_jev_questions()
  end

  @doc false
  def run_changeset(alert, attrs) do
    cast(alert, attrs, [:last_run_at, :last_notified_at, :notified_count])
  end

  # Drop unknown keys and blanks so an alert never carries dead criteria, and
  # numeric fields survive coming in as strings from the admin form.
  defp clean_criteria(criteria) when is_map(criteria) do
    criteria
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.filter(fn {k, v} -> k in @criteria_keys and present?(v) end)
    |> Enum.map(&cast_value/1)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp clean_criteria(_), do: %{}

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  @numeric_keys ~w(min_price max_price min_area max_area)

  defp cast_value({key, value}) when key in @numeric_keys, do: {key, to_number(value)}
  defp cast_value({"rooms", value}), do: {"rooms", to_integer(value)}

  defp cast_value({key, ids}) when key in ~w(jev_yes jev_no) do
    case ids |> List.wrap() |> Enum.uniq() |> Enum.sort() do
      [] -> {key, nil}
      ids -> {key, ids}
    end
  end

  defp cast_value({key, value}) when is_binary(value), do: {key, String.trim(value)}
  defp cast_value(pair), do: pair

  defp to_number(value) when is_number(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(String.replace(value, ",", ".")) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_), do: nil

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp to_integer(_), do: nil

  # An unsupported region would otherwise be silently ignored at query time,
  # leaving an alert that quietly matches the whole country.
  defp validate_criteria(changeset) do
    criteria = get_field(changeset, :criteria) || %{}

    case Map.get(criteria, "voivodeship") do
      nil ->
        changeset

      value ->
        if Voivodeships.supported?(value) do
          changeset
        else
          add_error(changeset, :criteria, "unknown region: #{value}")
        end
    end
  end

  # An unknown question has no stored answers, so the alert would match nothing
  # while still asking Jev about every candidate.
  defp validate_jev_questions(changeset) do
    criteria = get_field(changeset, :criteria) || %{}

    unknown =
      (List.wrap(criteria["jev_yes"]) ++ List.wrap(criteria["jev_no"]))
      |> Enum.reject(&(&1 in Jev.noul_ids()))

    case unknown do
      [] -> changeset
      _ -> add_error(changeset, :criteria, "unknown Jev question: #{Enum.join(unknown, ", ")}")
    end
  end
end
