defmodule Rzeczywiscie.Workers.AlertWorker do
  @moduledoc """
  Oban worker that runs the saved-search alerts and emails new matches.

  Scheduled hourly, offset from the scrapers so a run sees a finished scrape
  rather than a half-written one.

  Options (via job args):
    - alert_id: run only this alert (default: every enabled alert)
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Rzeczywiscie.Alerts

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    progress = fn msg -> Rzeczywiscie.JobProgress.report(job, msg) end

    if Alerts.configured?() do
      run(args, progress)
    else
      # Not an error: an install without mail env vars should keep running,
      # it just has nowhere to send.
      Logger.info("AlertWorker: mail is not configured, skipping")
      progress.("skipped — mail not configured")
      :ok
    end
  end

  defp run(%{"alert_id" => alert_id}, progress) when not is_nil(alert_id) do
    case Alerts.get_alert(alert_id) do
      nil ->
        Logger.warning("AlertWorker: alert #{alert_id} no longer exists")
        progress.("alert #{alert_id} not found")
        :ok

      alert ->
        case Alerts.run_alert(alert) do
          {:ok, :no_matches} ->
            progress.("#{alert.name} — no new listings")
            :ok

          {:ok, {:sent, count}} ->
            progress.("#{alert.name} — emailed #{count} listing(s)")
            :ok

          {:error, reason} ->
            progress.("#{alert.name} — failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp run(_args, progress) do
    summary = Alerts.run_all(progress: progress)

    Logger.info(
      "AlertWorker completed: #{summary.emails_sent}/#{summary.alerts} alert(s) emailed, " <>
        "#{summary.listings_notified} listing(s), #{summary.failed} failed"
    )

    progress.(
      "done — #{summary.emails_sent} email(s), #{summary.listings_notified} listing(s)" <>
        if(summary.failed > 0, do: ", #{summary.failed} failed", else: "")
    )

    # A failed alert retries on the next tick with the same pending listings;
    # failing the job here would only re-send the ones that did go out.
    :ok
  end

  @doc """
  Manually trigger an alert run.

  Options:
    - alert_id: run only this alert (default: every enabled alert)
  """
  def trigger(opts \\ []) do
    case Keyword.get(opts, :alert_id) do
      nil -> %{}
      alert_id -> %{"alert_id" => alert_id}
    end
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
