defmodule Rzeczywiscie.Workers.CleanupWorker do
  @moduledoc """
  Oban worker for cleaning up stale property listings.
  Marks properties as inactive if they haven't been seen in 48 hours.
  Scheduled to run daily at 3 AM via cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Rzeczywiscie.RealEstate

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    hours = Map.get(args, "hours", 48)

    Logger.info("CleanupWorker starting: marking properties inactive if not seen in #{hours} hours")

    {count, _} = RealEstate.mark_stale_properties_inactive(hours)

    Logger.info("CleanupWorker completed: marked #{count} properties as inactive")

    :ok
  end

  @doc """
  Manually trigger a cleanup job.
  """
  def trigger(opts \\ []) do
    %{"hours" => Keyword.get(opts, :hours, 48)}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
