defmodule Rzeczywiscie.Workers.DataMaintenanceWorker do
  @moduledoc """
  Oban worker for automated data maintenance tasks.
  
  Runs daily to:
  - Remove duplicate properties
  - Fix misclassified transaction types (rent vs sale)
  - Backfill missing districts from city field
  - Backfill missing cities from district data
  - Clear invalid prices (< 100 PLN)
  - Clear bad descriptions (CSS, navigation content)
  
  Scheduled to run daily at 4 AM via cron.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 3

  require Logger
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🧹 Data Maintenance Worker starting")
    
    results = []
    
    # 1. Remove duplicates
    dupes_result = remove_duplicates()
    results = ["Duplicates: #{dupes_result}" | results]
    
    # 2. Fix misclassified transaction types
    misclass_result = fix_misclassified()
    results = ["Misclassified: #{misclass_result}" | results]
    
    # 3. Backfill districts
    districts_result = backfill_districts()
    results = ["Districts: #{districts_result}" | results]
    
    # 4. Backfill cities
    cities_result = backfill_cities()
    results = ["Cities: #{cities_result}" | results]
    
    # 5. Clear invalid prices
    prices_result = clear_invalid_prices()
    results = ["Invalid prices: #{prices_result}" | results]
    
    # 6. Clear bad descriptions (CSS, navigation garbage)
    desc_result = clear_bad_descriptions()
    results = ["Bad descriptions: #{desc_result}" | results]
    
    Logger.info("🧹 Data Maintenance complete: #{Enum.join(Enum.reverse(results), ", ")}")
    
    :ok
  end

  defp remove_duplicates do
    duplicate_query = """
    WITH duplicates AS (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY url ORDER BY inserted_at) as rn
      FROM properties WHERE url IS NOT NULL
    )
    DELETE FROM properties WHERE id IN (SELECT id FROM duplicates WHERE rn > 1)
    """

    case Ecto.Adapters.SQL.query(Repo, duplicate_query, []) do
      {:ok, %{num_rows: count}} -> 
        if count > 0, do: Logger.info("  Removed #{count} duplicates")
        "#{count} removed"
      {:error, reason} -> 
        Logger.error("  Duplicate removal failed: #{inspect(reason)}")
        "error"
    end
  end

  defp fix_misclassified do
    case RealEstate.fix_misclassified_transaction_types() do
      {:ok, %{sales_to_rent: str, rent_to_sales: rts}} ->
        total = str + rts
        if total > 0, do: Logger.info("  Fixed #{str} sales→rent, #{rts} rent→sales")
        "#{total} fixed"
      {:error, _} ->
        "error"
    end
  end

  defp backfill_districts do
    count = RealEstate.backfill_districts_from_city()
    if count > 0, do: Logger.info("  Backfilled #{count} districts")
    "#{count} filled"
  end

  defp backfill_cities do
    count = RealEstate.backfill_cities_from_districts()
    if count > 0, do: Logger.info("  Backfilled #{count} cities")
    "#{count} filled"
  end

  defp clear_invalid_prices do
    case RealEstate.clear_invalid_prices() do
      {:ok, count} ->
        if count > 0, do: Logger.info("  Cleared #{count} invalid prices")
        "#{count} cleared"
      {:error, _} ->
        "error"
    end
  end

  defp clear_bad_descriptions do
    case RealEstate.clear_bad_descriptions() do
      {:ok, count} ->
        if count > 0, do: Logger.info("  Cleared #{count} bad descriptions (CSS/navigation)")
        "#{count} cleared"
      {:error, _} ->
        "error"
    end
  end

  @doc """
  Manually trigger the maintenance job.
  """
  def trigger do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end

