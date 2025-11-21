defmodule Rzeczywiscie.RealEstate do
  @moduledoc """
  The RealEstate context - manages property listings with real-time updates.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.Property

  @topic "real_estate"

  @doc """
  Subscribe to real estate updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast property updates to all subscribed clients.
  """
  def broadcast_property(property, event) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {event, property}
    )
  end

  @doc """
  List all active properties with optional filters.

  ## Options
    * `:city` - Filter by city
    * `:min_price` - Minimum price
    * `:max_price` - Maximum price
    * `:min_area` - Minimum area in sqm
    * `:max_area` - Maximum area in sqm
    * `:source` - Filter by source (olx, otodom, etc.)
    * `:limit` - Limit results (default: 100)
    * `:offset` - Offset for pagination (default: 0)
  """
  def list_properties(opts \\ []) do
    Property
    |> where([p], p.active == true)
    |> apply_filters(opts)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  @doc """
  Count properties matching filters.
  """
  def count_properties(opts \\ []) do
    Property
    |> where([p], p.active == true)
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:city, city}, query when is_binary(city) ->
        where(query, [p], ilike(p.city, ^"%#{city}%"))

      {:min_price, min}, query when is_number(min) ->
        where(query, [p], p.price >= ^min)

      {:max_price, max}, query when is_number(max) ->
        where(query, [p], p.price <= ^max)

      {:min_area, min}, query when is_number(min) ->
        where(query, [p], p.area_sqm >= ^min)

      {:max_area, max}, query when is_number(max) ->
        where(query, [p], p.area_sqm <= ^max)

      {:source, source}, query when is_binary(source) ->
        where(query, [p], p.source == ^source)

      _other, query ->
        query
    end)
  end

  @doc """
  Get a single property by ID.
  """
  def get_property(id) do
    Repo.get(Property, id)
  end

  @doc """
  Get a property by source and external_id.
  """
  def get_property_by_external_id(source, external_id) do
    Repo.get_by(Property, source: source, external_id: external_id)
  end

  @doc """
  Create a new property or update if exists.
  This is the main function called by scrapers.
  """
  def upsert_property(attrs) do
    require Logger
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = Map.put(attrs, :last_seen_at, now)

    case get_property_by_external_id(attrs.source, attrs.external_id) do
      nil ->
        Logger.info("Creating new property: #{attrs.external_id}")
        create_property(attrs)

      existing ->
        Logger.info("Updating existing property: #{attrs.external_id}")
        update_property(existing, attrs)
    end
  end

  @doc """
  Create a new property and broadcast it.
  """
  def create_property(attrs) do
    %Property{}
    |> Property.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, property} ->
        broadcast_property(property, :property_created)
        {:ok, property}

      error ->
        error
    end
  end

  @doc """
  Update a property and broadcast if changed.
  """
  def update_property(%Property{} = property, attrs) do
    property
    |> Property.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_property} ->
        broadcast_property(updated_property, :property_updated)
        {:ok, updated_property}

      error ->
        error
    end
  end

  @doc """
  Mark properties as inactive if not seen recently.
  This should be run periodically (e.g., daily) to clean up old listings.
  """
  def mark_stale_properties_inactive(hours_ago \\ 48) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_ago * 3600, :second)

    from(p in Property,
      where: p.active == true and p.last_seen_at < ^cutoff
    )
    |> Repo.update_all(set: [active: false])
  end

  @doc """
  Delete a property.
  """
  def delete_property(%Property{} = property) do
    Repo.delete(property)
  end

  @doc """
  Get statistics about properties.
  """
  def get_statistics do
    %{
      total: Repo.aggregate(Property, :count),
      active: from(p in Property, where: p.active == true) |> Repo.aggregate(:count),
      by_source: get_count_by_source(),
      avg_price: get_average_price(),
      avg_area: get_average_area()
    }
  end

  defp get_count_by_source do
    from(p in Property,
      where: p.active == true,
      group_by: p.source,
      select: {p.source, count(p.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp get_average_price do
    from(p in Property,
      where: p.active == true and not is_nil(p.price),
      select: avg(p.price)
    )
    |> Repo.one()
    |> case do
      nil -> Decimal.new(0)
      avg -> avg
    end
  end

  defp get_average_area do
    from(p in Property,
      where: p.active == true and not is_nil(p.area_sqm),
      select: avg(p.area_sqm)
    )
    |> Repo.one()
    |> case do
      nil -> Decimal.new(0)
      avg -> avg
    end
  end
end
