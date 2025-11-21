defmodule Rzeczywiscie.Workers.OlxScraperWorker do
  @moduledoc """
  Oban worker for scraping OLX properties.
  Scheduled to run every 30 minutes via cron.
  """

  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger
  alias Rzeczywiscie.Scrapers.OlxScraper

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    pages = Map.get(args, "pages", 3)
    delay = Map.get(args, "delay", 2000)

    Logger.info("OlxScraperWorker starting: scraping #{pages} page(s)")

    case OlxScraper.scrape(pages: pages, delay: delay) do
      {:ok, result} ->
        Logger.info("OlxScraperWorker completed: #{result.saved}/#{result.total} properties saved")
        :ok

      {:error, reason} ->
        Logger.error("OlxScraperWorker failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Manually trigger a scrape job.
  Useful for testing or manual refreshes.
  """
  def trigger(opts \\ []) do
    %{
      "pages" => Keyword.get(opts, :pages, 3),
      "delay" => Keyword.get(opts, :delay, 2000)
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
