defmodule Rzeczywiscie.Workers.GeocodingWorker do
  @moduledoc """
  Oban worker for geocoding properties that don't have coordinates.
  Processes properties in batches to avoid API quota issues.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Rzeczywiscie.{Repo, RealEstate}
  alias Rzeczywiscie.Services.Geocoding
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    batch_size = Map.get(args, "batch_size", 10)
    delay_ms = Map.get(args, "delay_ms", 1000)

    Logger.info("GeocodingWorker starting: processing #{batch_size} properties")

    # Find properties without coordinates
    properties =
      from(p in RealEstate.Property,
        where: is_nil(p.latitude) or is_nil(p.longitude),
        where: p.active == true,
        limit: ^batch_size
      )
      |> Repo.all()

    if length(properties) == 0 do
      Logger.info("No properties to geocode")
      :ok
    else
      results =
        Enum.map(properties, fn property ->
          result = geocode_property(property)

          # Add delay between requests to respect API limits
          if delay_ms > 0, do: Process.sleep(delay_ms)

          result
        end)

      successful = Enum.count(results, fn {status, _} -> status == :ok end)
      Logger.info("GeocodingWorker completed: #{successful}/#{length(properties)} geocoded")

      :ok
    end
  end

  defp geocode_property(property) do
    Logger.info("Geocoding property #{property.id}: #{property.city}")

    case Geocoding.geocode_property(property) do
      {:ok, %{lat: lat, lng: lng}} ->
        case RealEstate.update_property(property, %{latitude: lat, longitude: lng}) do
          {:ok, updated} ->
            Logger.info("✓ Geocoded property #{updated.id}: #{lat}, #{lng}")
            {:ok, updated}

          {:error, changeset} ->
            Logger.error("Failed to update property #{property.id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.warning("Failed to geocode property #{property.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Manually trigger geocoding.
  """
  def trigger(opts \\ []) do
    %{
      "batch_size" => Keyword.get(opts, :batch_size, 10),
      "delay_ms" => Keyword.get(opts, :delay_ms, 1000)
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
