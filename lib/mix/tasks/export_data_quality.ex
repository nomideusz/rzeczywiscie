defmodule Mix.Tasks.ExportDataQuality do
  @moduledoc """
  Export properties with various data quality issues.
  Usage: mix export_data_quality [--type TYPE] [--output filename.csv]
  
  Types:
    missing_price    - Properties without price information
    missing_area     - Properties without area (m²)
    missing_rooms    - Properties without room count
    missing_coords   - Properties without coordinates
    incomplete       - Properties missing multiple key fields
    all             - All data quality issues (default)
  """

  use Mix.Task
  import Ecto.Query
  require Logger

  @shortdoc "Export properties with data quality issues"
  def run(args) do
    Mix.Task.run("app.start")

    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, 
      switches: [type: :string, output: :string, all: :boolean],
      aliases: [t: :type, o: :output, a: :all]
    )

    issue_type = Keyword.get(opts, :type, "all")
    output_file = Keyword.get(opts, :output, "data_quality_#{issue_type}.csv")

    Logger.info("Exporting data quality issues: #{issue_type}")
    Logger.info("Output file: #{output_file}")

    properties = case issue_type do
      "missing_price" -> get_missing_price()
      "missing_area" -> get_missing_area()
      "missing_rooms" -> get_missing_rooms()
      "missing_coords" -> get_missing_coords()
      "incomplete" -> get_incomplete()
      "all" -> get_all_issues()
      _ -> 
        Logger.error("Unknown type: #{issue_type}")
        Logger.info("Valid types: missing_price, missing_area, missing_rooms, missing_coords, incomplete, all")
        []
    end

    if length(properties) == 0 do
      Logger.info("No properties found with #{issue_type} issues!")
    else
      csv_content = generate_csv(properties, issue_type)
      File.write!(output_file, csv_content)
      
      Logger.info("✓ Exported #{length(properties)} properties to #{output_file}")
      print_summary(properties)
    end

    :ok
  end

  defp get_missing_price do
    from(p in Property,
      where: p.active == true and is_nil(p.price),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: "missing_price"
      }
    )
    |> Repo.all()
  end

  defp get_missing_area do
    from(p in Property,
      where: p.active == true and is_nil(p.area_sqm),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: "missing_area"
      }
    )
    |> Repo.all()
  end

  defp get_missing_rooms do
    from(p in Property,
      where: p.active == true and is_nil(p.rooms),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: "missing_rooms"
      }
    )
    |> Repo.all()
  end

  defp get_missing_coords do
    from(p in Property,
      where: p.active == true and (is_nil(p.latitude) or is_nil(p.longitude)),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: "missing_coords"
      }
    )
    |> Repo.all()
  end

  defp get_incomplete do
    # Properties missing 2+ key fields
    from(p in Property,
      where: p.active == true,
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: fragment("
          CASE 
            WHEN (? IS NULL)::int + (? IS NULL)::int + (? IS NULL)::int + 
                 ((? IS NULL OR ? IS NULL))::int >= 2 
            THEN 'incomplete_multiple'
            ELSE NULL 
          END", 
          p.price, p.area_sqm, p.rooms, p.latitude, p.longitude
        )
      }
    )
    |> Repo.all()
    |> Enum.reject(fn p -> is_nil(p.issue) end)
  end

  defp get_all_issues do
    # Get all properties with any data quality issue
    from(p in Property,
      where: p.active == true and (
        is_nil(p.price) or 
        is_nil(p.area_sqm) or 
        is_nil(p.rooms) or 
        is_nil(p.latitude) or 
        is_nil(p.longitude) or
        is_nil(p.transaction_type) or
        is_nil(p.property_type)
      ),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        city: p.city,
        latitude: p.latitude,
        longitude: p.longitude,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        issue: fragment("
          ARRAY_TO_STRING(ARRAY[
            CASE WHEN ? IS NULL THEN 'price' END,
            CASE WHEN ? IS NULL THEN 'area' END,
            CASE WHEN ? IS NULL THEN 'rooms' END,
            CASE WHEN ? IS NULL OR ? IS NULL THEN 'coords' END,
            CASE WHEN ? IS NULL THEN 'transaction_type' END,
            CASE WHEN ? IS NULL THEN 'property_type' END
          ]::text[], ',')
        ", p.price, p.area_sqm, p.rooms, p.latitude, p.longitude, p.transaction_type, p.property_type)
      }
    )
    |> Repo.all()
  end

  defp generate_csv(properties, _type) do
    header = "ID,Source,External ID,Price,Area (m²),Rooms,City,Coords,Transaction Type,Property Type,Issues,Title,URL\n"
    
    rows = Enum.map(properties, fn p ->
      coords_status = if Map.has_key?(p, :latitude) do
        if p.latitude && p.longitude, do: "✓", else: "✗"
      else
        "N/A"
      end
      
      [
        p.id,
        p.source,
        escape_csv(p.external_id),
        p.price || "",
        p.area_sqm || "",
        p.rooms || "",
        escape_csv(p.city || ""),
        coords_status,
        escape_csv(p.transaction_type || ""),
        escape_csv(p.property_type || ""),
        escape_csv(p.issue || ""),
        escape_csv(p.title),
        escape_csv(p.url)
      ]
      |> Enum.join(",")
    end)
    |> Enum.join("\n")
    
    header <> rows <> "\n"
  end

  defp print_summary(properties) do
    Logger.info("\nSummary:")
    
    # Count by source
    by_source = Enum.group_by(properties, & &1.source)
    Logger.info("  By source:")
    Enum.each(by_source, fn {source, props} ->
      Logger.info("    #{source}: #{length(props)}")
    end)
    
    # Count by issue type (if "all" type)
    if Enum.any?(properties, &Map.has_key?(&1, :issue)) do
      issues_list = properties
        |> Enum.flat_map(fn p -> 
          if p.issue, do: String.split(p.issue, ","), else: []
        end)
        |> Enum.frequencies()
      
      if map_size(issues_list) > 0 do
        Logger.info("\n  By issue type:")
        Enum.each(issues_list, fn {issue, count} ->
          Logger.info("    #{issue}: #{count}")
        end)
      end
    end
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      escaped = String.replace(value, "\"", "\"\"")
      "\"#{escaped}\""
    else
      value
    end
  end
  defp escape_csv(value), do: to_string(value)
end

