defmodule Rzeczywiscie.Workers.OlxScraperWorker do
  @moduledoc """
  Oban worker for scraping OLX properties.
  Scheduled to run every 30 minutes via cron.
  
  Options (via job args):
    - pages: Number of pages to scrape (default: 3)
    - delay: Delay between requests in ms (default: 2000)
    - enrich: If true, auto-enriches missing data after scraping (default: false)
  """

  use Oban.Worker, queue: :scraper, max_attempts: 3

  require Logger
  alias Rzeczywiscie.Scrapers.OlxScraper

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    pages = Map.get(args, "pages", 3)
    delay = Map.get(args, "delay", 2000)
    enrich = Map.get(args, "enrich", false)

    Logger.info("OlxScraperWorker starting: scraping #{pages} page(s)#{if enrich, do: " + enrichment", else: ""}")

    case OlxScraper.scrape(pages: pages, delay: delay, enrich: enrich) do
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
  
  Options:
    - pages: Number of pages to scrape (default: 3)
    - delay: Delay between requests in ms (default: 2000)
    - enrich: If true, auto-enriches missing data after scraping (default: false)
  """
  def trigger(opts \\ []) do
    %{
      "pages" => Keyword.get(opts, :pages, 3),
      "delay" => Keyword.get(opts, :delay, 2000),
      "enrich" => Keyword.get(opts, :enrich, false)
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
