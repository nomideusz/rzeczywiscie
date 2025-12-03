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
            <p class="text-[10px] opacity-60">Filter by property type and transaction type • Outliers excluded (Sale: 30k-50M zł, Rent: 300-100k zł)</p>
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
  def handle_event("refresh_stats", _params, socket) do
    socket =
      socket
      |> assign(:refreshing, true)
      |> assign(:stats, calculate_stats())
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
        where: p.active == true and not is_nil(p.property_type),
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
    # Uses ALL active data - prices don't change quickly in real estate
    base_query = from p in Property,
      where: p.active == true and 
             p.property_type == ^property_type and
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
      where: p.active == true and 
             p.property_type == ^property_type and
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
      where: p.active == true and 
             p.property_type == ^property_type and
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
      where: p.active == true and 
             p.property_type == ^property_type and
             p.district == ^district and
             not is_nil(p.price),
      order_by: [desc: p.inserted_at],
      limit: 20,
      select: %{
        id: p.id,
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
