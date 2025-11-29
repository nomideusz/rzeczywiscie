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
    # Get available property types for filter
    property_types = get_property_types()
    
    socket =
      socket
      |> assign(:stats, calculate_stats())
      |> assign(:refreshing, false)
      |> assign(:property_types, property_types)
      |> assign(:selected_property_type, "mieszkanie")
      |> assign(:selected_transaction_type, "all")
      |> assign(:sort_by, "sale_count")
      |> assign(:sort_dir, :desc)
      |> assign(:filtered_district_prices, calculate_filtered_district_prices("mieszkanie", "all"))
      |> sort_filtered_prices()

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
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Stale (48h+)</div>
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
              <span class="text-xs opacity-60">Not seen in 48h+ — will become inactive</span>
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

        <!-- Prices by Property Type -->
        <%= if length(@stats.price_by_property_type) > 0 do %>
          <div class="bg-base-100 border-2 border-base-content mb-6">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">🏘️ Prices by Property Type</h2>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30">
                  <tr>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">Type</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-info" colspan="3">Sprzedaż</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-warning" colspan="3">Wynajem</th>
                  </tr>
                  <tr class="bg-base-100">
                    <th class="px-4 py-1"></th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Count</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg Price</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg/m²</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Count</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg Price</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg/m²</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/20">
                  <%= for item <- @stats.price_by_property_type do %>
                    <tr class="hover:bg-base-200/50">
                      <td class="px-4 py-2 font-bold capitalize"><%= item.type %></td>
                      <td class="px-2 py-2 text-center text-info"><%= item.sale.count %></td>
                      <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.sale.avg_price) %></td>
                      <td class="px-2 py-2 text-center text-xs"><%= format_price_short(item.sale.avg_per_sqm) %></td>
                      <td class="px-2 py-2 text-center text-warning"><%= item.rent.count %></td>
                      <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.rent.avg_price) %></td>
                      <td class="px-2 py-2 text-center text-xs"><%= format_price_short(item.rent.avg_per_sqm) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>

        <!-- Prices by District -->
        <%= if length(@stats.price_by_district) > 0 do %>
          <div class="bg-base-100 border-2 border-base-content mb-6">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h2 class="text-sm font-bold uppercase tracking-wide">📍 Prices by District (Dzielnice)</h2>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-base-200 border-b border-base-content/30">
                  <tr>
                    <th class="px-4 py-2 text-left text-[10px] font-bold uppercase tracking-wide">District</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-info" colspan="3">Sprzedaż</th>
                    <th class="px-4 py-2 text-center text-[10px] font-bold uppercase tracking-wide text-warning" colspan="3">Wynajem</th>
                  </tr>
                  <tr class="bg-base-100">
                    <th class="px-4 py-1"></th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Count</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg Price</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg/m²</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Count</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg Price</th>
                    <th class="px-2 py-1 text-[9px] font-bold uppercase opacity-60">Avg/m²</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-content/20">
                  <%= for item <- @stats.price_by_district do %>
                    <tr class="hover:bg-base-200/50">
                      <td class="px-4 py-2 font-bold"><%= item.district %></td>
                      <td class="px-2 py-2 text-center text-info"><%= item.sale.count %></td>
                      <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.sale.avg_price) %></td>
                      <td class="px-2 py-2 text-center text-xs"><%= format_price_short(item.sale.avg_per_sqm) %></td>
                      <td class="px-2 py-2 text-center text-warning"><%= item.rent.count %></td>
                      <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.rent.avg_price) %></td>
                      <td class="px-2 py-2 text-center text-xs"><%= format_price_short(item.rent.avg_per_sqm) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>

        <!-- Interactive Price Explorer -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-3 border-b-2 border-base-content bg-gradient-to-r from-primary/20 to-secondary/20">
            <h2 class="text-sm font-bold uppercase tracking-wide">🔍 Price Explorer by District</h2>
            <p class="text-[10px] opacity-60">Filter by property type and transaction type</p>
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
                      <tr class="hover:bg-base-200/50">
                        <td class="px-3 py-2 font-bold text-sm"><%= item.district %></td>
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
                    <% else %>
                      <tr class="hover:bg-base-200/50">
                        <td class="px-4 py-2 font-bold"><%= item.district %></td>
                        <td class={"px-2 py-2 text-center #{if item.transaction_type == "sprzedaż", do: "text-info", else: "text-warning"}"}><%= item.stats.count %></td>
                        <td class="px-2 py-2 text-center font-bold"><%= format_price_short(item.stats.avg_price) %></td>
                        <td class="px-2 py-2 text-center text-success"><%= format_price_short(item.stats.min_price) %></td>
                        <td class="px-2 py-2 text-center text-error"><%= format_price_short(item.stats.max_price) %></td>
                        <td class="px-2 py-2 text-center opacity-70"><%= format_price_short(item.stats.avg_per_sqm) %></td>
                      </tr>
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
      |> assign(:refreshing, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_property_type", %{"type" => type}, socket) do
    filtered = calculate_filtered_district_prices(type, socket.assigns.selected_transaction_type)
    
    socket =
      socket
      |> assign(:selected_property_type, type)
      |> assign(:filtered_district_prices, filtered)
      |> sort_filtered_prices()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_transaction_type", %{"type" => type}, socket) do
    filtered = calculate_filtered_district_prices(socket.assigns.selected_property_type, type)
    
    # Reset sort to appropriate default when switching transaction type
    default_sort = if type == "all", do: "sale_count", else: "count"
    
    socket =
      socket
      |> assign(:selected_transaction_type, type)
      |> assign(:filtered_district_prices, filtered)
      |> assign(:sort_by, default_sort)
      |> sort_filtered_prices()

    {:noreply, socket}
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

    # Price statistics for sale properties
    sale_price_stats = calculate_price_stats("sprzedaż")
    rent_price_stats = calculate_price_stats("wynajem")

    # Price statistics by property type
    price_by_property_type = calculate_prices_by_property_type()
    
    # Price statistics by district (top 10 districts with most properties)
    price_by_district = calculate_prices_by_district()
    
    # Apartment prices by district (mieszkanie only)
    apartment_prices_by_district = calculate_apartment_prices_by_district()

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

    # Stale properties (not seen in 48+ hours)
    cutoff = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)
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
      by_transaction_type: by_transaction_type,
      by_property_type: by_property_type,
      top_cities: top_cities,
      with_price: with_price,
      with_area: with_area,
      with_rooms: with_rooms,
      complete_data: complete_data,
      recent_activity: recent_activity,
      price_drops: price_drops,
      sale_price_stats: sale_price_stats,
      rent_price_stats: rent_price_stats,
      price_by_property_type: price_by_property_type,
      price_by_district: price_by_district,
      apartment_prices_by_district: apartment_prices_by_district,
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
    query = from p in Property,
      where: p.active == true and 
             p.transaction_type == ^transaction_type and 
             not is_nil(p.price) and 
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

  defp calculate_prices_by_property_type do
    # Get all property types that actually exist in the database
    property_types = Repo.all(
      from p in Property,
        where: p.active == true and not is_nil(p.property_type),
        group_by: p.property_type,
        select: p.property_type,
        order_by: [desc: count(p.id)]
    )
    
    Enum.map(property_types, fn prop_type ->
      # Sale stats - count all with price, avg_per_sqm only for those with area
      sale_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      sale_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :avg, :price
      )

      sale_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      # Rent stats
      rent_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      rent_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :avg, :price
      )

      rent_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.property_type == ^prop_type and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      %{
        type: prop_type,
        sale: %{
          count: sale_count || 0,
          avg_price: sale_avg_price && Decimal.round(sale_avg_price, 0),
          avg_per_sqm: sale_avg_per_sqm && Decimal.round(sale_avg_per_sqm, 0)
        },
        rent: %{
          count: rent_count || 0,
          avg_price: rent_avg_price && Decimal.round(rent_avg_price, 0),
          avg_per_sqm: rent_avg_per_sqm && Decimal.round(rent_avg_per_sqm, 0)
        }
      }
    end)
    |> Enum.filter(fn x -> x.sale.count > 0 or x.rent.count > 0 end)
  end

  defp calculate_prices_by_district do
    # Get top 15 districts by number of active properties
    top_districts = Repo.all(
      from p in Property,
        where: p.active == true and not is_nil(p.district) and p.district != "",
        group_by: p.district,
        select: p.district,
        order_by: [desc: count(p.id)],
        limit: 15
    )

    Enum.map(top_districts, fn district ->
      # Sale stats - count all with price, avg_per_sqm only for those with area
      sale_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      sale_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :avg, :price
      )

      sale_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      # Rent stats
      rent_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      rent_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :avg, :price
      )

      rent_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      %{
        district: district,
        sale: %{
          count: sale_count || 0,
          avg_price: sale_avg_price && Decimal.round(sale_avg_price, 0),
          avg_per_sqm: sale_avg_per_sqm && Decimal.round(sale_avg_per_sqm, 0)
        },
        rent: %{
          count: rent_count || 0,
          avg_price: rent_avg_price && Decimal.round(rent_avg_price, 0),
          avg_per_sqm: rent_avg_per_sqm && Decimal.round(rent_avg_per_sqm, 0)
        }
      }
    end)
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

  defp calculate_filtered_district_prices(property_type, transaction_type) do
    # Get districts with this property type
    base_query = from p in Property,
      where: p.active == true and 
             p.property_type == ^property_type and
             not is_nil(p.district) and 
             p.district != "" and
             not is_nil(p.price)
    
    # Add transaction type filter if not "all"
    base_query = case transaction_type do
      "all" -> base_query
      type -> where(base_query, [p], p.transaction_type == ^type)
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
          sale = get_district_stats(property_type, district, "sprzedaż")
          rent = get_district_stats(property_type, district, "wynajem")
          %{district: district, sale: sale, rent: rent, mode: :both}
        
        type ->
          # Show only selected type
          stats = get_district_stats(property_type, district, type)
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

  defp get_district_stats(property_type, district, transaction_type) do
    count = Repo.aggregate(
      from(p in Property,
        where: p.active == true and 
               p.property_type == ^property_type and
               p.district == ^district and
               p.transaction_type == ^transaction_type and
               not is_nil(p.price)),
      :count, :id
    )
    
    avg_price = Repo.aggregate(
      from(p in Property,
        where: p.active == true and 
               p.property_type == ^property_type and
               p.district == ^district and
               p.transaction_type == ^transaction_type and
               not is_nil(p.price)),
      :avg, :price
    )

    avg_per_sqm = Repo.one(
      from p in Property,
        where: p.active == true and 
               p.property_type == ^property_type and
               p.district == ^district and
               p.transaction_type == ^transaction_type and
               not is_nil(p.price) and 
               not is_nil(p.area_sqm) and
               p.area_sqm > 0,
        select: avg(p.price / p.area_sqm)
    )

    min_price = Repo.aggregate(
      from(p in Property,
        where: p.active == true and 
               p.property_type == ^property_type and
               p.district == ^district and
               p.transaction_type == ^transaction_type and
               not is_nil(p.price)),
      :min, :price
    )

    max_price = Repo.aggregate(
      from(p in Property,
        where: p.active == true and 
               p.property_type == ^property_type and
               p.district == ^district and
               p.transaction_type == ^transaction_type and
               not is_nil(p.price)),
      :max, :price
    )

    %{
      count: count || 0,
      avg_price: avg_price && Decimal.round(avg_price, 0),
      avg_per_sqm: avg_per_sqm && Decimal.round(avg_per_sqm, 0),
      min_price: min_price,
      max_price: max_price
    }
  end

  defp calculate_apartment_prices_by_district do
    # Get districts with apartments, ordered by count
    districts_with_apartments = Repo.all(
      from p in Property,
        where: p.active == true and 
               p.property_type == "mieszkanie" and
               not is_nil(p.district) and 
               p.district != "" and
               not is_nil(p.price),
        group_by: p.district,
        select: p.district,
        order_by: [desc: count(p.id)],
        limit: 20
    )

    Enum.map(districts_with_apartments, fn district ->
      # Sale stats for apartments in this district
      sale_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      sale_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :avg, :price
      )

      sale_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      sale_min_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :min, :price
      )

      sale_max_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "sprzedaż" and
                 not is_nil(p.price)),
        :max, :price
      )

      # Rent stats for apartments in this district
      rent_count = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :count, :id
      )
      
      rent_avg_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :avg, :price
      )

      rent_avg_per_sqm = Repo.one(
        from p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price) and 
                 not is_nil(p.area_sqm) and
                 p.area_sqm > 0,
          select: avg(p.price / p.area_sqm)
      )

      rent_min_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :min, :price
      )

      rent_max_price = Repo.aggregate(
        from(p in Property,
          where: p.active == true and 
                 p.property_type == "mieszkanie" and
                 p.district == ^district and
                 p.transaction_type == "wynajem" and
                 not is_nil(p.price)),
        :max, :price
      )

      %{
        district: district,
        sale: %{
          count: sale_count || 0,
          avg_price: sale_avg_price && Decimal.round(sale_avg_price, 0),
          avg_per_sqm: sale_avg_per_sqm && Decimal.round(sale_avg_per_sqm, 0),
          min_price: sale_min_price,
          max_price: sale_max_price
        },
        rent: %{
          count: rent_count || 0,
          avg_price: rent_avg_price && Decimal.round(rent_avg_price, 0),
          avg_per_sqm: rent_avg_per_sqm && Decimal.round(rent_avg_per_sqm, 0),
          min_price: rent_min_price,
          max_price: rent_max_price
        }
      }
    end)
    |> Enum.filter(fn x -> x.sale.count > 0 or x.rent.count > 0 end)
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
end
