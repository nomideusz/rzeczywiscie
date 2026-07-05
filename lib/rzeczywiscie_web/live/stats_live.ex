defmodule RzeczywiscieWeb.StatsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  require Logger
  import Ecto.Query
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  # Stale threshold in hours (4 days)
  @stale_hours 96
  
  @impl true
  def mount(_params, _session, socket) do
    # Get available property types for filter
    property_types = get_property_types()
    
    socket =
      socket
      |> assign(:stats, calculate_stats())
      |> assign(:market, calculate_market_stats())
      |> assign(:city_property_type, "mieszkanie")
      |> assign(:city_transaction_type, "sprzedaż")
      |> assign(:city_medians, calculate_city_medians("mieszkanie", "sprzedaż"))
      |> assign(:refreshing, false)
      |> assign(:last_updated, DateTime.utc_now())
      |> assign(:property_types, property_types)
      |> assign(:selected_property_type, "mieszkanie")
      |> assign(:selected_transaction_type, "all")
      |> assign(:min_area, nil)
      |> assign(:max_area, nil)
      |> assign(:min_rooms, nil)
      |> assign(:max_rooms, nil)
      |> assign(:sort_by, "sale_count")
      |> assign(:sort_dir, :desc)
      |> assign(:filtered_district_prices, calculate_filtered_district_prices("mieszkanie", "all"))
      |> assign(:expanded_district, nil)
      |> assign(:district_properties, [])
      |> sort_filtered_prices()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <.property_page_header current_path={@current_path} title="Statistics" subtitle="Data Monitoring Dashboard">
        <:actions>
          <div class="flex items-center gap-3">
            <span class="text-xs opacity-50">
              Updated <%= format_time_ago(@last_updated) %>
            </span>
            <button
              phx-click="refresh_stats"
              disabled={@refreshing}
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer"
            >
              <%= if @refreshing, do: "Refreshing...", else: "🔄 Refresh" %>
            </button>
          </div>
        </:actions>
      </.property_page_header>

      <!-- Main Stats Grid -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-2 md:grid-cols-5 divide-x-2 divide-base-content">
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
            <div class="p-4 text-center">
              <div class={"text-3xl font-black #{if @stats.stale_count > 0, do: "text-warning", else: "text-success"}"}><%= @stats.stale_count %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Stale (4 days+)</div>
              <div class="text-xs opacity-50">Will deactivate soon</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Stale Warning -->
      <%= if @stats.stale_count > 0 do %>
        <div class="bg-warning/10 border-b-2 border-warning">
          <div class="container mx-auto px-4 py-3">
            <div class="flex flex-wrap items-center gap-4">
              <span class="text-xs font-bold uppercase tracking-wide">⚠️ Stale Properties:</span>
              <%= for {source, count} <- @stats.stale_by_source do %>
                <span class="px-2 py-1 text-xs font-bold bg-warning/20 border border-warning">
                  <%= String.upcase(source) %>: <%= count %>
                </span>
              <% end %>
              <span class="text-xs opacity-60">Not seen in 4+ days — will become inactive</span>
            </div>
          </div>
        </div>
      <% end %>

      <div class="container mx-auto px-4 py-6">
        <style>
          .viz-root { --viz-1: #2a78d6; --viz-2: #1baf7a; --viz-3: #eda100; }
        </style>

        <!-- Market Trends: computed over the FULL archive, not just active listings -->
        <div class="viz-root bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-3 border-b-2 border-base-content bg-gradient-to-r from-primary/20 to-accent/20">
            <h2 class="text-sm font-bold uppercase tracking-wide">&#128200; Market Trends &mdash; Full Archive</h2>
            <p class="text-[10px] opacity-60">
              Monthly medians over all <%= @stats.total_properties %> tracked properties (mieszkania)
              <%= if @market.tracked_since do %>
                &bull; since <%= Calendar.strftime(@market.tracked_since, "%b %Y") %>
              <% end %>
              &bull; outliers excluded
            </p>
          </div>
          <div class="grid grid-cols-1 lg:grid-cols-2 divide-y-2 lg:divide-y-0 lg:divide-x-2 divide-base-content">
            <div class="p-4">
              <h3 class="text-xs font-bold uppercase tracking-wide mb-2">
                <span class="inline-block w-3 h-3 align-middle mr-1" style="background: var(--viz-1)"></span>
                Median Sale Price / m&sup2;
              </h3>
              <.trend_chart rows={@market.monthly_sale} color="var(--viz-1)" unit="zł/m²" label="Median sale price per square meter by month" />
              <details class="mt-2">
                <summary class="text-[10px] uppercase font-bold opacity-50 cursor-pointer">Data table</summary>
                <table class="w-full text-xs mt-1">
                  <thead><tr class="text-left opacity-60"><th class="px-2 py-1">Month</th><th class="px-2 py-1">Median z&#322;/m&sup2;</th><th class="px-2 py-1">Listings</th></tr></thead>
                  <tbody>
                    <%= for row <- Enum.reverse(@market.monthly_sale) do %>
                      <tr class="border-t border-base-content/10"><td class="px-2 py-1"><%= short_month(row.month) %></td><td class="px-2 py-1 font-bold"><%= axis_number(row.value) %></td><td class="px-2 py-1 opacity-60"><%= row.count %></td></tr>
                    <% end %>
                  </tbody>
                </table>
              </details>
            </div>
            <div class="p-4">
              <h3 class="text-xs font-bold uppercase tracking-wide mb-2">
                <span class="inline-block w-3 h-3 align-middle mr-1" style="background: var(--viz-2)"></span>
                Median Monthly Rent
              </h3>
              <.trend_chart rows={@market.monthly_rent} color="var(--viz-2)" unit="zł" label="Median monthly rent by month" />
              <details class="mt-2">
                <summary class="text-[10px] uppercase font-bold opacity-50 cursor-pointer">Data table</summary>
                <table class="w-full text-xs mt-1">
                  <thead><tr class="text-left opacity-60"><th class="px-2 py-1">Month</th><th class="px-2 py-1">Median z&#322;</th><th class="px-2 py-1">Listings</th></tr></thead>
                  <tbody>
                    <%= for row <- Enum.reverse(@market.monthly_rent) do %>
                      <tr class="border-t border-base-content/10"><td class="px-2 py-1"><%= short_month(row.month) %></td><td class="px-2 py-1 font-bold"><%= axis_number(row.value) %></td><td class="px-2 py-1 opacity-60"><%= row.count %></td></tr>
                    <% end %>
                  </tbody>
                </table>
              </details>
            </div>
          </div>
        </div>

        <!-- Listing Volume + Market Velocity -->
        <div class="viz-root grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-secondary/20 flex items-center justify-between flex-wrap gap-2">
              <h2 class="text-sm font-bold uppercase tracking-wide">&#128202; New Listings / Month</h2>
              <div class="flex gap-3 text-[10px] font-bold uppercase">
                <span><span class="inline-block w-3 h-3 align-middle mr-1" style="background: var(--viz-1)"></span>OLX</span>
                <span><span class="inline-block w-3 h-3 align-middle mr-1" style="background: var(--viz-2)"></span>Otodom</span>
                <%= if Enum.any?(@market.monthly_volume, & &1.other > 0) do %>
                  <span><span class="inline-block w-3 h-3 align-middle mr-1" style="background: var(--viz-3)"></span>Other</span>
                <% end %>
              </div>
            </div>
            <div class="p-4">
              <.volume_chart rows={@market.monthly_volume} />
            </div>
          </div>

          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-accent/20">
              <h2 class="text-sm font-bold uppercase tracking-wide">&#9201;&#65039; Market Velocity</h2>
              <p class="text-[10px] opacity-60">Median days on market, from <%= @market.delisted_count %> delisted properties</p>
            </div>
            <%= if map_size(@market.velocity) > 0 do %>
              <div class="grid grid-cols-2 divide-x-2 divide-base-content border-b border-base-content/20">
                <%= for {key, css} <- [{"sprzedaż", "text-info"}, {"wynajem", "text-warning"}] do %>
                  <div class="p-4 text-center">
                    <%= if v = @market.velocity[key] do %>
                      <div class={"text-3xl font-black #{css}"}><%= round(v.median_days) %>d</div>
                      <div class="text-[10px] font-bold uppercase tracking-wide opacity-60"><%= key %></div>
                      <div class="text-xs opacity-50"><%= v.count %> delisted</div>
                    <% else %>
                      <div class="text-3xl font-black opacity-30">&mdash;</div>
                      <div class="text-[10px] font-bold uppercase tracking-wide opacity-60"><%= key %></div>
                    <% end %>
                  </div>
                <% end %>
              </div>
              <div class="p-3">
                <%= for v <- @market.velocity_by_type do %>
                  <div class="flex items-center justify-between py-1 text-xs border-b border-base-content/10 last:border-0">
                    <span class="font-bold"><%= v.key %></span>
                    <span><span class="font-black"><%= round(v.median_days) %> days</span> <span class="opacity-50">(<%= v.count %>)</span></span>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="p-8 text-center text-xs opacity-50">No delisted properties yet &mdash; velocity appears once listings start expiring</div>
            <% end %>
          </div>
        </div>

        <!-- City medians over full archive -->
        <div class="viz-root bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-primary/20">
            <h2 class="text-sm font-bold uppercase tracking-wide">&#127961;&#65039; Price by City &mdash; Full Archive</h2>
            <p class="text-[10px] opacity-60">
              Medians over all tracked listings with price &amp; area &bull; min. 10 per city &bull;
              <%= @city_medians |> Enum.map(& &1.count) |> Enum.sum() %> listings in <%= length(@city_medians) %> cities
            </p>
          </div>

          <div class="px-4 py-3 border-b border-base-content/20 bg-base-200/50 flex flex-wrap gap-4 items-center">
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wide opacity-60">Property:</span>
              <div class="flex flex-wrap gap-1">
                <%= for type <- ["mieszkanie", "dom", "działka", "lokal użytkowy", "pokój", "garaż"] do %>
                  <button
                    phx-click="city_property_type"
                    phx-value-type={type}
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @city_property_type == type, do: "bg-primary text-primary-content border-primary", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    <%= type %>
                  </button>
                <% end %>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wide opacity-60">Transaction:</span>
              <div class="flex gap-1">
                <button
                  phx-click="city_transaction_type"
                  phx-value-type="sprzedaż"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @city_transaction_type == "sprzedaż", do: "bg-info text-info-content border-info", else: "border-base-content/30 hover:bg-base-200"}"}
                >
                  Sprzedaż
                </button>
                <button
                  phx-click="city_transaction_type"
                  phx-value-type="wynajem"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @city_transaction_type == "wynajem", do: "bg-warning text-warning-content border-warning", else: "border-base-content/30 hover:bg-base-200"}"}
                >
                  Wynajem
                </button>
              </div>
            </div>
          </div>

          <%= if @city_medians != [] do %>
            <div class="overflow-x-auto max-h-[32rem] overflow-y-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30 sticky top-0">
                  <tr class="text-left text-[10px] font-bold uppercase tracking-wide">
                    <th class="px-3 py-2">City</th>
                    <th class="px-3 py-2 text-right">Median z&#322;/m&sup2;</th>
                    <th class="px-3 py-2 text-right">Median price</th>
                    <th class="px-3 py-2 text-right">Listings</th>
                    <th class="px-3 py-2 w-1/3"></th>
                  </tr>
                </thead>
                <tbody>
                  <% max_median = @city_medians |> Enum.map(& &1.median_sqm) |> Enum.max() %>
                  <%= for c <- @city_medians do %>
                    <tr class="border-t border-base-content/10 hover:bg-base-200/50">
                      <td class="px-3 py-1.5 font-bold"><%= c.city %></td>
                      <td class="px-3 py-1.5 text-right font-black"><%= axis_number(c.median_sqm) %></td>
                      <td class="px-3 py-1.5 text-right"><%= axis_number(c.median_price) %> z&#322;</td>
                      <td class="px-3 py-1.5 text-right opacity-60"><%= c.count %></td>
                      <td class="px-3 py-1.5">
                        <div class="h-3 rounded-sm" style={"width: #{round(c.median_sqm / max_median * 100)}%; background: var(--viz-1)"}></div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="p-8 text-center text-xs opacity-50">No cities with 10+ qualifying listings for this filter</div>
          <% end %>
        </div>

        <!-- Price Statistics -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <!-- Sale Prices -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-info/20">
              <h2 class="text-sm font-bold uppercase tracking-wide">💰 Sale Prices (Sprzedaż)</h2>
            </div>
            <%= if @stats.sale_price_stats.count > 0 do %>
              <div class="grid grid-cols-2 md:grid-cols-4 divide-x divide-base-content/20">
                <div class="p-4 text-center">
                  <div class="text-xl font-black text-info"><%= format_price_short(@stats.sale_price_stats.avg_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Avg Price</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-xl font-black"><%= format_price_short(@stats.sale_price_stats.avg_price_per_sqm) %>/m²</div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Avg per m²</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-lg font-black text-success"><%= format_price_short(@stats.sale_price_stats.min_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Min</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-lg font-black text-error"><%= format_price_short(@stats.sale_price_stats.max_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Max</div>
                </div>
              </div>
              <div class="px-4 py-2 bg-base-200 text-xs text-center opacity-60">
                Based on <%= @stats.sale_price_stats.count %> properties with price & area data
              </div>
            <% else %>
              <div class="p-4 text-center opacity-50">No sale data available</div>
            <% end %>
          </div>

          <!-- Rent Prices -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-warning/20">
              <h2 class="text-sm font-bold uppercase tracking-wide">🏠 Rent Prices (Wynajem)</h2>
            </div>
            <%= if @stats.rent_price_stats.count > 0 do %>
              <div class="grid grid-cols-2 md:grid-cols-4 divide-x divide-base-content/20">
                <div class="p-4 text-center">
                  <div class="text-xl font-black text-warning"><%= format_price_short(@stats.rent_price_stats.avg_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Avg Price</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-xl font-black"><%= format_price_short(@stats.rent_price_stats.avg_price_per_sqm) %>/m²</div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Avg per m²</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-lg font-black text-success"><%= format_price_short(@stats.rent_price_stats.min_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Min</div>
                </div>
                <div class="p-4 text-center">
                  <div class="text-lg font-black text-error"><%= format_price_short(@stats.rent_price_stats.max_price) %></div>
                  <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Max</div>
                </div>
              </div>
              <div class="px-4 py-2 bg-base-200 text-xs text-center opacity-60">
                Based on <%= @stats.rent_price_stats.count %> properties with price & area data
              </div>
            <% else %>
              <div class="p-4 text-center opacity-50">No rent data available</div>
            <% end %>
          </div>
        </div>

        <!-- Price Explorer (combines property type, transaction type, and district filtering) -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-3 border-b-2 border-base-content bg-gradient-to-r from-primary/20 to-secondary/20">
            <h2 class="text-sm font-bold uppercase tracking-wide">🔍 Price Explorer by District</h2>
            <p class="text-[10px] opacity-60">Full archive incl. delisted listings • Filter by property type and transaction type • Outliers excluded (Sale: 30k-50M zł, Rent: 300-100k zł)</p>
          </div>
          
          <!-- Filters -->
          <div class="px-4 py-3 border-b border-base-content/20 bg-base-200/50">
            <div class="flex flex-wrap gap-4 items-center">
              <!-- Property Type Filter -->
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Property:</span>
                <div class="flex flex-wrap gap-1">
                  <%= for {type, count} <- @property_types do %>
                    <button
                      phx-click="filter_property_type"
                      phx-value-type={type}
                      class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @selected_property_type == type, do: "bg-primary text-primary-content border-primary", else: "border-base-content/30 hover:bg-base-200"}"}
                    >
                      <%= type %> <span class="opacity-50">(<%= count %>)</span>
                    </button>
                  <% end %>
                </div>
              </div>
              
              <!-- Transaction Type Filter -->
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Transaction:</span>
                <div class="flex gap-1">
                  <button
                    phx-click="filter_transaction_type"
                    phx-value-type="all"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @selected_transaction_type == "all", do: "bg-base-content text-base-100 border-base-content", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    All
                  </button>
                  <button
                    phx-click="filter_transaction_type"
                    phx-value-type="sprzedaż"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @selected_transaction_type == "sprzedaż", do: "bg-info text-info-content border-info", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    Sprzedaż
                  </button>
                  <button
                    phx-click="filter_transaction_type"
                    phx-value-type="wynajem"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @selected_transaction_type == "wynajem", do: "bg-warning text-warning-content border-warning", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    Wynajem
                  </button>
                </div>
              </div>
            </div>
            
            <!-- Second Row: Area and Room Filters -->
            <div class="flex flex-wrap gap-4 items-center mt-3 pt-3 border-t border-base-content/10">
              <!-- Area Filter -->
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Area m²:</span>
                <form phx-change="filter_area" class="flex gap-1 items-center">
                  <input 
                    type="number" 
                    name="min_area" 
                    value={@min_area}
                    placeholder="min"
                    class="w-16 px-2 py-1 text-xs border border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                  />
                  <span class="text-xs opacity-40">—</span>
                  <input 
                    type="number" 
                    name="max_area" 
                    value={@max_area}
                    placeholder="max"
                    class="w-16 px-2 py-1 text-xs border border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                  />
                </form>
                <!-- Quick area presets -->
                <div class="flex gap-1">
                  <button phx-click="set_area_preset" phx-value-preset="small" class={"px-2 py-1 text-[10px] font-bold border transition-colors cursor-pointer #{if @min_area == 20 and @max_area == 40, do: "bg-accent text-accent-content border-accent", else: "border-base-content/20 hover:bg-base-200"}"}>20-40</button>
                  <button phx-click="set_area_preset" phx-value-preset="medium" class={"px-2 py-1 text-[10px] font-bold border transition-colors cursor-pointer #{if @min_area == 40 and @max_area == 60, do: "bg-accent text-accent-content border-accent", else: "border-base-content/20 hover:bg-base-200"}"}>40-60</button>
                  <button phx-click="set_area_preset" phx-value-preset="large" class={"px-2 py-1 text-[10px] font-bold border transition-colors cursor-pointer #{if @min_area == 60 and @max_area == 100, do: "bg-accent text-accent-content border-accent", else: "border-base-content/20 hover:bg-base-200"}"}>60-100</button>
                  <button phx-click="set_area_preset" phx-value-preset="clear" class="px-2 py-1 text-[10px] font-bold border border-base-content/20 hover:bg-base-200 transition-colors cursor-pointer">✕</button>
                </div>
              </div>
              
              <!-- Rooms Filter -->
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Rooms:</span>
                <div class="flex gap-1">
                  <button phx-click="filter_rooms" phx-value-rooms="1" class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @min_rooms == 1 and @max_rooms == 1, do: "bg-secondary text-secondary-content border-secondary", else: "border-base-content/30 hover:bg-base-200"}"}>1</button>
                  <button phx-click="filter_rooms" phx-value-rooms="2" class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @min_rooms == 2 and @max_rooms == 2, do: "bg-secondary text-secondary-content border-secondary", else: "border-base-content/30 hover:bg-base-200"}"}>2</button>
                  <button phx-click="filter_rooms" phx-value-rooms="3" class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @min_rooms == 3 and @max_rooms == 3, do: "bg-secondary text-secondary-content border-secondary", else: "border-base-content/30 hover:bg-base-200"}"}>3</button>
                  <button phx-click="filter_rooms" phx-value-rooms="4+" class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @min_rooms == 4 and @max_rooms == nil, do: "bg-secondary text-secondary-content border-secondary", else: "border-base-content/30 hover:bg-base-200"}"}>4+</button>
                  <button phx-click="filter_rooms" phx-value-rooms="clear" class="px-2 py-1 text-xs font-bold border border-base-content/30 hover:bg-base-200 transition-colors cursor-pointer">All</button>
                </div>
              </div>
              
            </div>
          </div>

          <!-- Results Table -->
          <%= if length(@filtered_district_prices) > 0 do %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30">
                  <%= if @selected_transaction_type == "all" do %>
                    <tr>
                      <th class="px-3 py-2 text-left text-[10px] font-bold uppercase tracking-wide">
                        <.sort_header column="district" label="District" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </th>
                      <th class="px-3 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-info" colspan="5">Sprzedaż</th>
                      <th class="px-3 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-warning" colspan="5">Wynajem</th>
                    </tr>
                    <tr class="bg-base-100">
                      <th class="px-3 py-1"></th>
                      <th class="px-1 py-1"><.sort_header column="sale_count" label="#" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="sale_avg" label="Avg" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="sale_min" label="Min" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="sale_max" label="Max" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="sale_sqm" label="/m²" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="rent_count" label="#" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="rent_avg" label="Avg" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="rent_min" label="Min" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="rent_max" label="Max" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                      <th class="px-1 py-1"><.sort_header column="rent_sqm" label="/m²" sort_by={@sort_by} sort_dir={@sort_dir} small={true} /></th>
                    </tr>
                  <% else %>
                    <tr>
                      <th class="px-4 py-2 text-left"><.sort_header column="district" label="District" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                      <th class="px-2 py-2 text-center"><.sort_header column="count" label="#" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                      <th class="px-2 py-2 text-center"><.sort_header column="avg" label="Avg Price" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                      <th class="px-2 py-2 text-center"><.sort_header column="min" label="Min" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                      <th class="px-2 py-2 text-center"><.sort_header column="max" label="Max" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                      <th class="px-2 py-2 text-center"><.sort_header column="sqm" label="Avg/m²" sort_by={@sort_by} sort_dir={@sort_dir} /></th>
                    </tr>
                  <% end %>
                </thead>
                <tbody class="divide-y divide-base-content/20">
                  <%= for item <- @filtered_district_prices do %>
                    <%= if item.mode == :both do %>
                      <tr 
                        class={"hover:bg-base-200/50 cursor-pointer #{if @expanded_district == item.district, do: "bg-primary/10"}"}
                        phx-click="toggle_district"
                        phx-value-district={item.district}
                      >
                        <td class="px-3 py-2 font-bold text-sm">
                          <span class="inline-flex items-center gap-1">
                            <span class={"transition-transform #{if @expanded_district == item.district, do: "rotate-90"}"}>▶</span>
                            <%= item.district %>
                          </span>
                        </td>
                        <td class="px-1 py-2 text-center text-info text-xs"><%= item.sale.count %></td>
                        <td class="px-1 py-2 text-center font-bold text-xs"><%= format_price_short(item.sale.avg_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] text-success"><%= format_price_short(item.sale.min_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] text-error"><%= format_price_short(item.sale.max_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] opacity-70"><%= format_price_short(item.sale.avg_per_sqm) %></td>
                        <td class="px-1 py-2 text-center text-warning text-xs"><%= item.rent.count %></td>
                        <td class="px-1 py-2 text-center font-bold text-xs"><%= format_price_short(item.rent.avg_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] text-success"><%= format_price_short(item.rent.min_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] text-error"><%= format_price_short(item.rent.max_price) %></td>
                        <td class="px-1 py-2 text-center text-[10px] opacity-70"><%= format_price_short(item.rent.avg_per_sqm) %></td>
                      </tr>
                      <!-- Expanded properties row -->
                      <%= if @expanded_district == item.district do %>
                        <tr>
                          <td colspan="11" class="p-0">
                            <.district_properties_panel 
                              properties={@district_properties} 
                              district={item.district}
                              transaction_type={@selected_transaction_type}
                            />
                          </td>
                        </tr>
                      <% end %>
                    <% else %>
                      <tr 
                        class={"hover:bg-base-200/50 cursor-pointer #{if @expanded_district == item.district, do: "bg-primary/10"}"}
                        phx-click="toggle_district"
                        phx-value-district={item.district}
                      >
                        <td class="px-4 py-2 font-bold">
                          <span class="inline-flex items-center gap-1">
                            <span class={"transition-transform #{if @expanded_district == item.district, do: "rotate-90"}"}>▶</span>
                            <%= item.district %>
                          </span>
                        </td>
                        <td class={"px-2 py-2 text-center #{if item.transaction_type == "sprzedaż", do: "text-info", else: "text-warning"}"}><%= item.stats.count %></td>
                        <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.stats.avg_price) %></td>
                        <td class="px-2 py-2 text-center text-success"><%= format_price_short(item.stats.min_price) %></td>
                        <td class="px-2 py-2 text-center text-error"><%= format_price_short(item.stats.max_price) %></td>
                        <td class="px-2 py-2 text-center opacity-70"><%= format_price_short(item.stats.avg_per_sqm) %></td>
                      </tr>
                      <!-- Expanded properties row -->
                      <%= if @expanded_district == item.district do %>
                        <tr>
                          <td colspan="6" class="p-0">
                            <.district_properties_panel 
                              properties={@district_properties} 
                              district={item.district}
                              transaction_type={@selected_transaction_type}
                            />
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="p-8 text-center opacity-50">
              <p class="text-sm">No data available for selected filters</p>
            </div>
          <% end %>
        </div>

        <!-- Sources & Cities Row (condensed) -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <!-- Sources -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">📡 Sources</h2>
            </div>
            <div class="p-4 flex gap-4">
              <%= for {source, count} <- @stats.by_source do %>
                <div class="flex-1 text-center">
                  <div class="font-black text-2xl"><%= count %></div>
                  <div class="text-xs font-bold uppercase opacity-60"><%= source %></div>
                  <div class="text-[10px] opacity-40"><%= Float.round(count / max(@stats.active_properties, 1) * 100, 1) %>%</div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Top Cities (condensed) -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">🏙️ Top Cities</h2>
            </div>
            <div class="p-4 flex gap-3 overflow-x-auto">
              <%= for {{city, count}, index} <- Enum.with_index(Enum.take(@stats.top_cities, 5)) do %>
                <div class={"text-center min-w-[60px] #{if index == 0, do: "text-primary"}"}>
                  <div class="font-black text-xl"><%= count %></div>
                  <div class="text-[10px] font-bold uppercase opacity-60 truncate"><%= city || "?" %></div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Room Distribution -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">🛏️ Room Distribution</h2>
          </div>
          <%= if length(@stats.room_distribution) > 0 do %>
            <div class="p-4">
              <div class="flex items-end gap-2" style="height: 120px;">
                <%= for {rooms, count} <- @stats.room_distribution do %>
                  <div class="flex-1 flex flex-col items-center h-full">
                    <div class="text-xs font-bold mb-1"><%= count %></div>
                    <div class="flex-1 w-full flex flex-col justify-end">
                      <div 
                        class="w-full bg-primary/80 hover:bg-primary transition-colors rounded-t min-h-[4px]"
                        style={"height: #{calc_bar_height(@stats.room_distribution, count)}px"}
                        title={"#{rooms} rooms: #{count} properties"}
                      ></div>
                    </div>
                    <div class="text-xs font-bold mt-2 opacity-60"><%= rooms %></div>
                  </div>
                <% end %>
              </div>
              <div class="text-center text-xs opacity-50 mt-2">Number of rooms</div>
            </div>
          <% else %>
            <div class="p-4 text-center opacity-50">No room data available</div>
          <% end %>
        </div>

        <!-- Data Quality -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">📊 Data Quality</h2>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 divide-x divide-base-content/20">
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_price %></span>
                <span class="text-xs font-bold text-success mb-1"><%= Float.round(@stats.with_price / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Price</div>
              <div class="mt-2 h-2 bg-base-300 rounded">
                <div class="h-2 bg-success rounded" style={"width: #{Float.round(@stats.with_price / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
              <div class="text-[10px] text-error mt-1"><%= @stats.missing_price %> missing</div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_area %></span>
                <span class="text-xs font-bold text-success mb-1"><%= Float.round(@stats.with_area / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Area</div>
              <div class="mt-2 h-2 bg-base-300 rounded">
                <div class="h-2 bg-success rounded" style={"width: #{Float.round(@stats.with_area / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
              <div class="text-[10px] text-error mt-1"><%= @stats.missing_area %> missing</div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.with_rooms %></span>
                <span class="text-xs font-bold text-warning mb-1"><%= Float.round(@stats.with_rooms / max(@stats.active_properties, 1) * 100, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Rooms</div>
              <div class="mt-2 h-2 bg-base-300 rounded">
                <div class="h-2 bg-warning rounded" style={"width: #{Float.round(@stats.with_rooms / max(@stats.active_properties, 1) * 100, 0)}%"}></div>
              </div>
              <div class="text-[10px] text-error mt-1"><%= @stats.missing_rooms %> missing</div>
            </div>
            <div class="p-4">
              <div class="flex items-end gap-2">
                <span class="font-black text-2xl"><%= @stats.geocoded_count %></span>
                <span class="text-xs font-bold text-info mb-1"><%= Float.round(@stats.geocoded_percentage, 0) %>%</span>
              </div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">With Location</div>
              <div class="mt-2 h-2 bg-base-300 rounded">
                <div class="h-2 bg-info rounded" style={"width: #{Float.round(@stats.geocoded_percentage, 0)}%"}></div>
              </div>
              <div class="text-[10px] text-error mt-1"><%= @stats.missing_location %> missing</div>
            </div>
          </div>
          <div class="px-4 py-2 bg-base-200 border-t border-base-content/20">
            <div class="flex justify-between items-center">
              <span class="text-xs font-bold uppercase tracking-wide opacity-60">Complete Data (all fields)</span>
              <span class="font-black text-lg"><%= @stats.complete_data %> <span class="text-xs font-normal opacity-60">(<%= Float.round(@stats.complete_data / max(@stats.active_properties, 1) * 100, 1) %>%)</span></span>
            </div>
          </div>
        </div>

        <!-- Recent Activity (condensed bar view) -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">📅 Last 7 Days</h2>
          </div>
          <div class="p-4">
            <div class="flex items-end justify-between gap-2" style="height: 80px;">
              <%= for day <- Enum.reverse(@stats.recent_activity) do %>
                <% max_total = Enum.max_by(@stats.recent_activity, & &1.total).total %>
                <% height_pct = if max_total > 0, do: day.total / max_total * 100, else: 0 %>
                <div class="flex-1 flex flex-col items-center h-full">
                  <div class="text-[10px] font-bold mb-1"><%= day.total %></div>
                  <div class="flex-1 w-full flex flex-col justify-end">
                    <div class="w-full rounded-t flex flex-col overflow-hidden" style={"height: #{trunc(height_pct * 0.6)}px; min-height: 4px;"}>
                      <div class="bg-primary flex-1" title={"OLX: #{day.olx}"}></div>
                      <div class="bg-secondary flex-1" title={"Otodom: #{day.otodom}"}></div>
                    </div>
                  </div>
                  <div class="text-[9px] opacity-50 mt-1"><%= String.slice(day.date, 5, 5) %></div>
                </div>
              <% end %>
            </div>
            <div class="flex gap-4 mt-3 justify-center text-[10px]">
              <span><span class="inline-block w-3 h-3 bg-primary mr-1"></span> OLX</span>
              <span><span class="inline-block w-3 h-3 bg-secondary mr-1"></span> Otodom</span>
            </div>
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

  # --- SVG chart components (no JS deps; hover via native <title> tooltips) ---

  # ponytail: native SVG <title> tooltips instead of a JS crosshair layer;
  # upgrade to a Svelte chart component if richer interaction is ever needed

  @chart_w 560
  @chart_h 200
  @pad_l 46
  @pad_r 10
  @pad_t 12
  @pad_b 24

  defp trend_chart(assigns) do
    rows = assigns.rows
    plot_w = @chart_w - @pad_l - @pad_r
    plot_h = @chart_h - @pad_t - @pad_b

    if length(rows) < 2 do
      ~H"""
      <div class="p-8 text-center text-xs opacity-50">Not enough monthly data yet — check back after a few scrape cycles</div>
      """
    else
      vals = Enum.map(rows, & &1.value)
      {vmin, vmax} = {Enum.min(vals), Enum.max(vals)}
      span = max(vmax - vmin, max(vmax * 0.05, 1.0))
      dmin = vmin - span * 0.1
      dmax = vmax + span * 0.1

      n = length(rows)
      dx = plot_w / (n - 1)

      pts =
        rows
        |> Enum.with_index()
        |> Enum.map(fn {r, i} ->
          %{
            x: Float.round(@pad_l + i * dx, 1),
            y: Float.round(@pad_t + plot_h - (r.value - dmin) / (dmax - dmin) * plot_h, 1),
            row: r
          }
        end)

      ticks =
        Enum.map(1..3, fn i ->
          v = dmin + (dmax - dmin) * i / 4
          %{y: Float.round(@pad_t + plot_h - i / 4 * plot_h, 1), label: axis_number(v)}
        end)

      # label roughly 6 x-axis months, always including first and last
      step = max(div(n - 1, 5), 1)
      x_labels =
        pts
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> rem(i, step) == 0 or i == n - 1 end)
        |> Enum.map(fn {pt, _} -> pt end)

      last = List.last(pts)

      assigns =
        assign(assigns,
          pts: pts,
          poly: Enum.map_join(pts, " ", &"#{&1.x},#{&1.y}"),
          ticks: ticks,
          x_labels: x_labels,
          last: last,
          baseline_y: @pad_t + plot_h
        )

      ~H"""
      <svg viewBox="0 0 560 200" class="w-full" role="img" aria-label={@label}>
        <%= for tick <- @ticks do %>
          <line x1="46" y1={tick.y} x2="550" y2={tick.y} class="stroke-base-content/10" stroke-width="1" />
          <text x="40" y={tick.y + 3} text-anchor="end" class="fill-base-content/50" font-size="9"><%= tick.label %></text>
        <% end %>
        <line x1="46" y1={@baseline_y} x2="550" y2={@baseline_y} class="stroke-base-content/25" stroke-width="1" />
        <%= for pt <- @x_labels do %>
          <text x={pt.x} y="194" text-anchor="middle" class="fill-base-content/50" font-size="9"><%= short_month(pt.row.month) %></text>
        <% end %>
        <polyline points={@poly} fill="none" stroke={@color} stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
        <%= for pt <- @pts do %>
          <g>
            <circle cx={pt.x} cy={pt.y} r="9" fill="transparent">
              <title><%= "#{short_month(pt.row.month)}: #{axis_number(pt.row.value)} #{@unit} (#{pt.row.count} listings)" %></title>
            </circle>
            <circle cx={pt.x} cy={pt.y} r="2.5" fill={@color} pointer-events="none" />
          </g>
        <% end %>
        <text x={min(@last.x, 548)} y={max(@last.y - 8, 10)} text-anchor="end" class="fill-base-content" font-size="10" font-weight="bold">
          <%= axis_number(@last.row.value) %> <%= @unit %>
        </text>
      </svg>
      """
    end
  end

  defp volume_chart(assigns) do
    rows = assigns.rows
    plot_w = @chart_w - @pad_l - @pad_r
    plot_h = @chart_h - @pad_t - @pad_b

    if rows == [] do
      ~H"""
      <div class="p-8 text-center text-xs opacity-50">No data yet</div>
      """
    else
      n = length(rows)
      band = plot_w / n
      bar_w = Float.round(max(band * 0.7, 2.0), 1)
      vmax = rows |> Enum.map(&(&1.olx + &1.otodom + &1.other)) |> Enum.max() |> max(1)

      bars =
        rows
        |> Enum.with_index()
        |> Enum.map(fn {r, i} ->
          x = Float.round(@pad_l + i * band + (band - bar_w) / 2, 1)
          # stacked segments bottom-up with a 2px surface gap between them
          segments =
            [{r.olx, "olx"}, {r.otodom, "otodom"}, {r.other, "other"}]
            |> Enum.reject(fn {count, _} -> count == 0 end)

          {rects, _} =
            Enum.map_reduce(segments, @pad_t + plot_h, fn {count, source}, y_bottom ->
              h = count / vmax * plot_h
              {%{x: x, y: Float.round(y_bottom - h, 1), h: Float.round(max(h - 2, 1.0), 1), source: source, count: count},
               y_bottom - h}
            end)

          %{x: x, month: r.month, total: r.olx + r.otodom + r.other, rects: rects}
        end)

      step = max(div(n - 1, 5), 1)

      x_labels =
        bars
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> rem(i, step) == 0 or i == n - 1 end)
        |> Enum.map(fn {b, _} -> b end)

      ticks =
        Enum.map(1..3, fn i ->
          %{
            y: Float.round(@pad_t + plot_h - i / 4 * plot_h, 1),
            label: axis_number(vmax * i / 4)
          }
        end)

      assigns =
        assign(assigns, bars: bars, bar_w: bar_w, ticks: ticks, x_labels: x_labels, baseline_y: @pad_t + plot_h)

      ~H"""
      <svg viewBox="0 0 560 200" class="w-full" role="img" aria-label="New listings per month by source">
        <%= for tick <- @ticks do %>
          <line x1="46" y1={tick.y} x2="550" y2={tick.y} class="stroke-base-content/10" stroke-width="1" />
          <text x="40" y={tick.y + 3} text-anchor="end" class="fill-base-content/50" font-size="9"><%= tick.label %></text>
        <% end %>
        <line x1="46" y1={@baseline_y} x2="550" y2={@baseline_y} class="stroke-base-content/25" stroke-width="1" />
        <%= for bar <- @bars do %>
          <g>
            <%= for rect <- bar.rects do %>
              <rect x={rect.x} y={rect.y} width={@bar_w} height={rect.h} rx="1" fill={source_color(rect.source)} />
            <% end %>
            <rect x={bar.x} y="12" width={@bar_w} height="164" fill="transparent">
              <title><%= "#{short_month(bar.month)}: #{bar.total} listings (#{Enum.map_join(bar.rects, ", ", &"#{&1.source} #{&1.count}")})" %></title>
            </rect>
          </g>
        <% end %>
        <%= for bar <- @x_labels do %>
          <text x={bar.x + @bar_w / 2} y="194" text-anchor="middle" class="fill-base-content/50" font-size="9"><%= short_month(bar.month) %></text>
        <% end %>
      </svg>
      """
    end
  end

  # Palette validated with dataviz six-checks for light+dark surfaces
  # (blue #2a78d6 / aqua #1baf7a / yellow #eda100)
  defp source_color("olx"), do: "var(--viz-1)"
  defp source_color("otodom"), do: "var(--viz-2)"
  defp source_color(_), do: "var(--viz-3)"

  defp axis_number(v) when is_number(v) do
    cond do
      v >= 1_000_000 -> "#{Float.round(v / 1_000_000, 1)}M"
      v >= 10_000 -> "#{round(v / 1000)}k"
      v >= 1_000 -> "#{Float.round(v / 1000, 1)}k"
      true -> "#{round(v)}"
    end
  end

  defp axis_number(_), do: "—"

  @month_names ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  defp short_month(<<year::binary-4, "-", mm::binary-2>>) do
    "#{Enum.at(@month_names, String.to_integer(mm) - 1)} '#{String.slice(year, 2, 2)}"
  end

  defp short_month(other), do: other

  attr :column, :string, required: true
  attr :label, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :small, :boolean, default: false

  defp sort_header(assigns) do
    ~H"""
    <button
      phx-click="sort_prices"
      phx-value-column={@column}
      class={[
        "flex items-center gap-1 cursor-pointer hover:text-primary transition-colors",
        if(@small, do: "text-[9px] font-bold uppercase opacity-60", else: "text-[10px] font-bold uppercase tracking-wide")
      ]}
    >
      <%= @label %>
      <%= if @sort_by == @column do %>
        <span class="text-primary">
          <%= if @sort_dir == :desc, do: "↓", else: "↑" %>
        </span>
      <% end %>
    </button>
    """
  end

  attr :properties, :list, required: true
  attr :district, :string, required: true
  attr :transaction_type, :string, required: true

  defp district_properties_panel(assigns) do
    ~H"""
    <div class="bg-base-200/50 border-t border-b border-base-content/20">
      <div class="px-4 py-2 border-b border-base-content/10 bg-base-300/50">
        <span class="text-xs font-bold uppercase tracking-wide opacity-60">
          📋 Listings in <%= @district %> 
          <span class="font-normal">(<%= length(@properties) %> shown, max 20)</span>
        </span>
      </div>
      
      <%= if length(@properties) == 0 do %>
        <div class="p-4 text-center text-sm opacity-50">
          No properties found with current filters
        </div>
      <% else %>
        <div class="max-h-[400px] overflow-y-auto">
          <table class="w-full text-xs">
            <thead class="bg-base-300/30 sticky top-0">
              <tr>
                <th class="px-3 py-1.5 text-left font-bold uppercase tracking-wide opacity-60">Title</th>
                <th class="px-2 py-1.5 text-center font-bold uppercase tracking-wide opacity-60">Type</th>
                <th class="px-2 py-1.5 text-right font-bold uppercase tracking-wide opacity-60">Price</th>
                <th class="px-2 py-1.5 text-right font-bold uppercase tracking-wide opacity-60">Area</th>
                <th class="px-2 py-1.5 text-center font-bold uppercase tracking-wide opacity-60">Rooms</th>
                <th class="px-2 py-1.5 text-right font-bold uppercase tracking-wide opacity-60">/m²</th>
                <th class="px-2 py-1.5 text-center font-bold uppercase tracking-wide opacity-60">Source</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-content/10">
              <%= for prop <- @properties do %>
                <tr class="hover:bg-base-100/50">
                  <td class="px-3 py-2 max-w-[300px]">
                    <a 
                      href={prop.url} 
                      target="_blank" 
                      class="text-primary hover:underline truncate block"
                      title={prop.title}
                    >
                      <%= truncate_title(prop.title, 50) %>
                    </a>
                    <%= if prop[:active] == false do %>
                      <span class="text-[9px] font-bold uppercase px-1 border border-base-content/30 opacity-50">delisted</span>
                    <% end %>
                  </td>
                  <td class={"px-2 py-2 text-center #{if prop.transaction_type == "sprzedaż", do: "text-info", else: "text-warning"}"}>
                    <%= if prop.transaction_type == "sprzedaż", do: "Sale", else: "Rent" %>
                  </td>
                  <td class="px-2 py-2 text-right font-bold">
                    <%= format_price_short(prop.price) %>
                  </td>
                  <td class="px-2 py-2 text-right">
                    <%= if prop.area_sqm, do: "#{Decimal.round(prop.area_sqm, 0)} m²", else: "—" %>
                  </td>
                  <td class="px-2 py-2 text-center">
                    <%= prop.rooms || "—" %>
                  </td>
                  <td class="px-2 py-2 text-right opacity-70">
                    <%= if prop.price && prop.area_sqm && Decimal.compare(prop.area_sqm, Decimal.new(0)) == :gt do %>
                      <%= format_price_short(Decimal.div(prop.price, prop.area_sqm)) %>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="px-2 py-2 text-center">
                    <span class={"px-1.5 py-0.5 text-[10px] font-bold uppercase rounded #{if prop.source == "olx", do: "bg-primary/20 text-primary", else: "bg-secondary/20 text-secondary"}"}>
                      <%= prop.source %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp truncate_title(nil, _), do: "—"
  defp truncate_title(title, max_length) when byte_size(title) <= max_length, do: title
  defp truncate_title(title, max_length), do: String.slice(title, 0, max_length) <> "…"

  @impl true
  def handle_event("city_property_type", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:city_property_type, type)
     |> assign(:city_medians, calculate_city_medians(type, socket.assigns.city_transaction_type))}
  end

  def handle_event("city_transaction_type", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:city_transaction_type, type)
     |> assign(:city_medians, calculate_city_medians(socket.assigns.city_property_type, type))}
  end

  def handle_event("refresh_stats", _params, socket) do
    socket =
      socket
      |> assign(:refreshing, true)
      |> assign(:stats, calculate_stats())
      |> assign(:market, calculate_market_stats())
      |> assign(:city_medians, calculate_city_medians(
          socket.assigns.city_property_type,
          socket.assigns.city_transaction_type
        ))
      |> assign(:filtered_district_prices, calculate_filtered_district_prices(
          socket.assigns.selected_property_type,
          socket.assigns.selected_transaction_type
        ))
      |> assign(:last_updated, DateTime.utc_now())
      |> assign(:refreshing, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_property_type", %{"type" => type}, socket) do
    socket =
      socket
      |> assign(:selected_property_type, type)
      |> refresh_district_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_transaction_type", %{"type" => type}, socket) do
    # Reset sort to appropriate default when switching transaction type
    default_sort = if type == "all", do: "sale_count", else: "count"
    
    socket =
      socket
      |> assign(:selected_transaction_type, type)
      |> assign(:sort_by, default_sort)
      |> refresh_district_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_area", %{"min_area" => min_str, "max_area" => max_str}, socket) do
    min_area = parse_int_or_nil(min_str)
    max_area = parse_int_or_nil(max_str)
    
    socket =
      socket
      |> assign(:min_area, min_area)
      |> assign(:max_area, max_area)
      |> refresh_district_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_area_preset", %{"preset" => preset}, socket) do
    {min_area, max_area} = case preset do
      "small" -> {20, 40}
      "medium" -> {40, 60}
      "large" -> {60, 100}
      "clear" -> {nil, nil}
      _ -> {nil, nil}
    end
    
    socket =
      socket
      |> assign(:min_area, min_area)
      |> assign(:max_area, max_area)
      |> refresh_district_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_rooms", %{"rooms" => rooms_str}, socket) do
    {min_rooms, max_rooms} = case rooms_str do
      "1" -> {1, 1}
      "2" -> {2, 2}
      "3" -> {3, 3}
      "4+" -> {4, nil}
      "clear" -> {nil, nil}
      _ -> {nil, nil}
    end
    
    socket =
      socket
      |> assign(:min_rooms, min_rooms)
      |> assign(:max_rooms, max_rooms)
      |> refresh_district_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_district", %{"district" => district}, socket) do
    socket = if socket.assigns.expanded_district == district do
      # Collapse
      socket
      |> assign(:expanded_district, nil)
      |> assign(:district_properties, [])
    else
      # Expand with properties
      properties = fetch_district_properties(
        district,
        socket.assigns.selected_property_type,
        socket.assigns.selected_transaction_type,
        socket.assigns.min_area,
        socket.assigns.max_area,
        socket.assigns.min_rooms,
        socket.assigns.max_rooms
      )
      
      socket
      |> assign(:expanded_district, district)
      |> assign(:district_properties, properties)
    end
    
    {:noreply, socket}
  end

  defp parse_int_or_nil(""), do: nil
  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp refresh_district_prices(socket) do
    filtered = calculate_filtered_district_prices(
      socket.assigns.selected_property_type,
      socket.assigns.selected_transaction_type,
      socket.assigns.min_area,
      socket.assigns.max_area,
      socket.assigns.min_rooms,
      socket.assigns.max_rooms
    )
    
    socket
    |> assign(:filtered_district_prices, filtered)
    |> assign(:expanded_district, nil)
    |> assign(:district_properties, [])
    |> sort_filtered_prices()
  end

  @impl true
  def handle_event("sort_prices", %{"column" => column}, socket) do
    # Toggle direction if same column, otherwise default to desc
    new_dir = if socket.assigns.sort_by == column do
      if socket.assigns.sort_dir == :desc, do: :asc, else: :desc
    else
      :desc
    end
    
    socket =
      socket
      |> assign(:sort_by, column)
      |> assign(:sort_dir, new_dir)
      |> sort_filtered_prices()

    {:noreply, socket}
  end

  # Market analytics over ALL properties (including delisted ones) - the
  # historical archive is what makes trends and velocity computable
  defp calculate_city_medians(property_type, transaction_type) do
    {pmin, pmax} = price_range(transaction_type)

    Repo.all(
      from p in Property,
        where:
          p.transaction_type == ^transaction_type and p.property_type == ^property_type and
            not is_nil(p.price) and p.price >= ^pmin and p.price <= ^pmax and
            not is_nil(p.area_sqm) and p.area_sqm > 0 and not is_nil(p.city),
        group_by: fragment("SPLIT_PART(?, ',', 1)", p.city),
        having: count(p.id) >= 10,
        order_by: [
          desc:
            fragment(
              "percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::float / ?::float)",
              p.price,
              p.area_sqm
            )
        ],
        select: %{
          city: fragment("SPLIT_PART(?, ',', 1)", p.city),
          median_sqm:
            fragment(
              "percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::float / ?::float)",
              p.price,
              p.area_sqm
            ),
          median_price: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::float)", p.price),
          count: count(p.id)
        }
    )
  end

  defp calculate_market_stats do
    {sale_min, sale_max} = price_range("sprzedaż")
    {rent_min, rent_max} = price_range("wynajem")

    monthly_sale =
      Repo.all(
        from p in Property,
          where:
            p.transaction_type == "sprzedaż" and p.property_type == "mieszkanie" and
              not is_nil(p.price) and p.price >= ^sale_min and p.price <= ^sale_max and
              not is_nil(p.area_sqm) and p.area_sqm > 0,
          group_by: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
          order_by: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
          select: %{
            month: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
            value:
              fragment(
                "percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::float / ?::float)",
                p.price,
                p.area_sqm
              ),
            count: count(p.id)
          }
      )

    monthly_rent =
      Repo.all(
        from p in Property,
          where:
            p.transaction_type == "wynajem" and p.property_type == "mieszkanie" and
              not is_nil(p.price) and p.price >= ^rent_min and p.price <= ^rent_max,
          group_by: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
          order_by: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
          select: %{
            month: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
            value: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::float)", p.price),
            count: count(p.id)
          }
      )

    monthly_volume =
      Repo.all(
        from p in Property,
          group_by: [fragment("to_char(?, 'YYYY-MM')", p.inserted_at), p.source],
          order_by: fragment("to_char(?, 'YYYY-MM')", p.inserted_at),
          select: {fragment("to_char(?, 'YYYY-MM')", p.inserted_at), p.source, count(p.id)}
      )
      |> Enum.group_by(fn {month, _, _} -> month end)
      |> Enum.map(fn {month, rows} ->
        by_source = Map.new(rows, fn {_, source, count} -> {source, count} end)
        olx = Map.get(by_source, "olx", 0)
        otodom = Map.get(by_source, "otodom", 0)
        other = (by_source |> Map.values() |> Enum.sum()) - olx - otodom
        %{month: month, olx: olx, otodom: otodom, other: other}
      end)
      |> Enum.sort_by(& &1.month)

    velocity =
      Repo.all(
        from p in Property,
          where:
            p.active == false and not is_nil(p.last_seen_at) and
              not is_nil(p.transaction_type) and p.last_seen_at > p.inserted_at,
          group_by: p.transaction_type,
          select: %{
            key: p.transaction_type,
            median_days:
              fragment(
                "percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (? - ?)) / 86400.0)",
                p.last_seen_at,
                p.inserted_at
              ),
            count: count(p.id)
          }
      )

    velocity_by_type =
      Repo.all(
        from p in Property,
          where:
            p.active == false and not is_nil(p.last_seen_at) and
              not is_nil(p.property_type) and p.last_seen_at > p.inserted_at,
          group_by: p.property_type,
          having: count(p.id) >= 10,
          order_by: [
            asc:
              fragment(
                "percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (? - ?)) / 86400.0)",
                p.last_seen_at,
                p.inserted_at
              )
          ],
          select: %{
            key: p.property_type,
            median_days:
              fragment(
                "percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (? - ?)) / 86400.0)",
                p.last_seen_at,
                p.inserted_at
              ),
            count: count(p.id)
          }
      )

    %{
      monthly_sale: monthly_sale,
      monthly_rent: monthly_rent,
      monthly_volume: monthly_volume,
      velocity: Map.new(velocity, &{&1.key, &1}),
      velocity_by_type: velocity_by_type,
      tracked_since: Repo.one(from p in Property, select: min(p.inserted_at)),
      delisted_count:
        Repo.aggregate(from(p in Property, where: p.active == false), :count, :id)
    }
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

    # Top cities - normalize by extracting base city name (before comma)
    # This groups "Kraków", "Kraków, Stare Miasto", "Kraków, Podgórze" all as "Kraków"
    top_cities =
      Repo.all(
        from p in Property,
          where: p.active == true and not is_nil(p.city),
          group_by: fragment("SPLIT_PART(?, ',', 1)", p.city),
          select: {fragment("SPLIT_PART(?, ',', 1)", p.city), count(p.id)},
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

    # Price statistics for sale properties
    sale_price_stats = calculate_price_stats("sprzedaż")
    rent_price_stats = calculate_price_stats("wynajem")

    
    # Room distribution
    room_distribution =
      Repo.all(
        from p in Property,
          where: p.active == true and not is_nil(p.rooms),
          group_by: p.rooms,
          select: {p.rooms, count(p.id)},
          order_by: p.rooms
      )
      |> Enum.take(8)

    # Stale properties (not seen in 96+ hours / 4 days)
    cutoff = DateTime.utc_now() |> DateTime.add(-@stale_hours * 3600, :second)
    stale_count = Repo.aggregate(
      from(p in Property, where: p.active == true and p.last_seen_at < ^cutoff),
      :count, :id
    )

    stale_by_source = from(p in Property,
      where: p.active == true and p.last_seen_at < ^cutoff,
      group_by: p.source,
      select: {p.source, count(p.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})

    # Missing data breakdown
    missing_price = Repo.aggregate(from(p in Property, where: p.active == true and is_nil(p.price)), :count, :id)
    missing_area = Repo.aggregate(from(p in Property, where: p.active == true and is_nil(p.area_sqm)), :count, :id)
    missing_rooms = Repo.aggregate(from(p in Property, where: p.active == true and is_nil(p.rooms)), :count, :id)
    missing_location = Repo.aggregate(from(p in Property, where: p.active == true and is_nil(p.latitude)), :count, :id)

    %{
      total_properties: total_properties,
      active_properties: active_properties,
      geocoded_count: geocoded_count,
      geocoded_percentage: geocoded_percentage,
      aqi_count: aqi_count,
      aqi_percentage: aqi_percentage,
      added_today: added_today,
      by_source: by_source,
      top_cities: top_cities,
      with_price: with_price,
      with_area: with_area,
      with_rooms: with_rooms,
      complete_data: complete_data,
      recent_activity: recent_activity,
      price_drops: price_drops,
      sale_price_stats: sale_price_stats,
      rent_price_stats: rent_price_stats,
      room_distribution: room_distribution,
      stale_count: stale_count,
      stale_by_source: stale_by_source,
      missing_price: missing_price,
      missing_area: missing_area,
      missing_rooms: missing_rooms,
      missing_location: missing_location
    }
  end

  defp calculate_price_stats(transaction_type) do
    {min_valid, max_valid} = price_range(transaction_type)
    
    query = from p in Property,
      where: p.active == true and 
             p.transaction_type == ^transaction_type and 
             not is_nil(p.price) and 
             p.price >= ^min_valid and
             p.price <= ^max_valid and
             not is_nil(p.area_sqm) and
             p.area_sqm > 0

    count = Repo.aggregate(query, :count, :id)
    
    if count > 0 do
      avg_price = Repo.aggregate(query, :avg, :price)
      min_price = Repo.aggregate(query, :min, :price)
      max_price = Repo.aggregate(query, :max, :price)
      
      # Calculate average price per sqm
      avg_price_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.transaction_type == ^transaction_type and 
                 not is_nil(p.price) and 
                 p.price >= ^min_valid and
                 p.price <= ^max_valid and
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      %{
        count: count,
        avg_price: avg_price && Decimal.round(avg_price, 0),
        min_price: min_price,
        max_price: max_price,
        avg_price_per_sqm: avg_price_per_sqm && Decimal.round(avg_price_per_sqm, 0)
      }
    else
      %{count: 0, avg_price: nil, min_price: nil, max_price: nil, avg_price_per_sqm: nil}
    end
  end

  defp sort_filtered_prices(socket) do
    prices = socket.assigns.filtered_district_prices
    sort_by = socket.assigns.sort_by
    sort_dir = socket.assigns.sort_dir
    mode = socket.assigns.selected_transaction_type
    
    sorted = Enum.sort_by(prices, fn item ->
      case {mode, sort_by} do
        # All mode (both sale and rent)
        {"all", "district"} -> item.district
        {"all", "sale_count"} -> item.sale.count
        {"all", "sale_avg"} -> decimal_to_float(item.sale.avg_price)
        {"all", "sale_min"} -> decimal_to_float(item.sale.min_price)
        {"all", "sale_max"} -> decimal_to_float(item.sale.max_price)
        {"all", "sale_sqm"} -> decimal_to_float(item.sale.avg_per_sqm)
        {"all", "rent_count"} -> item.rent.count
        {"all", "rent_avg"} -> decimal_to_float(item.rent.avg_price)
        {"all", "rent_min"} -> decimal_to_float(item.rent.min_price)
        {"all", "rent_max"} -> decimal_to_float(item.rent.max_price)
        {"all", "rent_sqm"} -> decimal_to_float(item.rent.avg_per_sqm)
        
        # Single mode (sprzedaż or wynajem only)
        {_, "district"} -> item.district
        {_, "count"} -> item.stats.count
        {_, "avg"} -> decimal_to_float(item.stats.avg_price)
        {_, "min"} -> decimal_to_float(item.stats.min_price)
        {_, "max"} -> decimal_to_float(item.stats.max_price)
        {_, "sqm"} -> decimal_to_float(item.stats.avg_per_sqm)
        
        _ -> 0
      end
    end, if(sort_dir == :desc, do: :desc, else: :asc))
    
    assign(socket, :filtered_district_prices, sorted)
  end

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(decimal), do: Decimal.to_float(decimal)

  defp get_property_types do
    Repo.all(
      from p in Property,
        where: not is_nil(p.property_type),
        group_by: p.property_type,
        select: {p.property_type, count(p.id)},
        order_by: [desc: count(p.id)]
    )
  end

  # Price sanity filters to exclude misclassified listings
  # Sale: 30k - 50M zł (anything below 30k is likely rent misclassified as sale)
  # Rent: 300 - 100k zł/month
  defp price_range("sprzedaż"), do: {Decimal.new("30000"), Decimal.new("50000000")}
  defp price_range("wynajem"), do: {Decimal.new("300"), Decimal.new("100000")}
  defp price_range(_), do: {Decimal.new("1"), Decimal.new("999999999")}

  defp calculate_filtered_district_prices(property_type, transaction_type, min_area \\ nil, max_area \\ nil, min_rooms \\ nil, max_rooms \\ nil) do
    filters = %{min_area: min_area, max_area: max_area, min_rooms: min_rooms, max_rooms: max_rooms}
    
    # Get districts with this property type (with price sanity filter)
    # Uses the FULL archive including delisted listings
    base_query = from p in Property,
      where: p.property_type == ^property_type and
             not is_nil(p.district) and 
             p.district != "" and
             not is_nil(p.price)
    
    # Add area filters
    base_query = if min_area do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm >= ^min_area)
    else
      base_query
    end
    
    base_query = if max_area do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm <= ^max_area)
    else
      base_query
    end
    
    # Add room filters
    base_query = if min_rooms do
      where(base_query, [p], not is_nil(p.rooms) and p.rooms >= ^min_rooms)
    else
      base_query
    end
    
    base_query = if max_rooms do
      where(base_query, [p], p.rooms <= ^max_rooms)
    else
      base_query
    end
    
    # Add transaction type and price range filter if not "all"
    base_query = case transaction_type do
      "all" -> 
        # For "all" mode, we accept prices valid for either sale OR rent
        # This means: >= 300 (rent min) and <= 50M (sale max)
        where(base_query, [p], p.price >= ^Decimal.new("300") and p.price <= ^Decimal.new("50000000"))
      type -> 
        {min_price, max_price} = price_range(type)
        base_query
        |> where([p], p.transaction_type == ^type)
        |> where([p], p.price >= ^min_price and p.price <= ^max_price)
    end

    districts = Repo.all(
      from p in subquery(base_query),
        group_by: p.district,
        select: p.district,
        order_by: [desc: count(p.id)],
        limit: 25
    )

    Enum.map(districts, fn district ->
      case transaction_type do
        "all" ->
          # Show both sale and rent
          sale = get_district_stats(property_type, district, "sprzedaż", filters)
          rent = get_district_stats(property_type, district, "wynajem", filters)
          %{district: district, sale: sale, rent: rent, mode: :both}
        
        type ->
          # Show only selected type
          stats = get_district_stats(property_type, district, type, filters)
          %{district: district, stats: stats, mode: :single, transaction_type: type}
      end
    end)
    |> Enum.filter(fn item ->
      case item.mode do
        :both -> item.sale.count > 0 or item.rent.count > 0
        :single -> item.stats.count > 0
      end
    end)
  end

  defp get_district_stats(property_type, district, transaction_type, filters \\ %{}) do
    {min_valid, max_valid} = price_range(transaction_type)
    base_query = from(p in Property,
      where: p.property_type == ^property_type and
             p.district == ^district and
             p.transaction_type == ^transaction_type and
             not is_nil(p.price) and
             p.price >= ^min_valid and
             p.price <= ^max_valid)
    
    # Apply area filters
    base_query = if filters[:min_area] do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm >= ^filters[:min_area])
    else
      base_query
    end
    
    base_query = if filters[:max_area] do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm <= ^filters[:max_area])
    else
      base_query
    end
    
    # Apply room filters
    base_query = if filters[:min_rooms] do
      where(base_query, [p], not is_nil(p.rooms) and p.rooms >= ^filters[:min_rooms])
    else
      base_query
    end
    
    base_query = if filters[:max_rooms] do
      where(base_query, [p], p.rooms <= ^filters[:max_rooms])
    else
      base_query
    end
    
    count = Repo.aggregate(base_query, :count, :id)
    avg_price = Repo.aggregate(base_query, :avg, :price)
    min_price = Repo.aggregate(base_query, :min, :price)
    max_price = Repo.aggregate(base_query, :max, :price)

    # For avg_per_sqm, also apply the same filters
    sqm_query = from(p in Property,
      where: p.property_type == ^property_type and
             p.district == ^district and
             p.transaction_type == ^transaction_type and
             not is_nil(p.price) and 
             p.price >= ^min_valid and
             p.price <= ^max_valid and
             not is_nil(p.area_sqm) and
             p.area_sqm > 0)
    
    sqm_query = if filters[:min_area] do
      where(sqm_query, [p], p.area_sqm >= ^filters[:min_area])
    else
      sqm_query
    end
    
    sqm_query = if filters[:max_area] do
      where(sqm_query, [p], p.area_sqm <= ^filters[:max_area])
    else
      sqm_query
    end
    
    sqm_query = if filters[:min_rooms] do
      where(sqm_query, [p], not is_nil(p.rooms) and p.rooms >= ^filters[:min_rooms])
    else
      sqm_query
    end
    
    sqm_query = if filters[:max_rooms] do
      where(sqm_query, [p], p.rooms <= ^filters[:max_rooms])
    else
      sqm_query
    end

    avg_per_sqm = Repo.one(from p in subquery(sqm_query), select: avg(p.price / p.area_sqm))

    %{
      count: count || 0,
      avg_price: avg_price && Decimal.round(avg_price, 0),
      avg_per_sqm: avg_per_sqm && Decimal.round(avg_per_sqm, 0),
      min_price: min_price,
      max_price: max_price
    }
  end

  defp fetch_district_properties(district, property_type, transaction_type, min_area, max_area, min_rooms, max_rooms) do
    # Build base query
    base_query = from p in Property,
      where: p.property_type == ^property_type and
             p.district == ^district and
             not is_nil(p.price),
      order_by: [desc: p.active, desc: p.inserted_at],
      limit: 20,
      select: %{
        id: p.id,
        active: p.active,
        title: p.title,
        price: p.price,
        area_sqm: p.area_sqm,
        rooms: p.rooms,
        transaction_type: p.transaction_type,
        source: p.source,
        url: p.url
      }

    # Add transaction type filter and price range
    base_query = case transaction_type do
      "all" -> 
        where(base_query, [p], p.price >= ^Decimal.new("300") and p.price <= ^Decimal.new("50000000"))
      type -> 
        {min_price, max_price} = price_range(type)
        base_query
        |> where([p], p.transaction_type == ^type)
        |> where([p], p.price >= ^min_price and p.price <= ^max_price)
    end

    # Add area filters
    base_query = if min_area do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm >= ^min_area)
    else
      base_query
    end
    
    base_query = if max_area do
      where(base_query, [p], not is_nil(p.area_sqm) and p.area_sqm <= ^max_area)
    else
      base_query
    end

    # Add room filters
    base_query = if min_rooms do
      where(base_query, [p], not is_nil(p.rooms) and p.rooms >= ^min_rooms)
    else
      base_query
    end
    
    base_query = if max_rooms do
      where(base_query, [p], p.rooms <= ^max_rooms)
    else
      base_query
    end

    Repo.all(base_query)
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

  defp format_price_short(nil), do: "—"

  defp format_price_short(price) do
    value = Decimal.to_float(price)
    
    cond do
      value >= 1_000_000 ->
        "#{Float.round(value / 1_000_000, 1)}M zł"
      value >= 1_000 ->
        "#{Float.round(value / 1_000, 0)}k zł"
      true ->
        "#{trunc(value)} zł"
    end
  end

  defp calc_bar_height(distribution, count) do
    max_count = distribution |> Enum.map(fn {_, c} -> c end) |> Enum.max(fn -> 1 end)
    max_height = 80  # pixels
    min_height = 4   # minimum visible bar
    
    if max_count > 0 do
      height = count / max_count * max_height
      trunc(max(height, min_height))
    else
      min_height
    end
  end
  
  defp format_time_ago(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime)
    
    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end
end
