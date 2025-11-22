defmodule Mix.Tasks.BackfillPropertyTypes do
  @moduledoc """
  Backfill transaction_type and property_type for existing properties based on their URLs.

  Usage:
    mix backfill_property_types
  """

  use Mix.Task
  require Logger

  @shortdoc "Backfill property types from URLs"

  def run(_args) do
    Mix.Task.run("app.start")

    Logger.info("Starting property type backfill...")

    # Get all properties without transaction_type or property_type
    properties = get_properties_to_update()

    Logger.info("Found #{length(properties)} properties to update")

    if length(properties) == 0 do
      Logger.info("✓ No properties need updating!")
      return
    end

    # Update each property
    updated =
      Enum.reduce(properties, 0, fn property, count ->
        transaction_type = extract_transaction_type(property.url)
        property_type = extract_property_type(property.url)

        changes = %{}
        changes = if transaction_type, do: Map.put(changes, :transaction_type, transaction_type), else: changes
        changes = if property_type, do: Map.put(changes, :property_type, property_type), else: changes

        if map_size(changes) > 0 do
          case Rzeczywiscie.RealEstate.update_property(property, changes) do
            {:ok, updated_property} ->
              Logger.info("✓ Updated property #{property.id}: #{transaction_type} / #{property_type}")
              count + 1

            {:error, changeset} ->
              Logger.error("✗ Failed to update property #{property.id}: #{inspect(changeset.errors)}")
              count
          end
        else
          Logger.info("- No type info found in URL for property #{property.id}")
          count
        end
      end)

    Logger.info("✓ Backfill completed: #{updated}/#{length(properties)} properties updated")
  end

  defp get_properties_to_update do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property

    from(p in Property,
      where: is_nil(p.transaction_type) or is_nil(p.property_type),
      where: p.active == true
    )
    |> Repo.all()
  end

  defp extract_transaction_type(url) do
    cond do
      String.contains?(url, "/sprzedaz/") -> "sprzedaż"
      String.contains?(url, "/wynajem/") -> "wynajem"
      true -> nil
    end
  end

  defp extract_property_type(url) do
    cond do
      String.contains?(url, "/mieszkania/") -> "mieszkanie"
      String.contains?(url, "/domy/") -> "dom"
      String.contains?(url, "/pokoje/") -> "pokój"
      String.contains?(url, "/garaze/") -> "garaż"
      String.contains?(url, "/dzialki/") -> "działka"
      String.contains?(url, "/lokale/") -> "lokal użytkowy"
      String.contains?(url, "/stancje/") -> "stancja"
      true -> nil
    end
  end
end
