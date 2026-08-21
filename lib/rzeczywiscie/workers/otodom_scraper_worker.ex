defmodule Rzeczywiscie.Workers.OtodomScraperWorker do
  @moduledoc """
  Oban worker for scraping Otodom.pl listings on a schedule.
  
  Options (via job args):
    - pages: Number of pages to scrape per search (default: 2)
    - delay: Delay between requests in ms (default: 3000)
    - enrich: If true, auto-enriches missing data after scraping (default: false)
    - voivodeships: Regions to scrape (default: all supported regions)
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    priority: 1

  require Logger
  alias Rzeczywiscie.RealEstate.Voivodeships
  alias Rzeczywiscie.Scrapers.OtodomScraper

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    pages = Map.get(args, "pages", 2)  # Scrape 2 pages by default
    delay = Map.get(args, "delay", 3000)  # 3 second delay to be respectful
    enrich = Map.get(args, "enrich", false)
    voivodeships = Map.get(args, "voivodeships")

    regions = Voivodeships.resolve(voivodeships) |> Enum.map(& &1.label) |> Enum.join(", ")

    Logger.info("Starting scheduled Otodom scrape: #{pages} page(s) of #{regions}#{if enrich, do: " + enrichment", else: ""}")

    case OtodomScraper.scrape(
           pages: pages,
           delay: delay,
           enrich: enrich,
           voivodeships: voivodeships,
           progress: fn msg -> Rzeczywiscie.JobProgress.report(job, msg) end
         ) do
      {:ok, %{total: total, saved: saved}} ->
        Logger.info("Otodom scrape job completed: #{saved}/#{total} properties saved")
        :ok

      {:error, reason} ->
        Logger.error("Otodom scrape job failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Manually trigger a scrape job.
  
  Options:
    - pages: Number of pages to scrape per search (default: 2)
    - delay: Delay between requests in ms (default: 3000)
    - enrich: If true, auto-enriches missing data after scraping (default: false)
    - voivodeships: Regions to scrape (default: all supported regions)
  """
  def trigger(opts \\ []) do
    %{
      "pages" => Keyword.get(opts, :pages, 2),
      "delay" => Keyword.get(opts, :delay, 3000),
      "enrich" => Keyword.get(opts, :enrich, false),
      "voivodeships" => Keyword.get(opts, :voivodeships, Voivodeships.slugs())
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
