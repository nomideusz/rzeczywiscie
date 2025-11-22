defmodule RzeczywiscieWeb.StatsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  require Logger
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:stats, calculate_stats())
      |> assign(:refreshing, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
    <div class="container mx-auto p-8">
      <!-- Sub-navigation tabs -->
      <div class="mb-6">
        <div class="tabs tabs-boxed bg-base-200 border-2 border-base-content">
          <a href="/real-estate" class="tab font-bold">Properties</a>
          <a href="/favorites" class="tab font-bold">Favorites</a>
          <a href="/stats" class="tab tab-active font-bold">Stats</a>
          <a href="/admin" class="tab font-bold">Admin</a>
        </div>
      </div>

      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Data Monitoring Dashboard</h1>
        <button
          phx-click="refresh_stats"
          class="btn btn-primary btn-sm"
          disabled={@refreshing}
        >
          <%= if @refreshing, do: "Refreshing...", else: "Refresh Data" %>
        </button>
      </div>

      <!-- Overall Stats Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-6">
        <!-- Total Properties -->
        <div class="stat bg-base-200 shadow-xl rounded-lg">
          <div class="stat-title">Total Properties</div>
          <div class="stat-value text-primary"><%= @stats.total_properties %></div>
          <div class="stat-desc"><%= @stats.active_properties %> active</div>
        </div>

        <!-- Geocoded Properties -->
        <div class="stat bg-base-200 shadow-xl rounded-lg">
          <div class="stat-title">Geocoded</div>
          <div class="stat-value text-secondary"><%= @stats.geocoded_count %></div>
          <div class="stat-desc">
            <%= Float.round(@stats.geocoded_percentage, 1) %>% coverage
          </div>
        </div>

        <!-- AQI Coverage -->
        <div class="stat bg-base-200 shadow-xl rounded-lg">
          <div class="stat-title">Air Quality Data</div>
          <div class="stat-value text-accent"><%= @stats.aqi_count %></div>
          <div class="stat-desc">
            <%= Float.round(@stats.aqi_percentage, 1) %>% of geocoded
          </div>
        </div>

        <!-- Added Today -->
        <div class="stat bg-base-200 shadow-xl rounded-lg">
          <div class="stat-title">Added Today</div>
          <div class="stat-value text-info"><%= @stats.added_today %></div>
          <div class="stat-desc">Last 24 hours</div>
        </div>
      </div>

      <!-- Source Breakdown -->
      <div class="card bg-base-200 shadow-xl mb-6">
        <div class="card-body">
          <h2 class="card-title">Sources Breakdown</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
            <%= for {source, count} <- @stats.by_source do %>
              <div class="stat bg-base-100 rounded-lg">
                <div class="stat-title"><%= String.upcase(source) %></div>
                <div class="stat-value text-sm"><%= count %></div>
                <div class="stat-desc">
                  <%= Float.round(count / max(@stats.total_properties, 1) * 100, 1) %>% of total
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Transaction & Property Types -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Transaction Types -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Transaction Types</h2>
            <div class="space-y-2 mt-4">
              <%= for {type, count} <- @stats.by_transaction_type do %>
                <div class="flex justify-between items-center p-3 bg-base-100 rounded-lg">
                  <span class="font-semibold"><%= type || "Unknown" %></span>
                  <div class="text-right">
                    <div class="font-bold"><%= count %></div>
                    <div class="text-xs opacity-70">
                      <%= Float.round(count / max(@stats.total_properties, 1) * 100, 1) %>%
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Property Types -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Property Types</h2>
            <div class="space-y-2 mt-4">
              <%= for {type, count} <- @stats.by_property_type do %>
                <div class="flex justify-between items-center p-3 bg-base-100 rounded-lg">
                  <span class="font-semibold"><%= type || "Unknown" %></span>
                  <div class="text-right">
                    <div class="font-bold"><%= count %></div>
                    <div class="text-xs opacity-70">
                      <%= Float.round(count / max(@stats.total_properties, 1) * 100, 1) %>%
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Top Cities -->
      <div class="card bg-base-200 shadow-xl mb-6">
        <div class="card-body">
          <h2 class="card-title">Top 10 Cities</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4 mt-4">
            <%= for {city, count} <- @stats.top_cities do %>
              <div class="stat bg-base-100 rounded-lg">
                <div class="stat-title text-xs"><%= city || "Unknown" %></div>
                <div class="stat-value text-sm"><%= count %></div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Data Quality Indicators -->
      <div class="card bg-base-200 shadow-xl mb-6">
        <div class="card-body">
          <h2 class="card-title">Data Quality</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            <div class="stat bg-base-100 rounded-lg">
              <div class="stat-title">With Price</div>
              <div class="stat-value text-sm"><%= @stats.with_price %></div>
              <div class="stat-desc">
                <%= Float.round(@stats.with_price / max(@stats.total_properties, 1) * 100, 1) %>%
              </div>
            </div>

            <div class="stat bg-base-100 rounded-lg">
              <div class="stat-title">With Area</div>
              <div class="stat-value text-sm"><%= @stats.with_area %></div>
              <div class="stat-desc">
                <%= Float.round(@stats.with_area / max(@stats.total_properties, 1) * 100, 1) %>%
              </div>
            </div>

            <div class="stat bg-base-100 rounded-lg">
              <div class="stat-title">With Rooms</div>
              <div class="stat-value text-sm"><%= @stats.with_rooms %></div>
              <div class="stat-desc">
                <%= Float.round(@stats.with_rooms / max(@stats.total_properties, 1) * 100, 1) %>%
              </div>
            </div>

            <div class="stat bg-base-100 rounded-lg">
              <div class="stat-title">Complete Data</div>
              <div class="stat-value text-sm"><%= @stats.complete_data %></div>
              <div class="stat-desc">
                <%= Float.round(@stats.complete_data / max(@stats.total_properties, 1) * 100, 1) %>%
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Price Drops -->
      <%= if length(@stats.price_drops) > 0 do %>
        <div class="card bg-base-200 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Recent Price Drops</h2>
            <p class="text-sm opacity-70 mb-4">Properties with price reductions in the last 7 days</p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Property</th>
                    <th>Location</th>
                    <th>Old Price</th>
                    <th>New Price</th>
                    <th>Change</th>
                    <th>Date</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {property, price_history} <- @stats.price_drops do %>
                    <tr>
                      <td class="max-w-xs truncate"><%= property.title %></td>
                      <td><%= property.city || "N/A" %></td>
                      <td>
                        <%= if price_history.change_percentage do %>
                          <%= format_price(Decimal.mult(price_history.price, Decimal.div(Decimal.new(100), Decimal.add(Decimal.new(100), price_history.change_percentage)))) %>
                        <% else %>
                          N/A
                        <% end %>
                      </td>
                      <td class="font-bold"><%= format_price(price_history.price) %></td>
                      <td>
                        <span class="badge badge-success">
                          <%= Float.round(Decimal.to_float(price_history.change_percentage), 1) %>%
                        </span>
                      </td>
                      <td class="text-xs"><%= Calendar.strftime(price_history.detected_at, "%Y-%m-%d") %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Recent Activity -->
      <div class="card bg-base-200 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Recent Activity (Last 7 Days)</h2>
          <div class="overflow-x-auto mt-4">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Properties Added</th>
                  <th>OLX</th>
                  <th>Otodom</th>
                </tr>
              </thead>
              <tbody>
                <%= for day <- @stats.recent_activity do %>
                  <tr>
                    <td><%= day.date %></td>
                    <td class="font-bold"><%= day.total %></td>
                    <td><%= day.olx %></td>
                    <td><%= day.otodom %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("refresh_stats", _params, socket) do
    socket =
      socket
      |> assign(:refreshing, true)
      |> assign(:stats, calculate_stats())
      |> assign(:refreshing, false)

    {:noreply, socket}
  end

  defp calculate_stats do
    total_properties = Repo.aggregate(Property, :count, :id)
    active_properties = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)

    # Geocoding stats
    geocoded_count =
      Repo.aggregate(
        from(p in Property,
          where: not is_nil(p.latitude) and not is_nil(p.longitude) and p.active == true
        ),
        :count,
        :id
      )

    geocoded_percentage = if active_properties > 0, do: geocoded_count / active_properties * 100, else: 0

    # AQI stats (check air_quality_cache)
    aqi_count =
      Repo.one(
        from p in Property,
          join: aq in "air_quality_cache",
          on: fragment("CAST(? AS text)", p.latitude) == fragment("CAST(? AS text)", aq.lat) and
             fragment("CAST(? AS text)", p.longitude) == fragment("CAST(? AS text)", aq.lng),
          where: p.active == true and not is_nil(p.latitude) and not is_nil(p.longitude),
          select: count(p.id),
          distinct: true
      ) || 0

    aqi_percentage = if geocoded_count > 0, do: aqi_count / geocoded_count * 100, else: 0

    # Added today
    today = DateTime.utc_now() |> DateTime.add(-24, :hour)
    added_today = Repo.aggregate(from(p in Property, where: p.inserted_at >= ^today), :count, :id)

    # By source
    by_source =
      Repo.all(
        from p in Property,
          where: p.active == true,
          group_by: p.source,
          select: {p.source, count(p.id)},
          order_by: [desc: count(p.id)]
      )

    # By transaction type
    by_transaction_type =
      Repo.all(
        from p in Property,
          where: p.active == true,
          group_by: p.transaction_type,
          select: {p.transaction_type, count(p.id)},
          order_by: [desc: count(p.id)]
      )

    # By property type
    by_property_type =
      Repo.all(
        from p in Property,
          where: p.active == true,
          group_by: p.property_type,
          select: {p.property_type, count(p.id)},
          order_by: [desc: count(p.id)]
      )
      |> Enum.take(10)

    # Top cities
    top_cities =
      Repo.all(
        from p in Property,
          where: p.active == true and not is_nil(p.city),
          group_by: p.city,
          select: {p.city, count(p.id)},
          order_by: [desc: count(p.id)],
          limit: 10
      )

    # Data quality
    with_price = Repo.aggregate(from(p in Property, where: p.active == true and not is_nil(p.price)), :count, :id)
    with_area = Repo.aggregate(from(p in Property, where: p.active == true and not is_nil(p.area_sqm)), :count, :id)
    with_rooms = Repo.aggregate(from(p in Property, where: p.active == true and not is_nil(p.rooms)), :count, :id)

    complete_data =
      Repo.aggregate(
        from(p in Property,
          where:
            p.active == true and
            not is_nil(p.price) and
            not is_nil(p.area_sqm) and
            not is_nil(p.transaction_type) and
            not is_nil(p.property_type)
        ),
        :count,
        :id
      )

    # Recent activity (last 7 days)
    recent_activity =
      0..6
      |> Enum.map(fn days_ago ->
        date = Date.utc_today() |> Date.add(-days_ago)
        start_datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        end_datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

        total =
          Repo.aggregate(
            from(p in Property, where: p.inserted_at >= ^start_datetime and p.inserted_at <= ^end_datetime),
            :count,
            :id
          )

        olx =
          Repo.aggregate(
            from(p in Property,
              where: p.source == "olx" and p.inserted_at >= ^start_datetime and p.inserted_at <= ^end_datetime
            ),
            :count,
            :id
          )

        otodom =
          Repo.aggregate(
            from(p in Property,
              where: p.source == "otodom" and p.inserted_at >= ^start_datetime and p.inserted_at <= ^end_datetime
            ),
            :count,
            :id
          )

        %{
          date: Calendar.strftime(date, "%Y-%m-%d"),
          total: total,
          olx: olx,
          otodom: otodom
        }
      end)
      |> Enum.reverse()

    # Price drops
    price_drops = RealEstate.get_properties_with_price_drops(7) |> Enum.take(10)

    %{
      total_properties: total_properties,
      active_properties: active_properties,
      geocoded_count: geocoded_count,
      geocoded_percentage: geocoded_percentage,
      aqi_count: aqi_count,
      aqi_percentage: aqi_percentage,
      added_today: added_today,
      by_source: by_source,
      by_transaction_type: by_transaction_type,
      by_property_type: by_property_type,
      top_cities: top_cities,
      with_price: with_price,
      with_area: with_area,
      with_rooms: with_rooms,
      complete_data: complete_data,
      recent_activity: recent_activity,
      price_drops: price_drops
    }
  end

  defp format_price(price) when is_nil(price), do: "N/A"

  defp format_price(price) do
    price
    |> Decimal.to_float()
    |> Float.round(0)
    |> then(fn p ->
      "#{trunc(p)} zł"
    end)
  end
end
