defmodule RzeczywiscieWeb.AdminLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  import Ecto.Query
  require Logger
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:backfill_running, false)
      |> assign(:backfill_result, nil)
      |> assign(:olx_scrape_running, false)
      |> assign(:olx_scrape_result, nil)
      |> assign(:otodom_scrape_running, false)
      |> assign(:otodom_scrape_result, nil)
      |> assign(:geocode_running, false)
      |> assign(:geocode_result, nil)
      |> assign(:cleanup_running, false)
      |> assign(:cleanup_result, nil)
      |> assign(:fix_misclassified_running, false)
      |> assign(:fix_misclassified_result, nil)
      |> assign(:misclassified_preview, RealEstate.preview_misclassified_transaction_types())
      |> assign(:dedup_running, false)
      |> assign(:dedup_result, nil)
      |> assign(:export_running, false)
      |> assign(:backfill_rooms_running, false)
      |> assign(:backfill_rooms_result, nil)
      |> assign(:rescrape_running, false)
      |> assign(:rescrape_result, nil)
      |> assign(:rescrape_target, :price)
      |> assign(:rescrape_missing_count, get_missing_count(:price))
      |> assign(:olx_pages, 2)
      |> assign(:otodom_pages, 2)
      |> assign(:db_stats, get_db_stats())

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
            <a href="/stats" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Stats
            </a>
            <a href="/admin" class="px-3 py-2 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100">
              Admin
            </a>
          </nav>

          <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">Admin Panel</h1>
          <p class="text-sm font-bold uppercase tracking-wide opacity-60">Scrapers & Maintenance</p>
        </div>
      </div>

      <!-- Quick Stats -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-2 md:grid-cols-7 divide-x-2 divide-base-content">
            <div class="p-3 text-center">
              <div class="text-xl font-black text-primary"><%= @db_stats.total %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-xl font-black text-success"><%= @db_stats.active %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Active</div>
            </div>
            <div class="p-3 text-center">
              <div class={"text-xl font-black #{if @db_stats.stale > 0, do: "text-warning", else: "text-success"}"}><%= @db_stats.stale %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Stale (48h+)</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-xl font-black text-secondary"><%= @db_stats.geocoded %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Geocoded</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-xl font-black text-warning"><%= @db_stats.missing_type %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">No Type</div>
            </div>
            <div class="p-3 text-center">
              <div class={"text-xl font-black #{if @db_stats.duplicates > 0, do: "text-error", else: "text-success"}"}><%= @db_stats.duplicates %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Duplicates</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-xl font-black text-error"><%= @db_stats.inactive %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Inactive</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Stale Properties Breakdown -->
      <%= if @db_stats.stale > 0 do %>
        <div class="bg-warning/10 border-b-2 border-warning">
          <div class="container mx-auto px-4 py-3">
            <div class="flex flex-wrap items-center gap-4">
              <span class="text-xs font-bold uppercase tracking-wide">⚠️ Stale Properties (not seen in 48h+):</span>
              <%= for {source, count} <- @db_stats.stale_by_source do %>
                <span class="px-2 py-1 text-xs font-bold bg-warning/20 border border-warning">
                  <%= String.upcase(source) %>: <%= count %>
                </span>
              <% end %>
              <span class="text-xs opacity-60">These will become inactive on next cleanup run</span>
            </div>
          </div>
        </div>
      <% end %>

      <div class="container mx-auto px-4 py-6">
        <!-- Scrapers Section -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">Manual Scrapers</h2>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-base-content">
            <!-- OLX Scraper -->
            <div class="p-4">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h3 class="font-bold text-lg">OLX</h3>
                  <p class="text-xs opacity-60">Scrape real estate listings from OLX.pl</p>
                </div>
                <span class="px-2 py-1 text-[10px] font-bold uppercase bg-primary/20 text-primary">Małopolskie</span>
              </div>

              <div class="flex items-center gap-3 mb-4">
                <label class="text-xs font-bold uppercase tracking-wide opacity-60">Pages:</label>
                <div class="flex border-2 border-base-content">
                  <%= for pages <- [1, 2, 3, 5, 10] do %>
                    <button
                      phx-click="set_olx_pages"
                      phx-value-pages={pages}
                      class={"px-3 py-1 text-xs font-bold transition-colors cursor-pointer #{if @olx_pages == pages, do: "bg-base-content text-base-100", else: "hover:bg-base-200"} #{if pages > 1, do: "border-l border-base-content/30"}"}
                    >
                      <%= pages %>
                    </button>
                  <% end %>
                </div>
              </div>

              <%= if @olx_scrape_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @olx_scrape_result %>
                </div>
              <% end %>

              <button
                phx-click="run_olx_scrape"
                disabled={@olx_scrape_running}
                class={"w-full px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @olx_scrape_running, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
              >
                <%= if @olx_scrape_running do %>
                  <span class="inline-block animate-pulse">⏳ Scraping OLX...</span>
                <% else %>
                  Run OLX Scraper (<%= @olx_pages %> pages)
                <% end %>
              </button>
            </div>

            <!-- Otodom Scraper -->
            <div class="p-4">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h3 class="font-bold text-lg">Otodom</h3>
                  <p class="text-xs opacity-60">Scrape real estate listings from Otodom.pl</p>
                </div>
                <span class="px-2 py-1 text-[10px] font-bold uppercase bg-secondary/20 text-secondary">Małopolskie</span>
              </div>

              <div class="flex items-center gap-3 mb-4">
                <label class="text-xs font-bold uppercase tracking-wide opacity-60">Pages:</label>
                <div class="flex border-2 border-base-content">
                  <%= for pages <- [1, 2, 3, 5, 10] do %>
                    <button
                      phx-click="set_otodom_pages"
                      phx-value-pages={pages}
                      class={"px-3 py-1 text-xs font-bold transition-colors cursor-pointer #{if @otodom_pages == pages, do: "bg-base-content text-base-100", else: "hover:bg-base-200"} #{if pages > 1, do: "border-l border-base-content/30"}"}
                    >
                      <%= pages %>
                    </button>
                  <% end %>
                </div>
              </div>

              <%= if @otodom_scrape_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @otodom_scrape_result %>
                </div>
              <% end %>

              <button
                phx-click="run_otodom_scrape"
                disabled={@otodom_scrape_running}
                class={"w-full px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @otodom_scrape_running, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
              >
                <%= if @otodom_scrape_running do %>
                  <span class="inline-block animate-pulse">⏳ Scraping Otodom...</span>
                <% else %>
                  Run Otodom Scraper (<%= @otodom_pages %> pages)
                <% end %>
              </button>
            </div>
          </div>
        </div>

        <!-- Maintenance Tasks -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-6 mb-6">
          <!-- Geocoding -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">📍 Geocoding</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-4">
                Add coordinates to properties without location data. Uses Google Geocoding API.
              </p>

              <%= if @geocode_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @geocode_result %>
                </div>
              <% end %>

              <button
                phx-click="run_geocode"
                disabled={@geocode_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @geocode_running, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
              >
                <%= if @geocode_running, do: "⏳ Running...", else: "Geocode 50 Properties" %>
              </button>
            </div>
          </div>

          <!-- Backfill Types -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🏷️ Backfill Types</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-4">
                Infer missing transaction and property types from URLs, titles, and descriptions.
              </p>

              <%= if @backfill_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @backfill_result %>
                </div>
              <% end %>

              <button
                phx-click="run_backfill"
                disabled={@backfill_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer mb-2 #{if @backfill_running, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
              >
                <%= if @backfill_running, do: "⏳ Running...", else: "Run Backfill" %>
              </button>

              <button
                phx-click="export_missing_types"
                disabled={@export_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-info text-info hover:bg-info hover:text-info-content"}"}
              >
                <%= if @export_running, do: "⏳ Generating...", else: "📥 Download Missing Types CSV" %>
              </button>
            </div>
          </div>

          <!-- Backfill Rooms -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🛏️ Backfill Rooms</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-4">
                Extract room counts from titles for properties missing this data.
              </p>

              <%= if @backfill_rooms_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @backfill_rooms_result %>
                </div>
              <% end %>

              <button
                phx-click="run_backfill_rooms"
                disabled={@backfill_rooms_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @backfill_rooms_running, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}
              >
                <%= if @backfill_rooms_running, do: "⏳ Running...", else: "Run Room Backfill" %>
              </button>
            </div>
          </div>

          <!-- Re-scrape Missing Data -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🔄 Re-scrape Missing Data</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-3">
                Re-fetch property pages to extract missing data (50 at a time).
              </p>

              <!-- Target Selection -->
              <div class="mb-3">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Target:</span>
                <div class="flex gap-1 mt-1">
                  <button
                    phx-click="set_rescrape_target"
                    phx-value-target="price"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @rescrape_target == :price, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    Price
                  </button>
                  <button
                    phx-click="set_rescrape_target"
                    phx-value-target="area"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @rescrape_target == :area, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    Area
                  </button>
                  <button
                    phx-click="set_rescrape_target"
                    phx-value-target="rooms"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @rescrape_target == :rooms, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    Rooms
                  </button>
                  <button
                    phx-click="set_rescrape_target"
                    phx-value-target="district"
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @rescrape_target == :district, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                  >
                    District
                  </button>
                </div>
              </div>

              <!-- Missing Count -->
              <div class="mb-3 px-2 py-1 bg-warning/10 border border-warning/30 text-xs">
                <span class="font-bold text-warning"><%= @rescrape_missing_count %></span>
                <span class="opacity-60">properties missing <%= @rescrape_target %></span>
              </div>

              <%= if @rescrape_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @rescrape_result %>
                </div>
              <% end %>

              <button
                phx-click="run_rescrape"
                disabled={@rescrape_running || @rescrape_missing_count == 0}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @rescrape_running || @rescrape_missing_count == 0, do: "border-base-content/30 opacity-50", else: "border-accent text-accent hover:bg-accent hover:text-accent-content"}"}
              >
                <%= if @rescrape_running, do: "⏳ Re-scraping...", else: "Re-scrape (50)" %>
              </button>
            </div>
          </div>

          <!-- Remove Duplicates -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🔄 Deduplication</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-4">
                Remove duplicate properties with the same URL. Keeps oldest entry.
              </p>

              <%= if @dedup_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @dedup_result %>
                </div>
              <% end %>

              <button
                phx-click="run_dedup"
                disabled={@dedup_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @dedup_running, do: "border-base-content/30 opacity-50", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}
              >
                <%= if @dedup_running, do: "⏳ Running...", else: "Remove Duplicates" %>
              </button>
            </div>
          </div>

          <!-- Cleanup -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🧹 Cleanup</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-4">
                Mark properties as inactive if not seen for 48+ hours (listing removed).
              </p>

              <%= if @cleanup_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @cleanup_result %>
                </div>
              <% end %>

              <button
                phx-click="run_cleanup"
                disabled={@cleanup_running}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @cleanup_running, do: "border-base-content/30 opacity-50", else: "border-error text-error hover:bg-error hover:text-error-content"}"}
              >
                <%= if @cleanup_running, do: "⏳ Running...", else: "Mark Stale Inactive" %>
              </button>
            </div>
          </div>

          <!-- Fix Misclassified -->
          <div class="bg-base-100 border-2 border-base-content">
            <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
              <h3 class="text-sm font-bold uppercase tracking-wide">🔄 Fix Misclassified</h3>
            </div>
            <div class="p-4">
              <p class="text-xs opacity-60 mb-3">
                Fix transaction types based on price: Sale &lt;30k → Rent, Rent &gt;100k → Sale
              </p>

              <div class="mb-3 grid grid-cols-2 gap-2 text-xs">
                <div class="px-2 py-1 bg-info/10 border border-info/30">
                  <span class="font-bold text-info"><%= @misclassified_preview.sales_to_rent %></span>
                  <span class="opacity-60">sales → rent</span>
                </div>
                <div class="px-2 py-1 bg-warning/10 border border-warning/30">
                  <span class="font-bold text-warning"><%= @misclassified_preview.rent_to_sales %></span>
                  <span class="opacity-60">rent → sales</span>
                </div>
              </div>

              <%= if @fix_misclassified_result do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✓ <%= @fix_misclassified_result %>
                </div>
              <% end %>

              <button
                phx-click="fix_misclassified"
                disabled={@fix_misclassified_running || (@misclassified_preview.sales_to_rent == 0 and @misclassified_preview.rent_to_sales == 0)}
                class={"w-full px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @fix_misclassified_running || (@misclassified_preview.sales_to_rent == 0 and @misclassified_preview.rent_to_sales == 0), do: "border-base-content/30 opacity-50", else: "border-primary text-primary hover:bg-primary hover:text-primary-content"}"}
              >
                <%= if @fix_misclassified_running, do: "⏳ Running...", else: "Fix Transaction Types" %>
              </button>
            </div>
          </div>

        </div>

        <!-- Data Quality Exports -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">📊 Data Quality Exports</h2>
          </div>
          <div class="p-4">
            <p class="text-xs opacity-60 mb-4">
              Download CSV reports for properties with missing or incomplete data.
            </p>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-3">
              <button
                phx-click="export_data_quality"
                phx-value-type="missing_price"
                disabled={@export_running}
                class={"px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}
              >
                💰 Missing Price
              </button>
              
              <button
                phx-click="export_data_quality"
                phx-value-type="missing_area"
                disabled={@export_running}
                class={"px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}
              >
                📐 Missing Area
              </button>
              
              <button
                phx-click="export_data_quality"
                phx-value-type="missing_rooms"
                disabled={@export_running}
                class={"px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}
              >
                🛏️ Missing Rooms
              </button>
              
              <button
                phx-click="export_data_quality"
                phx-value-type="missing_coords"
                disabled={@export_running}
                class={"px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-info text-info hover:bg-info hover:text-info-content"}"}
              >
                📍 No Coordinates
              </button>
              
              <button
                phx-click="export_data_quality"
                phx-value-type="all"
                disabled={@export_running}
                class={"px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @export_running, do: "border-base-content/30 opacity-50", else: "border-error text-error hover:bg-error hover:text-error-content"}"}
              >
                ⚠️ All Issues
              </button>
            </div>
          </div>
        </div>

        <!-- Quick Links -->
        <div class="bg-base-100 border-2 border-base-content">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">Quick Links</h2>
          </div>
          <div class="p-4 flex flex-wrap gap-3">
            <a href="/url-inspector" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              🔍 URL Inspector
            </a>
            <a href="/dev/dashboard" target="_blank" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              📊 Phoenix Dashboard
            </a>
            <a href="/dev/mailbox" target="_blank" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              📧 Mailbox
            </a>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("set_olx_pages", %{"pages" => pages}, socket) do
    {:noreply, assign(socket, :olx_pages, String.to_integer(pages))}
  end

  @impl true
  def handle_event("set_otodom_pages", %{"pages" => pages}, socket) do
    {:noreply, assign(socket, :otodom_pages, String.to_integer(pages))}
  end

  @impl true
  def handle_event("run_backfill", _params, socket) do
    Logger.info("Starting backfill from admin panel")

    socket = assign(socket, :backfill_running, true)

    parent = self()
    Task.start(fn ->
      result = run_backfill_task()
      send(parent, {:backfill_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_olx_scrape", _params, socket) do
    pages = socket.assigns.olx_pages
    Logger.info("Starting OLX scrape from admin panel (#{pages} pages)")

    socket = assign(socket, :olx_scrape_running, true)

    parent = self()
    Task.start(fn ->
      result = run_olx_scraper(pages)
      send(parent, {:olx_scrape_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_otodom_scrape", _params, socket) do
    pages = socket.assigns.otodom_pages
    Logger.info("Starting Otodom scrape from admin panel (#{pages} pages)")

    socket = assign(socket, :otodom_scrape_running, true)

    parent = self()
    Task.start(fn ->
      result = run_otodom_scraper(pages)
      send(parent, {:otodom_scrape_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_geocode", _params, socket) do
    Logger.info("Starting geocoding from admin panel")

    socket = assign(socket, :geocode_running, true)

    parent = self()
    Task.start(fn ->
      result = run_geocoding()
      send(parent, {:geocode_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_cleanup", _params, socket) do
    Logger.info("Starting cleanup from admin panel")

    socket = assign(socket, :cleanup_running, true)

    parent = self()
    Task.start(fn ->
      result = run_cleanup()
      send(parent, {:cleanup_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("fix_misclassified", _params, socket) do
    Logger.info("Fixing misclassified transaction types from admin panel")

    socket = assign(socket, :fix_misclassified_running, true)

    parent = self()
    Task.start(fn ->
      {:ok, result} = RealEstate.fix_misclassified_transaction_types()
      send(parent, {:fix_misclassified_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_rescrape_target", %{"target" => target}, socket) do
    target_atom = String.to_existing_atom(target)
    
    socket =
      socket
      |> assign(:rescrape_target, target_atom)
      |> assign(:rescrape_missing_count, get_missing_count(target_atom))
      |> assign(:rescrape_result, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_dedup", _params, socket) do
    Logger.info("Starting deduplication from admin panel")

    socket = assign(socket, :dedup_running, true)

    parent = self()
    Task.start(fn ->
      result = run_deduplication()
      send(parent, {:dedup_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_missing_types", _params, socket) do
    Logger.info("Generating missing types CSV export")

    socket = assign(socket, :export_running, true)

    parent = self()
    Task.start(fn ->
      csv_data = generate_missing_types_csv()
      send(parent, {:export_complete, {csv_data, "missing_types"}})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_data_quality", %{"type" => type}, socket) do
    Logger.info("Generating data quality CSV export: #{type}")

    socket = assign(socket, :export_running, true)

    parent = self()
    Task.start(fn ->
      csv_data = generate_data_quality_csv(type)
      send(parent, {:export_complete, {csv_data, type}})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_backfill_rooms", _params, socket) do
    Logger.info("Starting room count backfill from admin panel")

    socket = assign(socket, :backfill_rooms_running, true)

    parent = self()
    Task.start(fn ->
      result = run_backfill_rooms()
      send(parent, {:backfill_rooms_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_rescrape", _params, socket) do
    target = socket.assigns.rescrape_target
    Logger.info("Starting re-scrape for #{target} from admin panel")

    socket = assign(socket, :rescrape_running, true)

    parent = self()
    Task.start(fn ->
      result = run_rescrape(target)
      send(parent, {:rescrape_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:backfill_complete, result}, socket) do
    socket =
      socket
      |> assign(:backfill_running, false)
      |> assign(:backfill_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:olx_scrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:olx_scrape_running, false)
      |> assign(:olx_scrape_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:otodom_scrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:otodom_scrape_running, false)
      |> assign(:otodom_scrape_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:geocode_complete, result}, socket) do
    socket =
      socket
      |> assign(:geocode_running, false)
      |> assign(:geocode_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cleanup_complete, result}, socket) do
    socket =
      socket
      |> assign(:cleanup_running, false)
      |> assign(:cleanup_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:fix_misclassified_complete, result}, socket) do
    msg = "Fixed #{result.sales_to_rent} sales→rent, #{result.rent_to_sales} rent→sales"
    
    socket =
      socket
      |> assign(:fix_misclassified_running, false)
      |> assign(:fix_misclassified_result, msg)
      |> assign(:misclassified_preview, RealEstate.preview_misclassified_transaction_types())
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end


  @impl true
  def handle_info({:dedup_complete, result}, socket) do
    socket =
      socket
      |> assign(:dedup_running, false)
      |> assign(:dedup_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:export_complete, {csv_data, export_type}}, socket) do
    # Trigger file download via JavaScript
    filename = "#{export_type}_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"
    
    socket =
      socket
      |> assign(:export_running, false)
      |> push_event("download_csv", %{
        filename: filename,
        data: csv_data
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:backfill_rooms_complete, result}, socket) do
    socket =
      socket
      |> assign(:backfill_rooms_running, false)
      |> assign(:backfill_rooms_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rescrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:rescrape_running, false)
      |> assign(:rescrape_result, result)
      |> assign(:rescrape_missing_count, get_missing_count(socket.assigns.rescrape_target))
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  defp get_db_stats do
    total = Repo.aggregate(Property, :count, :id)
    active = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)
    inactive = total - active

    geocoded = Repo.aggregate(
      from(p in Property, where: p.active == true and not is_nil(p.latitude)),
      :count, :id
    )

    missing_type = Repo.aggregate(
      from(p in Property, where: p.active == true and (is_nil(p.transaction_type) or is_nil(p.property_type))),
      :count, :id
    )

    # Count duplicate URLs
    duplicate_query = """
    SELECT COUNT(*) FROM (
      SELECT url FROM properties
      WHERE url IS NOT NULL
      GROUP BY url
      HAVING COUNT(*) > 1
    ) as dupes
    """

    duplicates = case Ecto.Adapters.SQL.query(Repo, duplicate_query, []) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end

    # Count stale properties (active but not seen in 48+ hours - will become inactive)
    cutoff = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)
    
    stale = Repo.aggregate(
      from(p in Property, where: p.active == true and p.last_seen_at < ^cutoff),
      :count, :id
    )

    # Stale breakdown by source
    stale_by_source = from(p in Property,
      where: p.active == true and p.last_seen_at < ^cutoff,
      group_by: p.source,
      select: {p.source, count(p.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})

    %{
      total: total,
      active: active,
      inactive: inactive,
      geocoded: geocoded,
      missing_type: missing_type,
      duplicates: duplicates,
      stale: stale,
      stale_by_source: stale_by_source
    }
  end

  defp get_missing_count(:price) do
    Repo.aggregate(
      from(p in Property, where: p.active == true and is_nil(p.price)),
      :count, :id
    )
  end

  defp get_missing_count(:area) do
    Repo.aggregate(
      from(p in Property, where: p.active == true and is_nil(p.area_sqm)),
      :count, :id
    )
  end

  defp get_missing_count(:rooms) do
    Repo.aggregate(
      from(p in Property, where: p.active == true and is_nil(p.rooms)),
      :count, :id
    )
  end

  defp get_missing_count(:district) do
    Repo.aggregate(
      from(p in Property, where: p.active == true and (is_nil(p.district) or p.district == "")),
      :count, :id
    )
  end

  defp run_backfill_task do
    import Ecto.Query
    alias Rzeczywiscie.Repo
    alias Rzeczywiscie.RealEstate.Property
    alias Rzeczywiscie.RealEstate

    Logger.info("Starting property type backfill...")

    # Get all properties without transaction_type or property_type
    properties =
      from(p in Property,
        where: is_nil(p.transaction_type) or is_nil(p.property_type),
        where: p.active == true
      )
      |> Repo.all()

    Logger.info("Found #{length(properties)} properties to update")

    if length(properties) == 0 do
      Logger.info("✓ No properties need updating!")
      "No properties needed updating (all already have types)"
    else
      # Update each property
      updated =
        Enum.reduce(properties, 0, fn property, count ->
          # Try to infer from URL first, then title, then description
          text_to_check = [
            property.url || "",
            property.title || "",
            property.description || ""
          ] |> Enum.join(" ")

          transaction_type = extract_transaction_type(text_to_check)
          property_type = extract_property_type(text_to_check)

          # DEBUG: Log what we extracted for first few
          if count < 3 do
            Logger.info("DEBUG Property #{property.id}:")
            Logger.info("  Text: #{String.slice(text_to_check, 0, 100)}...")
            Logger.info("  Extracted transaction: #{inspect(transaction_type)}")
            Logger.info("  Extracted property: #{inspect(property_type)}")
            Logger.info("  Current transaction: #{inspect(property.transaction_type)}")
            Logger.info("  Current property: #{inspect(property.property_type)}")
          end

          changes = %{}
          changes = if transaction_type && is_nil(property.transaction_type),
            do: Map.put(changes, :transaction_type, transaction_type), else: changes
          changes = if property_type && is_nil(property.property_type),
            do: Map.put(changes, :property_type, property_type), else: changes

          if map_size(changes) > 0 do
            case RealEstate.update_property(property, changes) do
              {:ok, _updated_property} ->
                Logger.info("✓ Updated property #{property.id}: #{transaction_type} / #{property_type}")
                count + 1

              {:error, changeset} ->
                Logger.error("✗ Failed to update property #{property.id}: #{inspect(changeset.errors)}")
                count
            end
          else
            # Log why no changes were made
            if count < 5 do
              Logger.info("- No changes for property #{property.id}: extracted (#{inspect(transaction_type)}/#{inspect(property_type)}), current (#{inspect(property.transaction_type)}/#{inspect(property.property_type)})")
            end
            count
          end
        end)

      result = "Updated #{updated} out of #{length(properties)} properties"
      Logger.info("✓ Backfill completed: #{result}")
      result
    end
  end

  defp extract_transaction_type(text) do
    # Handle nil or empty text - return sale immediately
    if is_nil(text) or String.trim(text) == "" do
      "sprzedaż"
    else
      extract_transaction_type_from_text(text)
    end
  end

  defp extract_transaction_type_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      # Keywords for sale (sprzedaż)
      String.contains?(text_lower, "sprzedam") -> "sprzedaż"
      String.contains?(text_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "na-sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "na sprzedaz") -> "sprzedaż"
      String.contains?(text_lower, "/sprzedaz/") -> "sprzedaż"
      String.match?(text_lower, ~r/\bsprzedaz\b/) -> "sprzedaż"
      # OLX specific patterns
      String.contains?(text_lower, "/oferta/") && String.contains?(text_lower, "sprzeda") -> "sprzedaż"
      String.contains?(text_lower, "id") && String.contains?(text_lower, ".html") && !String.contains?(text_lower, "wynajem") -> "sprzedaż"
      
      # Keywords for rent (wynajem)
      String.contains?(text_lower, "wynajme") -> "wynajem"
      String.contains?(text_lower, "wynajem") -> "wynajem"
      String.contains?(text_lower, "do-wynajecia") -> "wynajem"
      String.contains?(text_lower, "na-wynajem") -> "wynajem"
      String.contains?(text_lower, "do wynajecia") -> "wynajem"
      String.contains?(text_lower, "na wynajem") -> "wynajem"
      String.contains?(text_lower, "/wynajem/") -> "wynajem"
      String.match?(text_lower, ~r/\bwynajem\b/) -> "wynajem"
      String.contains?(text_lower, "najem") -> "wynajem"
      String.contains?(text_lower, "najm") -> "wynajem"
      # Otodom rent patterns
      String.contains?(text_lower, "rent") -> "wynajem"
      String.contains?(text_lower, "/pl/oferta/") && String.contains?(text_lower, "miesi") -> "wynajem"
      
      # ULTRA-AGGRESSIVE FALLBACK: ANY olx.pl URL without clear rent indicators -> sale
      String.contains?(text_lower, "olx.pl") and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "najem") and
        not String.contains?(text_lower, "/mies") and
        not String.contains?(text_lower, " mc") ->
        "sprzedaż"
      
      # Otodom fallback: if no clear rent indicators, assume sale
      String.contains?(text_lower, "otodom.pl") and
        not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "rent") ->
        "sprzedaż"
      
      # EXTREME FALLBACK: If we still have NO transaction type at all
      # Default to sale (statistics show 80%+ of all real estate listings are sales)
      # Only exclude if we see clear rent indicators
      not String.contains?(text_lower, "wynaj") and
        not String.contains?(text_lower, "najem") and
        not String.contains?(text_lower, "/mies") and
        not String.contains?(text_lower, " mc") and
        not String.contains?(text_lower, "mc.") and
        not String.contains?(text_lower, "rent") ->
        "sprzedaż"

      true -> nil
    end
  end

  defp extract_property_type(text) do
    # Handle nil or empty text - return mieszkanie immediately
    if is_nil(text) or String.trim(text) == "" do
      "mieszkanie"
    else
      extract_property_type_from_text(text)
    end
  end

  defp extract_property_type_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      # Commercial space (lokal użytkowy) - check first as it's most specific
      String.contains?(text_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal uzytkowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-biurowy") -> "lokal użytkowy"
      String.contains?(text_lower, "lokal-handlowy") -> "lokal użytkowy"
      String.contains?(text_lower, "/lokal/") -> "lokal użytkowy"
      String.contains?(text_lower, "biuro") -> "lokal użytkowy"
      String.contains?(text_lower, "sklep") -> "lokal użytkowy"
      String.contains?(text_lower, "magazyn") -> "lokal użytkowy"
      String.contains?(text_lower, "hala") -> "lokal użytkowy"
      String.contains?(text_lower, "uslugowy") -> "lokal użytkowy"
      String.contains?(text_lower, "handel") -> "lokal użytkowy"

      # Apartment (mieszkanie) - most common, check after commercial
      String.contains?(text_lower, "mieszkanie") -> "mieszkanie"
      String.contains?(text_lower, "mieszkania") -> "mieszkanie"
      String.contains?(text_lower, "/mieszkanie/") -> "mieszkanie"
      String.match?(text_lower, ~r/\bmieszkanie\b/) -> "mieszkanie"
      # OLX apartment patterns
      String.contains?(text_lower, "/nieruchomosci/mieszkania/") -> "mieszkanie"
      String.contains?(text_lower, "pokoje") && String.contains?(text_lower, "m2") -> "mieszkanie"
      # Otodom apartment patterns  
      String.contains?(text_lower, "/apartment/") -> "mieszkanie"
      String.contains?(text_lower, "/mieszkania/") -> "mieszkanie"
      String.contains?(text_lower, "/pl/oferta/") && String.match?(text_lower, ~r/\d+\s*m/) -> "mieszkanie"
      # Size indicators often mean apartment
      String.match?(text_lower, ~r/\d{2,3}\s*m2/) && !String.contains?(text_lower, "dom") && !String.contains?(text_lower, "dzialka") -> "mieszkanie"
      String.match?(text_lower, ~r/\d{1}\s*pok/) -> "mieszkanie"
      # Common abbreviations
      String.match?(text_lower, ~r/\bmiesz\b/) -> "mieszkanie"
      String.match?(text_lower, ~r/\bm\d/) -> "mieszkanie"  # M2, M3, M4 etc.
      String.match?(text_lower, ~r/\d+\s*pok/) -> "mieszkanie"

      # House (dom)
      String.contains?(text_lower, "-dom-") -> "dom"
      String.contains?(text_lower, "/dom-") -> "dom"
      String.contains?(text_lower, "/dom/") -> "dom"
      String.contains?(text_lower, "/domy/") -> "dom"
      String.match?(text_lower, ~r/\bdom\b/) -> "dom"
      String.contains?(text_lower, "domek") -> "dom"
      String.contains?(text_lower, "house") -> "dom"
      # Otodom house patterns
      String.contains?(text_lower, "/nieruchomosci/domy/") -> "dom"

      # Room (pokój)
      String.contains?(text_lower, "pokoj") -> "pokój"
      String.contains?(text_lower, "pokój") -> "pokój"
      String.contains?(text_lower, "/stancje-pokoje/") -> "pokój"
      String.contains?(text_lower, "stancja") -> "pokój"
      String.contains?(text_lower, "kawalerka") -> "pokój"
      # Shared accommodation patterns
      String.contains?(text_lower, "wspolny") -> "pokój"
      String.contains?(text_lower, "akademik") -> "pokój"

      # Garage (garaż)
      String.contains?(text_lower, "garaz") -> "garaż"
      String.contains?(text_lower, "garaż") -> "garaż"
      String.contains?(text_lower, "/garaze/") -> "garaż"
      String.contains?(text_lower, "miejsce parkingowe") -> "garaż"
      String.contains?(text_lower, "parking") -> "garaż"
      String.contains?(text_lower, "garage") -> "garaż"

      # Plot/land (działka)
      String.contains?(text_lower, "dzialka") -> "działka"
      String.contains?(text_lower, "działka") -> "działka"
      String.contains?(text_lower, "/dzialki/") -> "działka"
      String.contains?(text_lower, "grunt") -> "działka"
      String.contains?(text_lower, "teren") -> "działka"
      String.contains?(text_lower, "budowlana") -> "działka"
      String.contains?(text_lower, "land") -> "działka"

      # ULTRA-AGGRESSIVE FALLBACK: If we still don't know and it's OLX/Otodom
      # Default to mieszkanie (apartment) - most common property type (~70% of listings)
      # Use word boundaries to avoid matching "dom" in "otodom"
      (String.contains?(text_lower, "olx.pl") or String.contains?(text_lower, "otodom.pl")) and
        not String.match?(text_lower, ~r/\bdom\b/) and
        not String.match?(text_lower, ~r/\bdomy\b/) and
        not String.contains?(text_lower, "/dom/") and
        not String.contains?(text_lower, "/domy/") and
        not String.contains?(text_lower, "dzialka") and
        not String.contains?(text_lower, "działka") and
        not String.contains?(text_lower, "garaz") and
        not String.contains?(text_lower, "garaż") and
        not String.contains?(text_lower, "parking") and
        not String.contains?(text_lower, "grunt") ->
        "mieszkanie"
      
      # EXTREME FALLBACK: If we STILL have no property type
      # Default to mieszkanie (apartment) - most common property type in Poland
      # Use word boundaries to avoid false matches
      not String.match?(text_lower, ~r/\bdom\b/) and
        not String.match?(text_lower, ~r/\bdomy\b/) and
        not String.contains?(text_lower, "/dom/") and
        not String.contains?(text_lower, "/domy/") and
        not String.contains?(text_lower, "house") and
        not String.contains?(text_lower, "dzialka") and
        not String.contains?(text_lower, "działka") and
        not String.contains?(text_lower, "garaz") and
        not String.contains?(text_lower, "garaż") and
        not String.contains?(text_lower, "parking") and
        not String.contains?(text_lower, "grunt") and
        not String.contains?(text_lower, "land") ->
        "mieszkanie"

      true -> nil
    end
  end

  defp run_olx_scraper(pages) do
    alias Rzeczywiscie.Scrapers.OlxScraper

    Logger.info("Running manual OLX scrape (#{pages} pages)...")

    case OlxScraper.scrape(pages: pages, delay: 2000) do
      {:ok, %{total: total, saved: saved}} ->
        "Found #{total} listings, saved #{saved}"

      {:error, reason} ->
        "Failed: #{inspect(reason)}"
    end
  end

  defp run_otodom_scraper(pages) do
    alias Rzeczywiscie.Scrapers.OtodomScraper

    Logger.info("Running manual Otodom scrape (#{pages} pages)...")

    case OtodomScraper.scrape(pages: pages, delay: 3000) do
      {:ok, %{total: total, saved: saved}} ->
        "Found #{total} listings, saved #{saved}"

      {:error, reason} ->
        "Failed: #{inspect(reason)}"
    end
  end

  defp run_geocoding do
    alias Rzeczywiscie.Workers.GeocodingWorker

    Logger.info("Running manual geocoding...")

    case GeocodingWorker.trigger(batch_size: 50, delay_ms: 500) do
      {:ok, _job} ->
        "Geocoding job started for up to 50 properties"

      {:error, reason} ->
        "Failed: #{inspect(reason)}"
    end
  end

  defp run_cleanup do
    alias Rzeczywiscie.RealEstate

    Logger.info("Running cleanup (marking stale properties inactive)...")

    {count, _} = RealEstate.mark_stale_properties_inactive(48)
    "Marked #{count} properties as inactive"
  end

  defp run_rescrape(target) do
    alias Rzeczywiscie.Scrapers.PropertyRescraper

    Logger.info("Running property re-scrape for #{target}...")

    case PropertyRescraper.rescrape_missing(limit: 50, delay: 2000, missing: target) do
      {:ok, %{total: total, updated: updated, failed: failed}} ->
        result = "#{target}: #{total} processed, #{updated} updated, #{failed} failed"
        Logger.info("✓ Re-scrape completed: #{result}")
        result

      {:error, reason} ->
        error = "Failed: #{inspect(reason)}"
        Logger.error("✗ Re-scrape failed: #{error}")
        error
    end
  end

  defp run_deduplication do
    alias Rzeczywiscie.RealEstate

    Logger.info("Running deduplication...")

    case RealEstate.remove_duplicate_properties() do
      {:ok, count} ->
        result = if count == 0 do
          "No duplicates found"
        else
          "Removed #{count} duplicate #{if count == 1, do: "property", else: "properties"}"
        end
        Logger.info("✓ Deduplication completed: #{result}")
        result

      {:error, reason} ->
        error = "Failed: #{inspect(reason)}"
        Logger.error("✗ Deduplication failed: #{error}")
        error
    end
  end

  defp run_backfill_rooms do
    alias Rzeczywiscie.RealEstate

    Logger.info("Starting room count backfill...")

    # Get properties without room count
    properties = from(p in Property,
      where: p.active == true and is_nil(p.rooms),
      select: %{id: p.id, title: p.title, property_type: p.property_type}
    )
    |> Repo.all()

    Logger.info("Found #{length(properties)} properties to update")

    if length(properties) == 0 do
      "No properties need room data"
    else
      updated = Enum.reduce(properties, 0, fn property, count ->
        rooms = extract_rooms_from_title(property.title)

        # DEBUG: Log first few
        if count < 5 do
          Logger.info("DEBUG Room Extract Property #{property.id}:")
          Logger.info("  Title: #{property.title}")
          Logger.info("  Extracted rooms: #{inspect(rooms)}")
        end

        if rooms do
          case RealEstate.update_property(
            Repo.get(Property, property.id),
            %{rooms: rooms}
          ) do
            {:ok, _} ->
              Logger.info("✓ Updated property #{property.id}: #{rooms} rooms")
              count + 1
            {:error, _} ->
              count
          end
        else
          count
        end
      end)

      result = "Updated #{updated} out of #{length(properties)} properties"
      Logger.info("✓ Room backfill completed: #{result}")
      result
    end
  end

  defp extract_rooms_from_title(title) do
    if is_nil(title) do
      nil
    else
      text_lower = String.downcase(title)
      extract_rooms_from_title_text(text_lower)
    end
  end

  defp extract_rooms_from_title_text(text_lower) do
    cond do
      # "3-pokojowe", "2 pokojowe", "czteropokojowe"
      match = Regex.run(~r/(\d+)[\s-]*pokojow/, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "3-pok", "2 pok" (WITHOUT "oj" after - use negative lookahead)
      match = Regex.run(~r/(\d+)[\s-]*pok(?!oj)/, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "3 pokoje", "2-pokoje", "4 pokoje"
      match = Regex.run(~r/(\d+)[\s-]*pokoje/, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "3 pok.", "2-pok."
      match = Regex.run(~r/(\d+)[\s-]*pok\./, text_lower) ->
        [_, num] = match
        String.to_integer(num)
      
      # "2 osobne pokoje", "3 osobne pokoje"  
      match = Regex.run(~r/(\d+)\s+osobne\s+pokoje/, text_lower) ->
        [_, num] = match
        String.to_integer(num)

      # Polish word numbers
      String.contains?(text_lower, "jednopokojow") -> 1
      String.contains?(text_lower, "dwupokojow") -> 2
      String.contains?(text_lower, "trzypokojow") -> 3
      String.contains?(text_lower, "czteropokojow") -> 4
      String.contains?(text_lower, "pieciopokojow") -> 5
      String.contains?(text_lower, "szesciopokojow") -> 6

      # Single room indicators
      String.contains?(text_lower, "kawalerka") -> 1
      String.contains?(text_lower, "studio") -> 1
      String.contains?(text_lower, "garsoniera") -> 1
      String.contains?(text_lower, "jednoosobowy") -> 1
      String.match?(text_lower, ~r/1[\s-]*osobow/) -> 1
      
      # Generic "pokój" without number might be 1 room
      String.contains?(text_lower, "pokoj") && !String.match?(text_lower, ~r/\d+/) -> 1

      true -> nil
    end
  end

  defp generate_missing_types_csv do
    Logger.info("Generating CSV export of properties missing types...")

    # Query for active properties missing types
    properties = from(p in Property,
      where: p.active == true and (is_nil(p.transaction_type) or is_nil(p.property_type)),
      order_by: [desc: p.inserted_at],
      select: %{
        id: p.id,
        source: p.source,
        external_id: p.external_id,
        title: p.title,
        url: p.url,
        transaction_type: p.transaction_type,
        property_type: p.property_type,
        city: p.city,
        price: p.price,
        inserted_at: p.inserted_at
      }
    )
    |> Repo.all()

    Logger.info("Found #{length(properties)} properties to export")

    # Generate CSV
    header = "ID,Source,External ID,Transaction Type,Property Type,City,Price,Title,URL,Inserted At\n"
    
    rows = Enum.map(properties, fn p ->
      [
        p.id,
        p.source,
        escape_csv(p.external_id),
        escape_csv(p.transaction_type || ""),
        escape_csv(p.property_type || ""),
        escape_csv(p.city || ""),
        p.price || "",
        escape_csv(p.title),
        escape_csv(p.url),
        p.inserted_at
      ]
      |> Enum.join(",")
    end)
    |> Enum.join("\n")
    
    Logger.info("✓ CSV generated successfully")
    header <> rows <> "\n"
  end

  defp generate_data_quality_csv(type) do
    Logger.info("Generating #{type} CSV export...")

    properties = case type do
      "missing_price" ->
        from(p in Property,
          where: p.active == true and is_nil(p.price),
          order_by: [desc: p.inserted_at]
        ) |> Repo.all()
      
      "missing_area" ->
        from(p in Property,
          where: p.active == true and is_nil(p.area_sqm),
          order_by: [desc: p.inserted_at]
        ) |> Repo.all()
      
      "missing_rooms" ->
        from(p in Property,
          where: p.active == true and is_nil(p.rooms),
          order_by: [desc: p.inserted_at]
        ) |> Repo.all()
      
      "missing_coords" ->
        from(p in Property,
          where: p.active == true and (is_nil(p.latitude) or is_nil(p.longitude)),
          order_by: [desc: p.inserted_at]
        ) |> Repo.all()
      
      "all" ->
        from(p in Property,
          where: p.active == true and (
            is_nil(p.price) or 
            is_nil(p.area_sqm) or 
            is_nil(p.rooms) or 
            is_nil(p.latitude) or 
            is_nil(p.longitude) or
            is_nil(p.transaction_type) or
            is_nil(p.property_type)
          ),
          order_by: [desc: p.inserted_at]
        ) |> Repo.all()
      
      _ -> []
    end

    Logger.info("Found #{length(properties)} properties with #{type}")

    # Generate CSV
    header = "ID,Source,External ID,Price,Price/m²,Area (m²),Rooms,City,Coords,Transaction Type,Property Type,Title,URL,Inserted At\n"
    
    rows = Enum.map(properties, fn p ->
      price_per_sqm = if p.price && p.area_sqm && Decimal.compare(p.area_sqm, 0) == :gt do
        Decimal.div(p.price, p.area_sqm) |> Decimal.round(2) |> Decimal.to_string()
      else
        ""
      end
      
      coords = if p.latitude && p.longitude, do: "✓", else: "✗"
      
      [
        p.id,
        p.source,
        escape_csv(p.external_id),
        p.price || "",
        price_per_sqm,
        p.area_sqm || "",
        p.rooms || "",
        escape_csv(p.city || ""),
        coords,
        escape_csv(p.transaction_type || ""),
        escape_csv(p.property_type || ""),
        escape_csv(p.title),
        escape_csv(p.url),
        p.inserted_at
      ]
      |> Enum.join(",")
    end)
    |> Enum.join("\n")
    
    Logger.info("✓ CSV generated successfully")
    header <> rows <> "\n"
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(value) when is_binary(value) do
    # Escape quotes and wrap in quotes if contains comma, quote, or newline
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      escaped = String.replace(value, "\"", "\"\"")
      "\"#{escaped}\""
    else
      value
    end
  end
  defp escape_csv(value), do: to_string(value)
end
