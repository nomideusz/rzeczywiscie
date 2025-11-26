defmodule Rzeczywiscie.LifeReboot do
  @moduledoc """
  The LifeReboot context - a personalized life management system.

  This is NOT a generic habit tracker. It's designed for someone with:
  - ADHD medication management challenges
  - Debt to pay off
  - Loneliness and desire to move out
  - Job dissatisfaction
  - Two cats to care for

  No shame. Just honest tracking and gentle encouragement.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo

  alias Rzeczywiscie.LifeReboot.{
    MedicationLog,
    MedicationSettings,
    Debt,
    DebtPayment,
    SocialContact,
    SocialInteraction,
    CatCareLog,
    MoodLog,
    HonestCheckin
  }

  @topic "life_reboot"

  # ============================================
  # PubSub
  # ============================================

  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {event, payload})
  end

  # ============================================
  # MEDICATION TRACKING
  # ============================================

  def list_medication_logs(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    MedicationLog
    |> where([m], m.taken_at >= ^cutoff)
    |> order_by([m], desc: m.taken_at)
    |> Repo.all()
  end

  def get_medication_log!(id), do: Repo.get!(MedicationLog, id)

  def create_medication_log(attrs) do
    %MedicationLog{}
    |> MedicationLog.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast(:medication_logged, &1))
  end

  def get_medication_settings do
    MedicationSettings
    |> where([s], s.active == true)
    |> order_by([s], desc: s.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def create_medication_settings(attrs) do
    %MedicationSettings{}
    |> MedicationSettings.changeset(attrs)
    |> Repo.insert()
  end

  def update_medication_settings(%MedicationSettings{} = settings, attrs) do
    settings
    |> MedicationSettings.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get medication abuse patterns for analysis
  """
  def get_medication_patterns(days \\ 30) do
    logs = list_medication_logs(days)

    %{
      total_logs: length(logs),
      as_prescribed: Enum.count(logs, & &1.is_as_prescribed),
      over_prescribed: Enum.count(logs, &MedicationLog.abuse_pattern?/1),
      common_triggers: logs
        |> Enum.map(& &1.trigger)
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> -count end),
      average_crash_severity: logs
        |> Enum.map(& &1.crash_severity)
        |> Enum.reject(&is_nil/1)
        |> average()
    }
  end

  def took_meds_today? do
    pills_taken_today() > 0
  end

  @doc """
  Count total pills taken today
  """
  def pills_taken_today do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    today_end = Date.utc_today() |> DateTime.new!(~T[23:59:59], "Etc/UTC")

    MedicationLog
    |> where([m], m.taken_at >= ^today_start and m.taken_at <= ^today_end)
    |> select([m], coalesce(sum(m.pills_taken), 0))
    |> Repo.one()
  end

  @doc """
  Get the current max allowed pills based on settings and taper schedule
  """
  def current_max_pills_allowed do
    case get_medication_settings() do
      nil -> 2  # Default to prescribed amount
      settings -> MedicationSettings.current_max_allowed(settings)
    end
  end

  @doc """
  Check if user is within their allowed pill limit for today
  """
  def within_pill_limit? do
    pills_taken_today() < current_max_pills_allowed()
  end

  @doc """
  Get remaining pills allowed today
  """
  def pills_remaining_today do
    max(0, current_max_pills_allowed() - pills_taken_today())
  end

  @doc """
  Get medication status summary for dashboard
  """
  def get_medication_status do
    settings = get_medication_settings()
    taken = pills_taken_today()
    max_allowed = current_max_pills_allowed()
    prescribed = if settings, do: settings.pills_per_day_prescribed, else: 2

    %{
      pills_taken_today: taken,
      pills_max_allowed: max_allowed,
      pills_prescribed: prescribed,
      pills_remaining: max(0, max_allowed - taken),
      over_limit: taken > max_allowed,
      at_limit: taken >= max_allowed,
      taper_status: if(settings, do: MedicationSettings.taper_status(settings), else: :no_taper),
      allowance_description: if(settings, do: MedicationSettings.allowance_description(settings), else: "2 pills/day")
    }
  end

  @doc """
  Initialize default medication settings for Concerta
  """
  def ensure_medication_settings do
    case get_medication_settings() do
      nil ->
        # Set up with 1-week taper: 3 pills allowed for 7 days, then 2
        taper_end = Date.utc_today() |> Date.add(7)

        create_medication_settings(%{
          "medication_name" => "Concerta",
          "prescribed_dose_mg" => 36,  # Standard Concerta dose
          "scheduled_time" => ~T[08:00:00],
          "pills_per_day_prescribed" => 2,
          "pills_per_day_max_allowed" => 3,
          "taper_start_date" => Date.utc_today(),
          "taper_end_date" => taper_end,
          "taper_from_pills" => 3,
          "taper_to_pills" => 2,
          "active" => true
        })

      settings ->
        {:ok, settings}
    end
  end

  # ============================================
  # DEBT TRACKING
  # ============================================

  def list_debts(include_paid_off \\ false) do
    query = from d in Debt, order_by: [asc: d.priority, asc: d.current_amount]

    query = if include_paid_off do
      query
    else
      where(query, [d], d.paid_off == false)
    end

    Repo.all(query) |> Repo.preload(:payments)
  end

  def get_debt!(id), do: Repo.get!(Debt, id) |> Repo.preload(:payments)

  def create_debt(attrs) do
    %Debt{}
    |> Debt.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast(:debt_created, &1))
  end

  def update_debt(%Debt{} = debt, attrs) do
    debt
    |> Debt.changeset(attrs)
    |> Repo.update()
    |> tap_ok(&broadcast(:debt_updated, &1))
  end

  def delete_debt(%Debt{} = debt) do
    Repo.delete(debt)
  end

  def make_debt_payment(%Debt{} = debt, attrs) do
    Repo.transaction(fn ->
      # Create the payment
      payment_attrs = Map.put(attrs, "debt_id", debt.id)

      {:ok, payment} =
        %DebtPayment{}
        |> DebtPayment.changeset(payment_attrs)
        |> Repo.insert()

      # Update debt current amount
      new_amount = Decimal.sub(debt.current_amount, payment.amount)
      new_amount = if Decimal.compare(new_amount, Decimal.new(0)) == :lt, do: Decimal.new(0), else: new_amount

      paid_off = Decimal.compare(new_amount, Decimal.new(0)) == :eq

      {:ok, updated_debt} =
        debt
        |> Debt.changeset(%{
          current_amount: new_amount,
          paid_off: paid_off,
          paid_off_at: if(paid_off, do: DateTime.utc_now(), else: nil)
        })
        |> Repo.update()

      broadcast(:payment_made, %{debt: updated_debt, payment: payment})

      {updated_debt, payment}
    end)
  end

  def get_debt_stats do
    debts = list_debts(false)

    total_owed = debts
      |> Enum.map(& &1.current_amount)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    total_original = debts
      |> Enum.map(& &1.original_amount)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    total_paid = Decimal.sub(total_original, total_owed)

    %{
      total_debts: length(debts),
      total_owed: total_owed,
      total_original: total_original,
      total_paid: total_paid,
      progress_percent: if(Decimal.compare(total_original, 0) == :gt,
        do: Decimal.div(total_paid, total_original) |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_float(),
        else: 0.0
      )
    }
  end

  # ============================================
  # SOCIAL CONNECTIONS
  # ============================================

  def list_contacts(active_only \\ true) do
    query = from c in SocialContact, order_by: [asc: c.name]

    query = if active_only do
      where(query, [c], c.active == true)
    else
      query
    end

    Repo.all(query)
  end

  def get_contact!(id), do: Repo.get!(SocialContact, id)

  def create_contact(attrs) do
    %SocialContact{}
    |> SocialContact.changeset(attrs)
    |> Repo.insert()
  end

  def update_contact(%SocialContact{} = contact, attrs) do
    contact
    |> SocialContact.changeset(attrs)
    |> Repo.update()
  end

  def list_interactions(days \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    SocialInteraction
    |> where([i], i.interacted_at >= ^cutoff)
    |> order_by([i], desc: i.interacted_at)
    |> Repo.all()
    |> Repo.preload(:contact)
  end

  def create_interaction(attrs) do
    %SocialInteraction{}
    |> SocialInteraction.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast(:interaction_logged, &1))
  end

  def days_since_meaningful_interaction do
    last_meaningful =
      SocialInteraction
      |> where([i], i.quality >= 3 and i.duration_minutes > 10)
      |> order_by([i], desc: i.interacted_at)
      |> limit(1)
      |> Repo.one()

    case last_meaningful do
      nil -> 999  # Never had one
      interaction ->
        Date.diff(Date.utc_today(), DateTime.to_date(interaction.interacted_at))
    end
  end

  @doc """
  Days since ANY social interaction (not just meaningful ones)
  """
  def days_since_any_interaction do
    last_interaction =
      SocialInteraction
      |> order_by([i], desc: i.interacted_at)
      |> limit(1)
      |> Repo.one()

    case last_interaction do
      nil -> nil  # No interactions ever
      interaction ->
        Date.diff(Date.utc_today(), DateTime.to_date(interaction.interacted_at))
    end
  end

  def days_since_left_house do
    last_outing =
      SocialInteraction
      |> where([i], i.left_house == true)
      |> order_by([i], desc: i.interacted_at)
      |> limit(1)
      |> Repo.one()

    case last_outing do
      nil -> 999
      interaction ->
        Date.diff(Date.utc_today(), DateTime.to_date(interaction.interacted_at))
    end
  end

  def get_social_stats do
    interactions = list_interactions(30)

    %{
      total_interactions: length(interactions),
      meaningful_count: Enum.count(interactions, &SocialInteraction.meaningful?/1),
      times_left_house: Enum.count(interactions, & &1.left_house),
      days_since_meaningful: days_since_meaningful_interaction(),
      days_since_left_house: days_since_left_house(),
      mood_improvement: interactions
        |> Enum.filter(fn i -> i.mood_before && i.mood_after end)
        |> Enum.map(fn i -> i.mood_after - i.mood_before end)
        |> average()
    }
  end

  # ============================================
  # CAT CARE
  # ============================================

  def list_cat_care_logs(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    CatCareLog
    |> where([c], c.logged_at >= ^cutoff)
    |> order_by([c], desc: c.logged_at)
    |> Repo.all()
  end

  def create_cat_care_log(attrs) do
    %CatCareLog{}
    |> CatCareLog.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast(:cat_care_logged, &1))
  end

  def fed_cats_today? do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    CatCareLog
    |> where([c], c.logged_at >= ^today_start and c.activity == "fed")
    |> Repo.exists?()
  end

  def played_with_cats_today? do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    CatCareLog
    |> where([c], c.logged_at >= ^today_start and c.activity == "played")
    |> Repo.exists?()
  end

  # ============================================
  # MOOD TRACKING
  # ============================================

  def list_mood_logs(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    MoodLog
    |> where([m], m.logged_at >= ^cutoff)
    |> order_by([m], desc: m.logged_at)
    |> Repo.all()
  end

  def create_mood_log(attrs) do
    %MoodLog{}
    |> MoodLog.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(&broadcast(:mood_logged, &1))
  end

  def get_mood_trends(days \\ 14) do
    logs = list_mood_logs(days)

    %{
      average_mood: logs |> Enum.map(& &1.mood) |> average(),
      average_energy: logs |> Enum.map(& &1.energy) |> Enum.reject(&is_nil/1) |> average(),
      average_anxiety: logs |> Enum.map(& &1.anxiety) |> Enum.reject(&is_nil/1) |> average(),
      average_job_dread: logs |> Enum.map(& &1.job_dread) |> Enum.reject(&is_nil/1) |> average(),
      days_took_meds: Enum.count(logs, & &1.took_meds),
      days_went_outside: Enum.count(logs, & &1.went_outside),
      days_talked_to_someone: Enum.count(logs, & &1.talked_to_someone)
    }
  end

  # ============================================
  # HONEST CHECK-INS
  # ============================================

  def get_today_honest_checkin do
    HonestCheckin
    |> where([c], c.date == ^Date.utc_today())
    |> Repo.one()
  end

  def upsert_honest_checkin(attrs) do
    date = attrs["date"] || Date.utc_today()

    case Repo.get_by(HonestCheckin, date: date) do
      nil ->
        %HonestCheckin{}
        |> HonestCheckin.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> HonestCheckin.changeset(attrs)
        |> Repo.update()
    end
    |> tap_ok(&broadcast(:honest_checkin_saved, &1))
  end

  def list_honest_checkins(days \\ 30) do
    cutoff = Date.utc_today() |> Date.add(-days)

    HonestCheckin
    |> where([c], c.date >= ^cutoff)
    |> order_by([c], desc: c.date)
    |> Repo.all()
  end

  def calculate_honest_streak do
    checkins =
      HonestCheckin
      |> where([c], not is_nil(c.completed_at))
      |> order_by([c], desc: c.date)
      |> Repo.all()

    count_consecutive_days(checkins, Date.utc_today(), 0)
  end

  defp count_consecutive_days([], _expected_date, count), do: count
  defp count_consecutive_days([checkin | rest], expected_date, count) do
    if Date.compare(checkin.date, expected_date) == :eq do
      count_consecutive_days(rest, Date.add(expected_date, -1), count + 1)
    else
      count
    end
  end

  # ============================================
  # DASHBOARD DATA
  # ============================================

  def get_life_dashboard_data do
    %{
      # Medication
      took_meds_today: took_meds_today?(),
      medication_status: get_medication_status(),
      medication_patterns: get_medication_patterns(14),

      # Debt
      debt_stats: get_debt_stats(),
      debts: list_debts(),

      # Social
      social_stats: get_social_stats(),
      days_since_meaningful_interaction: days_since_meaningful_interaction(),
      days_since_any_interaction: days_since_any_interaction(),
      days_since_left_house: days_since_left_house(),

      # Cats
      fed_cats_today: fed_cats_today?(),
      played_with_cats_today: played_with_cats_today?(),

      # Mood
      mood_trends: get_mood_trends(7),

      # Check-in
      today_checkin: get_today_honest_checkin(),
      checkin_streak: calculate_honest_streak()
    }
  end

  @doc """
  Get weekly history data for the past 7 days
  """
  def get_weekly_history do
    today = Date.utc_today()
    days = for i <- 6..0//-1, do: Date.add(today, -i)

    Enum.map(days, fn date ->
      %{
        date: date,
        day_name: Calendar.strftime(date, "%a"),
        is_today: date == today,
        meds: get_pills_for_date(date),
        social: had_social_on_date?(date),
        mood: get_mood_for_date(date),
        checkin: had_checkin_on_date?(date)
      }
    end)
  end

  defp get_pills_for_date(date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    MedicationLog
    |> where([m], m.taken_at >= ^start_dt and m.taken_at <= ^end_dt)
    |> select([m], coalesce(sum(m.pills_taken), 0))
    |> Repo.one()
  end

  defp had_social_on_date?(date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    SocialInteraction
    |> where([s], s.interacted_at >= ^start_dt and s.interacted_at <= ^end_dt)
    |> Repo.exists?()
  end

  defp get_mood_for_date(date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    MoodLog
    |> where([m], m.logged_at >= ^start_dt and m.logged_at <= ^end_dt)
    |> select([m], avg(m.mood))
    |> Repo.one()
    |> case do
      nil -> nil
      avg -> Float.round(Decimal.to_float(avg), 1)
    end
  end

  defp had_checkin_on_date?(date) do
    HonestCheckin
    |> where([c], c.date == ^date and not is_nil(c.completed_at))
    |> Repo.exists?()
  end

  # ============================================
  # HELPERS
  # ============================================

  defp average([]), do: nil
  defp average(list) do
    sum = Enum.sum(list)
    Float.round(sum / length(list), 1)
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end
  defp tap_ok(error, _fun), do: error
end

