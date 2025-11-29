defmodule Mix.Tasks.AnalyzeBackfill do
  @moduledoc """
  Analyze why backfill isn't updating all properties.
  Usage: mix analyze_backfill
  """

  use Mix.Task
  import Ecto.Query
  require Logger

  @shortdoc "Analyze properties and backfill coverage"
  def run(_) do
    Mix.Task.run("app.start")

    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    Logger.info("=== Property Backfill Analysis ===\n")

    # Total properties
    total = Repo.aggregate(Property, :count, :id)
    Logger.info("Total properties: #{total}")

    # Active vs inactive
    active = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)
    inactive = total - active
    Logger.info("  └─ Active: #{active} (#{percent(active, total)}%)")
    Logger.info("  └─ Inactive: #{inactive} (#{percent(inactive, total)}%)")

    # Of active, how many have types?
    active_with_both_types = Repo.aggregate(
      from(p in Property,
        where: p.active == true and
               not is_nil(p.transaction_type) and
               not is_nil(p.property_type)
      ),
      :count, :id
    )

    active_missing_transaction = Repo.aggregate(
      from(p in Property,
        where: p.active == true and is_nil(p.transaction_type)
      ),
      :count, :id
    )

    active_missing_property = Repo.aggregate(
      from(p in Property,
        where: p.active == true and is_nil(p.property_type)
      ),
      :count, :id
    )

    active_missing_both = Repo.aggregate(
      from(p in Property,
        where: p.active == true and
               is_nil(p.transaction_type) and
               is_nil(p.property_type)
      ),
      :count, :id
    )

    active_missing_any = Repo.aggregate(
      from(p in Property,
        where: p.active == true and
               (is_nil(p.transaction_type) or is_nil(p.property_type))
      ),
      :count, :id
    )

    Logger.info("\n=== Active Properties Type Status ===")
    Logger.info("Active with BOTH types: #{active_with_both_types} (#{percent(active_with_both_types, active)}%)")
    Logger.info("Active missing ANY type: #{active_missing_any} (#{percent(active_missing_any, active)}%)")
    Logger.info("  └─ Missing transaction_type: #{active_missing_transaction}")
    Logger.info("  └─ Missing property_type: #{active_missing_property}")
    Logger.info("  └─ Missing BOTH types: #{active_missing_both}")

    # Sample properties without types to see what they look like
    Logger.info("\n=== Sample Properties Missing Types ===")
    
    samples = from(p in Property,
      where: p.active == true and (is_nil(p.transaction_type) or is_nil(p.property_type)),
      limit: 10,
      select: %{
        id: p.id,
        url: p.url,
        title: p.title,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        source: p.source
      }
    )
    |> Repo.all()

    Enum.each(samples, fn p ->
      Logger.info("\nProperty ##{p.id} (#{p.source})")
      Logger.info("  Transaction: #{p.transaction_type || "MISSING"}")
      Logger.info("  Property: #{p.property_type || "MISSING"}")
      Logger.info("  Title: #{String.slice(p.title || "N/A", 0, 80)}")
      Logger.info("  URL: #{String.slice(p.url || "N/A", 0, 80)}")
    end)

    # Check by source
    Logger.info("\n=== By Source (Active Only) ===")
    
    by_source = from(p in Property,
      where: p.active == true,
      group_by: p.source,
      select: {
        p.source,
        count(p.id),
        fragment("COUNT(CASE WHEN ? IS NULL OR ? IS NULL THEN 1 END)", 
          p.transaction_type, p.property_type)
      }
    )
    |> Repo.all()

    Enum.each(by_source, fn {source, total, missing} ->
      Logger.info("#{source}: #{total} total, #{missing} missing types (#{percent(missing, total)}%)")
    end)

    Logger.info("\n=== Analysis Complete ===")
  end

  defp percent(_part, 0), do: 0
  defp percent(part, total), do: Float.round(part / total * 100, 1)
end

