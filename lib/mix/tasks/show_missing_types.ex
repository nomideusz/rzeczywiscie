defmodule Mix.Tasks.ShowMissingTypes do
  @moduledoc """
  Show properties missing types in the terminal.
  Usage: mix show_missing_types [limit]
  
  Examples:
    mix show_missing_types        # Show 20 properties
    mix show_missing_types 50     # Show 50 properties
    mix show_missing_types all    # Show all properties
  """

  use Mix.Task
  import Ecto.Query
  require Logger

  @shortdoc "Show properties missing types in terminal"
  def run(args) do
    Mix.Task.run("app.start")

    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    limit = case args do
      ["all"] -> nil
      [num] -> String.to_integer(num)
      _ -> 20
    end

    # Query for active properties missing types
    query = from(p in Property,
      where: p.active == true and (is_nil(p.transaction_type) or is_nil(p.property_type)),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        title: p.title,
        url: p.url,
        transaction_type: p.transaction_type,
        property_type: p.property_type
      }
    )

    query = if limit, do: limit(query, ^limit), else: query

    properties = Repo.all(query)
    total_missing = Repo.aggregate(
      from(p in Property,
        where: p.active == true and (is_nil(p.transaction_type) or is_nil(p.property_type))
      ),
      :count, :id
    )

    Logger.info("=== Properties Missing Types ===")
    Logger.info("Total active properties missing types: #{total_missing}")
    Logger.info("Showing: #{length(properties)}\n")

    Enum.each(properties, fn p ->
      IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
      IO.puts("ID: #{p.id} | Source: #{p.source}")
      
      # Show missing types in red
      trans_status = if p.transaction_type do
        "✓ #{p.transaction_type}"
      else
        "✗ MISSING"
      end
      
      prop_status = if p.property_type do
        "✓ #{p.property_type}"
      else
        "✗ MISSING"
      end
      
      IO.puts("Transaction: #{trans_status}")
      IO.puts("Property: #{prop_status}")
      IO.puts("\nTitle: #{p.title || "N/A"}")
      IO.puts("URL: #{p.url || "N/A"}")
      IO.puts("")
    end)

    if limit && total_missing > limit do
      IO.puts("\n... and #{total_missing - limit} more")
      IO.puts("\nTo see more, run: mix show_missing_types #{limit + 20}")
      IO.puts("To see all, run: mix show_missing_types all")
      IO.puts("To export to CSV, run: mix export_missing_types")
    end
  end
end

