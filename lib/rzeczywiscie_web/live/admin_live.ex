defmodule RzeczywiscieWeb.AdminLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  import Ecto.Query
  require Logger
  alias Rzeczywiscie.Repo
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
      |> assign(:dedup_running, false)
      |> assign(:dedup_result, nil)
      |> assign(:export_running, false)
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
          <div class="grid grid-cols-2 md:grid-cols-6 divide-x-2 divide-base-content">
            <div class="p-3 text-center">
              <div class="text-xl font-black text-primary"><%= @db_stats.total %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-xl font-black text-success"><%= @db_stats.active %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Active</div>
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
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-6">
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
      send(parent, {:export_complete, csv_data})
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
  def handle_info({:dedup_complete, result}, socket) do
    socket =
      socket
      |> assign(:dedup_running, false)
      |> assign(:dedup_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:export_complete, csv_data}, socket) do
    # Trigger file download via JavaScript
    socket =
      socket
      |> assign(:export_running, false)
      |> push_event("download_csv", %{
        filename: "missing_types_#{DateTime.utc_now() |> DateTime.to_unix()}.csv",
        data: csv_data
      })

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

    %{
      total: total,
      active: active,
      inactive: inactive,
      geocoded: geocoded,
      missing_type: missing_type,
      duplicates: duplicates
    }
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
            Logger.info("- No type info found for property #{property.id}")
            count
          end
        end)

      result = "Updated #{updated} out of #{length(properties)} properties"
      Logger.info("✓ Backfill completed: #{result}")
      result
    end
  end

  defp extract_transaction_type(text) do
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

      true -> nil
    end
  end

  defp extract_property_type(text) do
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
      # Default to mieszkanie (apartment) - most common property type
      (String.contains?(text_lower, "olx.pl") or String.contains?(text_lower, "otodom.pl")) and
        (String.contains?(text_lower, "nieruchomosci") or String.contains?(text_lower, "/oferta/") or String.contains?(text_lower, "/pl/oferta/")) and
        not String.contains?(text_lower, "dom") and
        not String.contains?(text_lower, "dzialka") and
        not String.contains?(text_lower, "garaz") and
        not String.contains?(text_lower, "parking") ->
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
