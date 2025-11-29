defmodule Rzeczywiscie.RealEstate do
  @moduledoc """
  The RealEstate context - manages property listings with real-time updates.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.Property
  alias Rzeczywiscie.RealEstate.PriceHistory
  alias Rzeczywiscie.RealEstate.Favorite

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
    * `:search` - Full-text search in title and description
    * `:city` - Filter by city
    * `:min_price` - Minimum price
    * `:max_price` - Maximum price
    * `:min_area` - Minimum area in sqm
    * `:max_area` - Maximum area in sqm
    * `:rooms` - Filter by number of rooms
    * `:source` - Filter by source (olx, otodom, etc.)
    * `:transaction_type` - Filter by transaction type (sprzedaż, wynajem)
    * `:property_type` - Filter by property type (mieszkanie, dom, etc.)
    * `:sort_by` - Column to sort by (default: "inserted_at")
    * `:sort_direction` - Sort direction "asc" or "desc" (default: "desc")
    * `:limit` - Limit results (default: 100)
    * `:offset` - Offset for pagination (default: 0)
  """
  def list_properties(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, "inserted_at")
    sort_direction = Keyword.get(opts, :sort_direction, "desc")

    Property
    |> where([p], p.active == true)
    |> apply_filters(opts)
    |> apply_sorting(sort_by, sort_direction)
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

  @doc """
  Count properties with coordinates (latitude and longitude) matching filters.
  """
  def count_properties_with_coordinates(opts \\ []) do
    Property
    |> where([p], p.active == true)
    |> where([p], not is_nil(p.latitude) and not is_nil(p.longitude))
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count properties with AQI data (have both coordinates and cache entry) matching filters.
  """
  def count_properties_with_aqi(opts \\ []) do
    # Need to import the Cache module alias
    alias Rzeczywiscie.AirQuality.Cache

    from(p in Property,
      join: c in Cache,
      on: fragment("ROUND(?::numeric, 2)", p.latitude) == c.lat and
          fragment("ROUND(?::numeric, 2)", p.longitude) == c.lng,
      where: p.active == true and not is_nil(p.latitude) and not is_nil(p.longitude)
    )
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:search, search}, query when is_binary(search) and search != "" ->
        # Full-text search in title and description
        search_term = "%#{search}%"
        where(query, [p], ilike(p.title, ^search_term) or ilike(p.description, ^search_term))

      {:city, city}, query when is_binary(city) and city != "" ->
        where(query, [p], ilike(p.city, ^"%#{city}%"))

      {:min_price, min}, query when is_number(min) ->
        where(query, [p], p.price >= ^min)

      {:max_price, max}, query when is_number(max) ->
        where(query, [p], p.price <= ^max)

      {:min_area, min}, query when is_number(min) ->
        where(query, [p], p.area_sqm >= ^min)

      {:max_area, max}, query when is_number(max) ->
        where(query, [p], p.area_sqm <= ^max)

      {:rooms, rooms}, query when is_integer(rooms) ->
        # For "5+", match 5 or more rooms
        if rooms >= 5 do
          where(query, [p], p.rooms >= ^rooms)
        else
          where(query, [p], p.rooms == ^rooms)
        end

      {:source, source}, query when is_binary(source) and source != "" ->
        where(query, [p], p.source == ^source)

      {:transaction_type, type}, query when is_binary(type) and type != "" ->
        # Include properties with matching type OR unknown (nil) type
        where(query, [p], p.transaction_type == ^type or is_nil(p.transaction_type))

      {:property_type, type}, query when is_binary(type) and type != "" ->
        # Include properties with matching type OR unknown (nil) type
        where(query, [p], p.property_type == ^type or is_nil(p.property_type))

      {:has_coordinates, true}, query ->
        where(query, [p], not is_nil(p.latitude) and not is_nil(p.longitude))

      _other, query ->
        query
    end)
  end

  defp apply_sorting(query, column, direction) do
    # Convert direction string to atom
    direction_atom = case direction do
      "asc" -> :asc
      "desc" -> :desc
      _ -> :desc
    end

    # Handle special case for price_per_sqm (calculated field)
    if column == "price_per_sqm" do
      case direction_atom do
        :asc ->
          order_by(query, [p], [asc_nulls_last: fragment("CASE WHEN ? > 0 THEN ? / ? ELSE NULL END", p.area_sqm, p.price, p.area_sqm)])
        :desc ->
          order_by(query, [p], [desc_nulls_last: fragment("CASE WHEN ? > 0 THEN ? / ? ELSE NULL END", p.area_sqm, p.price, p.area_sqm)])
      end
    else
      # Convert string column to atom, defaulting to :inserted_at if invalid
      column_atom = try do
        String.to_existing_atom(column)
      rescue
        ArgumentError -> :inserted_at
      end

      # Apply ordering with NULL handling (NULLs last for both directions)
      case direction_atom do
        :asc ->
          order_by(query, [p], [asc_nulls_last: field(p, ^column_atom)])
        :desc ->
          order_by(query, [p], [desc_nulls_last: field(p, ^column_atom)])
      end
    end
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
  Get a property by URL.
  """
  def get_property_by_url(url) do
    Repo.get_by(Property, url: url)
  end

  @doc """
  Create a new property or update if exists.
  This is the main function called by scrapers.
  Checks for duplicates by both source+external_id and URL to prevent duplicates.
  """
  def upsert_property(attrs) do
    require Logger
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = Map.put(attrs, :last_seen_at, now)

    # Check for existing property by source+external_id OR by URL
    existing =
      get_property_by_external_id(attrs.source, attrs.external_id) ||
      get_property_by_url(attrs.url)

    case existing do
      nil ->
        Logger.info("Creating new property: #{attrs.external_id} (URL: #{String.slice(attrs.url, 0, 50)}...)")
        create_property(attrs)

      property ->
        Logger.info("Updating existing property: ID #{property.id}, external_id: #{attrs.external_id}")
        update_property(property, attrs)
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
  Find potential duplicate properties based on URL.
  Returns a list of duplicate groups where each group contains properties with the same URL.
  """
  def find_duplicate_properties do
    query = """
    SELECT url, array_agg(id ORDER BY inserted_at) as property_ids, COUNT(*) as count
    FROM properties
    WHERE url IS NOT NULL
    GROUP BY url
    HAVING COUNT(*) > 1
    ORDER BY count DESC
    """

    Ecto.Adapters.SQL.query!(Repo, query, [])
    |> Map.get(:rows)
    |> Enum.map(fn [url, ids, count] ->
      %{url: url, property_ids: ids, count: count}
    end)
  end

  @doc """
  Remove duplicate properties, keeping only the oldest one (first inserted).
  Returns the number of duplicates removed.
  """
  def remove_duplicate_properties do
    require Logger
    duplicates = find_duplicate_properties()

    removed_count =
      Enum.reduce(duplicates, 0, fn %{url: url, property_ids: ids}, acc ->
        # Keep the first (oldest) property, delete the rest
        [_keep_id | delete_ids] = ids

        Logger.info("Removing #{length(delete_ids)} duplicate(s) for URL: #{String.slice(url, 0, 60)}...")

        from(p in Property, where: p.id in ^delete_ids)
        |> Repo.delete_all()
        |> elem(0)
        |> Kernel.+(acc)
      end)

    Logger.info("Removed #{removed_count} duplicate properties")
    {:ok, removed_count}
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

  # Price History functions

  @doc """
  Create a price history record for a property.
  """
  def create_price_history(attrs) do
    %PriceHistory{}
    |> PriceHistory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get price history for a property.
  """
  def get_price_history(property_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(ph in PriceHistory,
      where: ph.property_id == ^property_id,
      order_by: [desc: ph.detected_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get the latest price for a property.
  """
  def get_latest_price(property_id) do
    from(ph in PriceHistory,
      where: ph.property_id == ^property_id,
      order_by: [desc: ph.detected_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Track price change for a property.
  Called when a property is updated.
  """
  def track_price_change(%Property{} = property, new_price) do
    if property.price && new_price && property.price != new_price do
      old_price = Decimal.to_float(property.price)
      new_price_float = Decimal.to_float(new_price)
      change_pct = ((new_price_float - old_price) / old_price * 100) |> Decimal.from_float()

      price_per_sqm =
        if property.area_sqm && Decimal.compare(property.area_sqm, 0) == :gt do
          Decimal.div(new_price, property.area_sqm)
        else
          nil
        end

      create_price_history(%{
        property_id: property.id,
        price: new_price,
        price_per_sqm: price_per_sqm,
        currency: property.currency || "PLN",
        change_percentage: change_pct,
        detected_at: DateTime.utc_now()
      })
    else
      {:ok, :no_change}
    end
  end

  @doc """
  Get properties with recent price drops.
  """
  def get_properties_with_price_drops(days_ago \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_ago * 24 * 3600, :second)

    from(ph in PriceHistory,
      join: p in Property,
      on: ph.property_id == p.id,
      where: ph.detected_at >= ^cutoff and ph.change_percentage < 0,
      order_by: [asc: ph.change_percentage],
      select: {p, ph}
    )
    |> Repo.all()
  end

  # Favorites functions

  @doc """
  Add a property to favorites.
  """
  def add_favorite(property_id, user_id, opts \\ []) do
    attrs = %{
      property_id: property_id,
      user_id: user_id,
      notes: Keyword.get(opts, :notes),
      alert_on_price_drop: Keyword.get(opts, :alert_on_price_drop, true)
    }

    %Favorite{}
    |> Favorite.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Remove a property from favorites.
  """
  def remove_favorite(property_id, user_id) do
    from(f in Favorite,
      where: f.property_id == ^property_id and f.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Update notes on a favorite.
  """
  def update_favorite_notes(favorite_id, notes) do
    case Repo.get(Favorite, favorite_id) do
      nil ->
        {:error, :not_found}

      favorite ->
        favorite
        |> Favorite.changeset(%{notes: notes})
        |> Repo.update()
    end
  end

  @doc """
  Get all favorites for a user.
  """
  def list_favorites(user_id) do
    from(f in Favorite,
      join: p in Property,
      on: f.property_id == p.id,
      where: f.user_id == ^user_id and p.active == true,
      order_by: [desc: f.inserted_at],
      preload: [property: p]
    )
    |> Repo.all()
  end

  @doc """
  Check if a property is favorited by a user.
  """
  def is_favorited?(property_id, user_id) do
    from(f in Favorite,
      where: f.property_id == ^property_id and f.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Get all favorited property IDs for a user as a MapSet (for efficient lookups).
  This is much faster than calling is_favorited? for each property (avoids N+1 queries).
  """
  def get_favorited_property_ids(user_id) do
    from(f in Favorite,
      where: f.user_id == ^user_id,
      select: f.property_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Get count of favorites for a user.
  """
  def count_favorites(user_id) do
    from(f in Favorite,
      where: f.user_id == ^user_id
    )
    |> Repo.aggregate(:count)
  end
end
