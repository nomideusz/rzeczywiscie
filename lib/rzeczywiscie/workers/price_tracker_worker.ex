defmodule Rzeczywiscie.Workers.PriceTrackerWorker do
  @moduledoc """
  Oban worker for tracking property price changes.
  Runs periodically to detect and record price changes.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    priority: 2

  require Logger
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.Repo
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting price tracking job")

    # Get all properties that were updated recently (last hour)
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    recently_updated =
      from(p in Rzeczywiscie.RealEstate.Property,
        where: p.updated_at >= ^one_hour_ago and p.active == true and not is_nil(p.price),
        select: p
      )
      |> Repo.all()

    Logger.info("Found #{length(recently_updated)} recently updated properties to check")

    # Track price changes
    Enum.each(recently_updated, fn property ->
      # Get the last recorded price
      last_price_record = RealEstate.get_latest_price(property.id)

      # If no price history exists, create initial record
      if is_nil(last_price_record) do
        price_per_sqm =
          if property.area_sqm && Decimal.compare(property.area_sqm, 0) == :gt do
            Decimal.div(property.price, property.area_sqm)
          else
            nil
          end

        RealEstate.create_price_history(%{
          property_id: property.id,
          price: property.price,
          price_per_sqm: price_per_sqm,
          currency: property.currency || "PLN",
          change_percentage: Decimal.new(0),
          detected_at: DateTime.utc_now()
        })

        Logger.info("Created initial price record for property #{property.id}")
      else
        # Check if price changed
        if Decimal.compare(property.price, last_price_record.price) != :eq do
          case RealEstate.track_price_change(property, property.price) do
            {:ok, price_history} ->
              Logger.info(
                "Tracked price change for property #{property.id}: " <>
                  "#{last_price_record.price} → #{property.price} " <>
                  "(#{price_history.change_percentage}%)"
              )

            {:ok, :no_change} ->
              :ok

            {:error, reason} ->
              Logger.error("Failed to track price change: #{inspect(reason)}")
          end
        end
      end
    end)

    :ok
  end
end
