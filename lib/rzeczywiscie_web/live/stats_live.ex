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
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <div class="bg-base-100 border-b-4 border-base-content">
        <div class="container mx-auto px-4 py-6">
          <!-- Navigation -->
          <nav class="flex gap-1 mb-4">
            <a href="/real-estate" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Properties
            </a>
            <a href="/favorites" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Favorites
            </a>
            <a href="/stats" class="px-3 py-2 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100">
              Stats
            </a>
            <a href="/admin" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Admin
            </a>
          </nav>

          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div>
              <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">Statistics</h1>
              <p class="text-sm font-bold uppercase tracking-wide opacity-60">Data Monitoring Dashboard</p>
            </div>
            <button
              phx-click="refresh_stats"
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer"
              disabled={@refreshing}
            >
              <%= if @refreshing, do: "Refreshing...", else: "Refresh Data" %>
            </button>
          </div>
        </div>
      </div>

      <!-- Main Stats Grid -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-2 md:grid-cols-4 divide-x-2 divide-base-content">
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-primary"><%= @stats.total_properties %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total Properties</div>
              <div class="text-xs opacity-50"><%= @stats.active_properties %> active</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-secondary"><%= @stats.geocoded_count %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Geocoded</div>
              <div class="text-xs opacity-50"><%= Float.round(@stats.geocoded_percentage, 1) %>% coverage</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-accent"><%= @stats.aqi_count %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With AQI</div>
              <div class="text-xs opacity-50"><%= Float.round(@stats.aqi_percentage, 1) %>% of geocoded</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-info"><%= @stats.added_today %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Added Today</div>
              <div class="text-xs opacity-50">Last 24h</div>
            </div>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-6">
        <!-- Sources & Types Row -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
          <!-- Sources -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">Sources</h2>
            </div>
            <div class="divide-y divide-base-content/20">
              <%= for {source, count} <- @stats.by_source do %>
                <div class="flex justify-between items-center px-4 py-3">
                  <span class="font-bold uppercase"><%= source %></span>
                  <div class="text-right">
                    <span class="font-black text-lg"><%= count %></span>
                    <span class="text-xs opacity-50 ml-2"><%= Float.round(count / max(@stats.active_properties, 1) * 100, 1) %>%</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Transaction Types -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">Transaction Types</h2>
            </div>
            <div class="divide-y divide-base-content/20">
              <%= for {type, count} <- @stats.by_transaction_type do %>
                <div class="flex justify-between items-center px-4 py-3">
                  <span class={[
                    "font-bold",
                    type == "sprzedaż" && "text-info",
                    type == "wynajem" && "text-warning",
                    is_nil(type) && "opacity-50"
                  ]}><%= type || "Unknown" %></span>
                  <div class="text-right">
                    <span class="font-black text-lg"><%= count %></span>
                    <span class="text-xs opacity-50 ml-2"><%= Float.round(count / max(@stats.active_properties, 1) * 100, 1) %>%</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Property Types -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">Property Types</h2>
            </div>
            <div class="divide-y divide-base-content/20">
              <%= for {type, count} <- @stats.by_property_type do %>
                <div class="flex justify-between items-center px-4 py-3">
                  <span class={"font-bold #{if is_nil(type), do: "opacity-50"}"}><%= type || "Unknown" %></span>
                  <div class="text-right">
                    <span class="font-black text-lg"><%= count %></span>
                    <span class="text-xs opacity-50 ml-2"><%= Float.round(count / max(@stats.active_properties, 1) * 100, 1) %>%</span>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Top Cities -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">Top 10 Cities</h2>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-5 divide-x divide-y divide-base-content/20">
            <%= for {{city, count}, index} <- Enum.with_index(@stats.top_cities) do %>
              <div class={"p-3 #{if index == 0, do: "bg-primary/10"}"}>
                <div class="font-black text-xl"><%= count %></div>
                <div class="text-xs font-bold uppercase tracking-wide opacity-60 truncate"><%= city || "Unknown" %></div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Data Quality -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">Data Quality</h2>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 divide-x divide-base-content/20">
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_price %></span>
                <span class="text-xs font-bold text-success mb-1"><%= Float.round(@stats.with_price / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Price</div>
              <div class="mt-2 h-1 bg-base-300">
                <div class="h-1 bg-success" style={"width: #{Float.round(@stats.with_price / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_area %></span>
                <span class="text-xs font-bold text-success mb-1"><%= Float.round(@stats.with_area / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Area</div>
              <div class="mt-2 h-1 bg-base-300">
                <div class="h-1 bg-success" style={"width: #{Float.round(@stats.with_area / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_rooms %></span>
                <span class="text-xs font-bold text-warning mb-1"><%= Float.round(@stats.with_rooms / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Rooms</div>
              <div class="mt-2 h-1 bg-base-300">
                <div class="h-1 bg-warning" style={"width: #{Float.round(@stats.with_rooms / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.complete_data %></span>
                <span class="text-xs font-bold text-info mb-1"><%= Float.round(@stats.complete_data / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Complete Data</div>
              <div class="mt-2 h-1 bg-base-300">
                <div class="h-1 bg-info" style={"width: #{Float.round(@stats.complete_data / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
            </div>
          </div>
        </div>

        <!-- Recent Activity -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">Recent Activity (Last 7 Days)</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-base-200 border-b border-base-content/30">
                <tr>
                  <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">Date</th>
                  <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">Total</th>
                  <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">OLX</th>
                  <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">Otodom</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-base-content/20">
                <%= for day <- @stats.recent_activity do %>
                  <tr class="hover:bg-base-200/50">
                    <td class="px-4 py-2 font-medium"><%= day.date %></td>
                    <td class="px-4 py-2 text-right font-black"><%= day.total %></td>
                    <td class="px-4 py-2 text-right"><%= day.olx %></td>
                    <td class="px-4 py-2 text-right"><%= day.otodom %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Price Drops -->
        <%= if length(@stats.price_drops) > 0 do %>
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">Recent Price Drops</h2>
              <p class="text-[10px] opacity-60">Properties with price reductions in the last 7 days</p>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30">
                  <tr>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">Property</th>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">Location</th>
                    <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">New Price</th>
                    <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">Change</th>
                    <th class="px-4 py-2 text-right text-[10px] font-bold uppercase tracking-wide">Date</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/20">
                  <%= for {property, price_history} <- @stats.price_drops do %>
                    <tr class="hover:bg-base-200/50">
                      <td class="px-4 py-2 max-w-[200px] truncate font-medium"><%= property.title %></td>
                      <td class="px-4 py-2"><%= property.city || "—" %></td>
                      <td class="px-4 py-2 text-right font-bold"><%= format_price(price_history.price) %></td>
                      <td class="px-4 py-2 text-right">
                        <span class="px-2 py-0.5 text-xs font-bold bg-success text-success-content">
                          <%= Float.round(Decimal.to_float(price_history.change_percentage), 1) %>%
                        </span>
                      </td>
                      <td class="px-4 py-2 text-right text-xs opacity-60"><%= Calendar.strftime(price_history.detected_at, "%Y-%m-%d") %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
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

    geocoded_percentage = if active_properties > 0, do: geocoded_count / active_properties * 100, else: 0.0

    # AQI stats (check air_quality_cache)
    aqi_count =
      try do
        Repo.one(
          from p in Property,
            join: aq in "air_quality_cache",
            on: fragment("ROUND(?::numeric, 2)", p.latitude) == aq.lat and
               fragment("ROUND(?::numeric, 2)", p.longitude) == aq.lng,
            where: p.active == true and not is_nil(p.latitude) and not is_nil(p.longitude),
            select: count(p.id, :distinct)
        ) || 0
      rescue
        _ -> 0
      end

    aqi_percentage = if geocoded_count > 0, do: aqi_count / geocoded_count * 100, else: 0.0

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
