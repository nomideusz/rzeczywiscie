defmodule Rzeczywiscie.Workers.CleanupWorker do
  @moduledoc """
  Oban worker for cleaning up stale property listings.
  Marks properties as inactive if they haven't been seen in 96 hours (4 days).
  Scheduled to run daily at 3 AM via cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Rzeczywiscie.RealEstate

  # Stale threshold: 96 hours = 4 days
  @stale_hours 96

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    hours = Map.get(args, "hours", @stale_hours)

    Logger.info("CleanupWorker starting: marking properties inactive if not seen in #{hours} hours")

    {count, _} = RealEstate.mark_stale_properties_inactive(hours)

    Logger.info("CleanupWorker completed: marked #{count} properties as inactive")

    :ok
  end

  @doc """
  Manually trigger a cleanup job.
  """
  def trigger(opts \\ []) do
    %{"hours" => Keyword.get(opts, :hours, @stale_hours)}
    |> __MODULE__.new()
    |> Oban.insert()
  end
  
  @doc """
  Returns the stale threshold in hours.
  """
  def stale_hours, do: @stale_hours
end
