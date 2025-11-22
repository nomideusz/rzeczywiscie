defmodule Rzeczywiscie.Workers.OtodomScraperWorker do
  @moduledoc """
  Oban worker for scraping Otodom.pl listings on a schedule.
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    priority: 1

  require Logger
  alias Rzeczywiscie.Scrapers.OtodomScraper

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Starting scheduled Otodom scrape")

    pages = Map.get(args, "pages", 2)  # Scrape 2 pages by default
    delay = Map.get(args, "delay", 3000)  # 3 second delay to be respectful

    case OtodomScraper.scrape(pages: pages, delay: delay) do
      {:ok, %{total: total, saved: saved}} ->
        Logger.info("Otodom scrape job completed: #{saved}/#{total} properties saved")
        :ok

      {:error, reason} ->
        Logger.error("Otodom scrape job failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
