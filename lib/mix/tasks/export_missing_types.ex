defmodule Mix.Tasks.ExportMissingTypes do
  @moduledoc """
  Export properties missing transaction_type or property_type to a CSV file.
  Usage: mix export_missing_types [--all] [--output filename.csv]
  
  Options:
    --all         Include inactive properties (default: active only)
    --output      Output filename (default: missing_types.csv)
  """

  use Mix.Task
  import Ecto.Query
  require Logger

  @shortdoc "Export properties missing types to CSV"
  def run(args) do
    Mix.Task.run("app.start")

    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, 
      switches: [all: :boolean, output: :string],
      aliases: [a: :all, o: :output]
    )

    include_inactive = Keyword.get(opts, :all, false)
    output_file = Keyword.get(opts, :output, "missing_types.csv")

    Logger.info("Exporting properties missing types...")
    Logger.info("Include inactive: #{include_inactive}")
    Logger.info("Output file: #{output_file}")

    # Build query
    query = from(p in Property,
      where: is_nil(p.transaction_type) or is_nil(p.property_type),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        active: p.active,
        inserted_at: p.inserted_at
      }
    )

    query = if include_inactive do
      query
    else
      where(query, [p], p.active == true)
    end

    properties = Repo.all(query)

    Logger.info("Found #{length(properties)} properties missing types")

    if length(properties) == 0 do
      Logger.info("No properties to export!")
    else
      # Write CSV
      csv_content = generate_csv(properties)
      File.write!(output_file, csv_content)
      
      Logger.info("✓ Exported to #{output_file}")
      Logger.info("\nSummary:")
      Logger.info("  Total exported: #{length(properties)}")
      
      missing_both = Enum.count(properties, fn p -> 
        is_nil(p.transaction_type) && is_nil(p.property_type) 
      end)
      missing_transaction = Enum.count(properties, fn p -> 
        is_nil(p.transaction_type) && !is_nil(p.property_type)
      end)
      missing_property = Enum.count(properties, fn p -> 
        !is_nil(p.transaction_type) && is_nil(p.property_type)
      end)
      
      Logger.info("  Missing both types: #{missing_both}")
      Logger.info("  Missing transaction only: #{missing_transaction}")
      Logger.info("  Missing property only: #{missing_property}")
      
      # Group by source
      by_source = Enum.group_by(properties, & &1.source)
      Logger.info("\nBy source:")
      Enum.each(by_source, fn {source, props} ->
        Logger.info("  #{source}: #{length(props)} properties")
      end)
    end

    :ok
  end

  defp generate_csv(properties) do
    # CSV Header
    header = "ID,Source,External ID,Active,Transaction Type,Property Type,Title,URL,Inserted At\n"
    
    # CSV Rows
    rows = Enum.map(properties, fn p ->
      [
        p.id,
        p.source,
        escape_csv(p.external_id),
        p.active,
        escape_csv(p.transaction_type || ""),
        escape_csv(p.property_type || ""),
        escape_csv(p.title),
        escape_csv(p.url),
        p.inserted_at
      ]
      |> Enum.join(",")
    end)
    |> Enum.join("\n")
    
    header <> rows <> "\n"
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(value) when is_binary(value) do
    # Escape quotes and wrap in quotes if contains comma, quote, or newline
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      escaped = String.replace(value, "\"", "\"\"")
      "\"#{escaped}\""
    else
      value
    end
  end
  defp escape_csv(value), do: to_string(value)
end

