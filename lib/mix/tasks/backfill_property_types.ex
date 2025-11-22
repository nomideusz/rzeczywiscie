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
      :ok
    else
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
              {:ok, _updated_property} ->
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
    url_lower = String.downcase(url)

    cond do
      # Keywords for sale (sprzedaż)
      String.contains?(url_lower, "sprzedam") -> "sprzedaż"
      String.contains?(url_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(url_lower, "na-sprzedaz") -> "sprzedaż"

      # Keywords for rent (wynajem)
      String.contains?(url_lower, "wynajme") -> "wynajem"
      String.contains?(url_lower, "wynajem") -> "wynajem"
      String.contains?(url_lower, "do-wynajecia") -> "wynajem"
      String.contains?(url_lower, "na-wynajem") -> "wynajem"

      true -> nil
    end
  end

  defp extract_property_type(url) do
    url_lower = String.downcase(url)

    cond do
      # Apartment (mieszkanie)
      String.contains?(url_lower, "mieszkanie") -> "mieszkanie"
      String.contains?(url_lower, "mieszkania") -> "mieszkanie"

      # House (dom)
      String.contains?(url_lower, "-dom-") -> "dom"
      String.contains?(url_lower, "/dom-") -> "dom"
      String.match?(url_lower, ~r/\bdom\b/) -> "dom"

      # Room (pokój)
      String.contains?(url_lower, "pokoj") -> "pokój"

      # Garage (garaż)
      String.contains?(url_lower, "garaz") -> "garaż"

      # Plot/land (działka)
      String.contains?(url_lower, "dzialka") -> "działka"

      # Commercial space (lokal użytkowy)
      String.contains?(url_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(url_lower, "lokal-biurowo") -> "lokal użytkowy"
      String.contains?(url_lower, "lokal-handlowy") -> "lokal użytkowy"

      # Student accommodation (stancja)
      String.contains?(url_lower, "stancja") -> "stancja"

      true -> nil
    end
  end
end
