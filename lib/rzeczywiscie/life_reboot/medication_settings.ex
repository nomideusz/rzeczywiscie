defmodule Rzeczywiscie.LifeReboot.MedicationSettings do
  use Ecto.Schema
  import Ecto.Changeset

  schema "medication_settings" do
    field :medication_name, :string, default: "Concerta"
    field :prescribed_dose_mg, :integer
    field :scheduled_time, :time
    field :prescriber, :string
    field :started_at, :date
    field :notes, :string
    field :active, :boolean, default: true

    # Pill tracking with tapering support
    field :pills_per_day_prescribed, :integer, default: 2
    field :pills_per_day_max_allowed, :integer, default: 2
    field :taper_start_date, :date
    field :taper_end_date, :date
    field :taper_from_pills, :integer
    field :taper_to_pills, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :medication_name, :prescribed_dose_mg, :scheduled_time, :prescriber,
      :started_at, :notes, :active, :pills_per_day_prescribed, :pills_per_day_max_allowed,
      :taper_start_date, :taper_end_date, :taper_from_pills, :taper_to_pills
    ])
    |> validate_required([:medication_name, :prescribed_dose_mg, :scheduled_time])
    |> validate_number(:prescribed_dose_mg, greater_than: 0)
    |> validate_number(:pills_per_day_prescribed, greater_than: 0)
    |> validate_number(:pills_per_day_max_allowed, greater_than: 0)
  end

  @doc """
  Get the current max allowed pills based on tapering schedule.
  Returns the max_allowed if no taper is active, otherwise calculates based on date.
  """
  def current_max_allowed(%__MODULE__{} = settings) do
    today = Date.utc_today()

    cond do
      # No taper configured
      is_nil(settings.taper_start_date) or is_nil(settings.taper_end_date) ->
        settings.pills_per_day_max_allowed || settings.pills_per_day_prescribed || 2

      # Before taper starts
      Date.compare(today, settings.taper_start_date) == :lt ->
        settings.taper_from_pills || settings.pills_per_day_max_allowed || 3

      # After taper ends
      Date.compare(today, settings.taper_end_date) in [:gt, :eq] ->
        settings.taper_to_pills || settings.pills_per_day_prescribed || 2

      # During taper - return from_pills (taper happens at end date)
      true ->
        settings.taper_from_pills || settings.pills_per_day_max_allowed || 3
    end
  end

  @doc """
  Returns info about the current tapering status
  """
  def taper_status(%__MODULE__{} = settings) do
    today = Date.utc_today()

    cond do
      is_nil(settings.taper_start_date) or is_nil(settings.taper_end_date) ->
        :no_taper

      Date.compare(today, settings.taper_start_date) == :lt ->
        :before_taper

      Date.compare(today, settings.taper_end_date) in [:gt, :eq] ->
        :taper_complete

      true ->
        days_remaining = Date.diff(settings.taper_end_date, today)
        {:tapering, days_remaining}
    end
  end

  @doc """
  Human-friendly description of current pill allowance
  """
  def allowance_description(%__MODULE__{} = settings) do
    max = current_max_allowed(settings)
    prescribed = settings.pills_per_day_prescribed || 2

    case taper_status(settings) do
      :no_taper ->
        "#{max} pills/day allowed (prescribed: #{prescribed})"

      :before_taper ->
        days_until = Date.diff(settings.taper_start_date, Date.utc_today())
        "#{max} pills/day (taper starts in #{days_until} days)"

      :taper_complete ->
        "#{max} pills/day (taper complete)"

      {:tapering, days_remaining} ->
        "#{max} pills/day (#{days_remaining} days until #{settings.taper_to_pills}/day)"
    end
  end
end
