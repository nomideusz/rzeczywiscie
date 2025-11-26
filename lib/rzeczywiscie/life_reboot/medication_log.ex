defmodule Rzeczywiscie.LifeReboot.MedicationLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "medication_logs" do
    field :medication_name, :string, default: "Concerta"
    field :prescribed_dose_mg, :integer
    field :actual_dose_mg, :integer
    field :pills_taken, :integer, default: 1
    field :taken_at, :utc_datetime
    field :scheduled_time, :time
    field :feeling_before, :integer
    field :feeling_after, :integer
    field :crash_time, :time
    field :crash_severity, :integer
    field :notes, :string
    field :is_as_prescribed, :boolean, default: true
    field :trigger, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :medication_name, :prescribed_dose_mg, :actual_dose_mg, :pills_taken, :taken_at,
      :scheduled_time, :feeling_before, :feeling_after, :crash_time,
      :crash_severity, :notes, :is_as_prescribed, :trigger
    ])
    |> validate_required([:taken_at, :pills_taken])
    |> validate_number(:pills_taken, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:feeling_before, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:feeling_after, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:crash_severity, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_inclusion(:trigger, ["stress", "work", "boredom", "anxiety", "social", "other"])
  end

  @doc """
  Determines if this dose was an abuse pattern (took more than prescribed)
  """
  def abuse_pattern?(%__MODULE__{} = log) do
    cond do
      is_nil(log.prescribed_dose_mg) -> false
      is_nil(log.actual_dose_mg) -> false
      log.actual_dose_mg > log.prescribed_dose_mg -> true
      true -> false
    end
  end

  @doc """
  Returns a human-friendly description of the dose situation
  """
  def dose_status(%__MODULE__{} = log) do
    cond do
      is_nil(log.prescribed_dose_mg) or is_nil(log.actual_dose_mg) ->
        :unknown
      log.actual_dose_mg == log.prescribed_dose_mg ->
        :as_prescribed
      log.actual_dose_mg > log.prescribed_dose_mg ->
        :over
      log.actual_dose_mg < log.prescribed_dose_mg ->
        :under
      true ->
        :unknown
    end
  end
end
