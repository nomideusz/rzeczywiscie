defmodule Rzeczywiscie.Alerts do
  @moduledoc """
  Email alerts for new listings.

  An alert is a saved search; every run reports the listings that have appeared
  since the alert was created and that it has not reported before. Delivery goes
  to one configured address (`ALERT_EMAIL_TO`) through our own mail server - see
  the mailer section in `config/runtime.exs`.

  Two properties are worth knowing about:

    * **No backlog on creation.** An alert records the highest property id that
      existed when it was created and only ever looks above it, so adding an
      alert never mails thousands of rows that are already in the database.
    * **Never twice.** Everything reported is written to `property_alert_matches`
      under a unique index, so retries, overlapping cron ticks and manual runs
      cannot re-send a listing.

  Criteria can also require Jev's yes/no answers (`jev_yes` / `jev_no`). Those
  are stored per listing, so a run first asks Jev about candidates that lack
  one, and a listing Jev hasn't answered waits rather than matching.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Rzeczywiscie.Alerts.Alert
  alias Rzeczywiscie.Alerts.AlertEmail
  alias Rzeczywiscie.Alerts.AlertMatch
  alias Rzeczywiscie.Mailer
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Services.Jev

  # Cap per email. Anything above this waits for the next run rather than
  # producing a mail nobody reads.
  @max_matches_per_email 40

  # Jev calls per alert per run (~300ms each). A backfill drains over runs.
  @jev_per_run 300

  ## Alerts CRUD

  @doc "All alerts, newest first."
  def list_alerts do
    Repo.all(from a in Alert, order_by: [desc: a.inserted_at])
  end

  @doc "Enabled alerts only - what the worker iterates."
  def list_enabled_alerts do
    Repo.all(from a in Alert, where: a.enabled == true, order_by: [asc: a.id])
  end

  def get_alert(id), do: Repo.get(Alert, id)

  def get_alert!(id), do: Repo.get!(Alert, id)

  @doc """
  Create an alert.

  The current highest property id is stamped on it, so the alert starts from
  "everything from here on" rather than mailing the whole existing database on
  its first run. Pass `since_property_id` explicitly to override that.
  """
  def create_alert(attrs) do
    attrs = put_new(attrs, :since_property_id, RealEstate.max_property_id())

    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
  end

  defp put_new(attrs, key, value) when is_map(attrs) do
    if Map.has_key?(attrs, key) or Map.has_key?(attrs, to_string(key)) do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  def update_alert(%Alert{} = alert, attrs) do
    alert
    |> Alert.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert(%Alert{} = alert), do: Repo.delete(alert)

  def toggle_alert(%Alert{} = alert) do
    update_alert(alert, %{enabled: !alert.enabled})
  end

  @doc "Alert changeset, for the admin form."
  def change_alert(%Alert{} = alert, attrs \\ %{}), do: Alert.changeset(alert, attrs)

  ## Matching

  @doc """
  Listings this alert should report next: active, matching its criteria, first
  seen after the alert was created, and not reported before.

  ## Options
    * `:limit` - maximum rows to return (default #{@max_matches_per_email})
  """
  def pending_matches(%Alert{} = alert, opts \\ []) do
    limit = Keyword.get(opts, :limit, @max_matches_per_email)

    alert
    |> pending_matches_query()
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "How many listings are waiting to be reported by this alert."
  def count_pending_matches(%Alert{} = alert) do
    alert
    |> pending_matches_query()
    |> Repo.aggregate(:count)
  end

  defp pending_matches_query(%Alert{} = alert) do
    already_notified =
      from m in AlertMatch,
        where: m.alert_id == ^alert.id,
        select: m.property_id

    alert.criteria
    |> to_filters()
    |> RealEstate.filter_query()
    |> where([p], p.id > ^alert.since_property_id)
    |> where([p], p.id not in subquery(already_notified))
  end

  @doc """
  Turn stored criteria into query options for `RealEstate.list_properties/1`.

  Only the keys `Alert.criteria_keys/0` names survive, and each becomes a known
  atom - nothing from the database reaches the query builder unchecked.
  """
  def to_filters(criteria) when is_map(criteria) do
    Enum.flat_map(criteria, fn {key, value} ->
      case filter_key(to_string(key)) do
        nil -> []
        atom -> [{atom, value}]
      end
    end)
  end

  def to_filters(_), do: []

  defp filter_key("search"), do: :search
  defp filter_key("city"), do: :city
  defp filter_key("voivodeship"), do: :voivodeship
  defp filter_key("min_price"), do: :min_price
  defp filter_key("max_price"), do: :max_price
  defp filter_key("min_area"), do: :min_area
  defp filter_key("max_area"), do: :max_area
  defp filter_key("rooms"), do: :rooms
  defp filter_key("source"), do: :source
  defp filter_key("transaction_type"), do: :transaction_type
  defp filter_key("property_type"), do: :property_type
  defp filter_key("jev_yes"), do: :jev_yes
  defp filter_key("jev_no"), do: :jev_no
  defp filter_key(_), do: nil

  ## Running

  @doc """
  Run every enabled alert. Returns a summary of what was sent.
  """
  def run_all(opts \\ []) do
    alerts = list_enabled_alerts()
    progress = Keyword.get(opts, :progress, fn _msg -> :ok end)
    total = length(alerts)

    results =
      alerts
      |> Enum.with_index(1)
      |> Enum.map(fn {alert, index} ->
        progress.("alert #{index}/#{total} — #{alert.name}")
        {alert, run_alert(alert)}
      end)

    sent = Enum.count(results, fn {_alert, result} -> match?({:ok, {:sent, _}}, result) end)

    notified =
      results
      |> Enum.map(fn
        {_alert, {:ok, {:sent, count}}} -> count
        {_alert, _} -> 0
      end)
      |> Enum.sum()

    failed = Enum.count(results, fn {_alert, result} -> match?({:error, _}, result) end)

    %{alerts: total, emails_sent: sent, listings_notified: notified, failed: failed}
  end

  @doc """
  Run one alert: find what it hasn't reported, email it, record it.

  Returns `{:ok, :no_matches}`, `{:ok, {:sent, count}}` or `{:error, reason}`.
  Nothing is recorded unless the email was accepted by the mail server, so a
  delivery failure simply means the same listings are retried next run.
  """
  def run_alert(%Alert{} = alert) do
    ask_jev(alert)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case pending_matches(alert) do
      [] ->
        mark_run(alert, now)
        {:ok, :no_matches}

      properties ->
        remaining = count_pending_matches(alert) - length(properties)

        case deliver_matches(alert, properties, remaining) do
          {:ok, _email} ->
            record_notified(alert, properties, now)
            Logger.info("Alert #{alert.id} (#{alert.name}): emailed #{length(properties)} listing(s)")
            {:ok, {:sent, length(properties)}}

          {:error, reason} ->
            mark_run(alert, now)
            Logger.error("Alert #{alert.id} (#{alert.name}) delivery failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Asks Jev about the alert's candidates that lack an answer it needs: new
  # listings, and ones asked before a question existed. Newest first.
  defp ask_jev(%Alert{criteria: criteria} = alert) do
    # A question retired since the alert was saved would never get an answer
    ids =
      (List.wrap(criteria["jev_yes"]) ++ List.wrap(criteria["jev_no"]))
      |> Enum.filter(&(&1 in Jev.noul_ids()))

    if ids != [] and Jev.configured?() do
      candidates =
        criteria
        |> Map.drop(["jev_yes", "jev_no"])
        |> to_filters()
        |> RealEstate.filter_query()
        |> where([p], p.id > ^alert.since_property_id)
        # The answers come from the text, so a listing without one yet waits
        |> where([p], fragment("length(?) > 0", p.description))
        |> where(
          [p],
          is_nil(p.jev_signals) or
            not fragment("(?->'answers') \\?& ?::text[]", p.jev_signals, ^ids)
        )
        |> order_by([p], desc: p.id)
        |> limit(@jev_per_run)
        |> Repo.all()

      Enum.reduce_while(candidates, 0, fn property, failures ->
        case Jev.analyze_and_store(property) do
          {:ok, _} ->
            {:cont, 0}

          {:error, reason} ->
            Logger.warning("Alert #{alert.id}: Jev failed for ##{property.id}: #{inspect(reason)}")
            # Three in a row means Jev is down; the next run picks up the rest
            if failures < 2, do: {:cont, failures + 1}, else: {:halt, failures + 1}
        end
      end)
    end
  end

  defp deliver_matches(alert, properties, remaining) do
    if configured?() do
      alert
      |> AlertEmail.new_listings(properties, remaining: remaining, to: alert_recipient())
      |> Mailer.deliver()
    else
      {:error, :not_configured}
    end
  end

  defp mark_run(alert, now) do
    alert
    |> Alert.run_changeset(%{last_run_at: now})
    |> Repo.update()
  end

  defp record_notified(alert, properties, now) do
    entries =
      Enum.map(properties, fn property ->
        %{
          alert_id: alert.id,
          property_id: property.id,
          notified_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.transaction(fn ->
      # on_conflict: :nothing keeps a partially-recorded retry from failing the
      # whole run - the unique index is the real guarantee here
      Repo.insert_all(AlertMatch, entries, on_conflict: :nothing)

      alert
      |> Alert.run_changeset(%{
        last_run_at: now,
        last_notified_at: now,
        notified_count: alert.notified_count + length(properties)
      })
      |> Repo.update!()
    end)
  end

  ## Mail configuration

  @doc """
  True when outgoing mail is configured (a from address and a recipient).

  With this false the app still runs; alert delivery reports
  `{:error, :not_configured}` and jobs finish without sending.
  """
  def configured? do
    present?(mail_config(:from)) and present?(alert_recipient())
  end

  @doc "Where alert digests are delivered."
  def alert_recipient, do: mail_config(:alert_to) || mail_config(:from)

  @doc "The From address alerts are sent as, as a `{name, address}` pair."
  def mail_sender, do: {mail_config(:from_name) || "Kruk.live", mail_config(:from)}

  @doc """
  Send a sample digest to the configured recipient, using whatever listings are
  in the database. Used by the admin panel to verify SMTP end to end.
  """
  def send_test_email do
    if configured?() do
      properties = RealEstate.list_properties(limit: 3)

      AlertEmail.test_email(properties, to: alert_recipient())
      |> Mailer.deliver()
    else
      {:error, :not_configured}
    end
  end

  defp mail_config(key) do
    :rzeczywiscie
    |> Application.get_env(:mail, [])
    |> Keyword.get(key)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
