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
    db_stats = get_db_stats()
    
    socket =
      socket
      # Scrapers
      |> assign(:scrape_running, nil)  # :olx, :otodom, or nil
      |> assign(:scrape_result, nil)
      # Data Enrichment
      |> assign(:enrichment_running, nil)  # :geocode, :rescrape, :backfill_types, :backfill_rooms, or nil
      |> assign(:enrichment_result, nil)
      |> assign(:rescrape_target, :district)
      |> assign(:rescrape_missing_count, get_missing_count(:district))
      # Data Cleanup
      |> assign(:cleanup_running, nil)  # :stale, :duplicates, :misclassified, or nil
      |> assign(:cleanup_result, nil)
      |> assign(:misclassified_preview, RealEstate.preview_misclassified_transaction_types())
      # Stats
      |> assign(:db_stats, db_stats)

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
          <nav class="flex gap-1 mb-4">
            <a href="/real-estate" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">Properties</a>
            <a href="/favorites" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">Favorites</a>
            <a href="/stats" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">Stats</a>
            <a href="/admin" class="px-3 py-2 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100">Admin</a>
          </nav>
          <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">Admin Panel</h1>
        </div>
      </div>

      <!-- Quick Stats -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-3 md:grid-cols-6 divide-x divide-base-content/30">
            <div class="p-3 text-center">
              <div class="text-2xl font-black text-primary"><%= @db_stats.active %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Active</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-2xl font-black"><%= @db_stats.olx_count %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">OLX</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-2xl font-black"><%= @db_stats.otodom_count %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Otodom</div>
            </div>
            <div class="p-3 text-center">
              <div class="text-2xl font-black text-secondary"><%= @db_stats.geocoded %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Geocoded</div>
            </div>
            <div class="p-3 text-center">
              <div class={"text-2xl font-black #{if @db_stats.stale > 0, do: "text-warning", else: "text-success"}"}><%= @db_stats.stale %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Stale</div>
            </div>
            <div class="p-3 text-center">
              <div class={"text-2xl font-black #{if @db_stats.duplicates > 0, do: "text-error", else: "text-success"}"}><%= @db_stats.duplicates %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Dupes</div>
            </div>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-6">
        <!-- Scrapers -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">🌐 Scrapers</h2>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-base-content/30">
            <div class="p-4">
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-bold">OLX.pl</h3>
                <span class="px-2 py-1 text-[10px] font-bold uppercase bg-primary/20 text-primary">Małopolskie</span>
              </div>
              <%= if @scrape_result && @scrape_running == nil do %>
                <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">✓ <%= @scrape_result %></div>
              <% end %>
              <button phx-click="run_scrape" phx-value-source="olx" disabled={@scrape_running != nil}
                class={"w-full px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @scrape_running != nil, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}>
                <%= if @scrape_running == :olx, do: "⏳ Scraping...", else: "Scrape OLX (3 pages)" %>
              </button>
            </div>
            <div class="p-4">
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-bold">Otodom.pl</h3>
                <span class="px-2 py-1 text-[10px] font-bold uppercase bg-secondary/20 text-secondary">Małopolskie</span>
              </div>
              <button phx-click="run_scrape" phx-value-source="otodom" disabled={@scrape_running != nil}
                class={"w-full px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @scrape_running != nil, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}>
                <%= if @scrape_running == :otodom, do: "⏳ Scraping...", else: "Scrape Otodom (3 pages)" %>
              </button>
            </div>
          </div>
        </div>

        <!-- Data Enrichment -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">✨ Data Enrichment</h2>
          </div>
          <div class="p-4">
            <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <!-- Re-scrape Target Selection -->
              <div class="col-span-2 md:col-span-4 flex flex-wrap items-center gap-2 pb-3 border-b border-base-content/10">
                <span class="text-xs font-bold uppercase tracking-wide opacity-60">Re-scrape target:</span>
                <%= for target <- [:price, :area, :rooms, :district] do %>
                  <button phx-click="set_rescrape_target" phx-value-target={target}
                    class={"px-3 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @rescrape_target == target, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}>
                    <%= target %> (<%= get_missing_count(target) %>)
                  </button>
                <% end %>
              </div>
            </div>
            
            <%= if @enrichment_result do %>
              <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">✓ <%= @enrichment_result %></div>
            <% end %>

            <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
              <button phx-click="run_enrichment" phx-value-type="rescrape" disabled={@enrichment_running != nil || @rescrape_missing_count == 0}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @enrichment_running != nil || @rescrape_missing_count == 0, do: "border-base-content/30 opacity-50", else: "border-accent text-accent hover:bg-accent hover:text-accent-content"}"}>
                <%= if @enrichment_running == :rescrape, do: "⏳ Running...", else: "🔄 Re-scrape (50)" %>
              </button>
              <button phx-click="run_enrichment" phx-value-type="geocode" disabled={@enrichment_running != nil}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @enrichment_running != nil, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}>
                <%= if @enrichment_running == :geocode, do: "⏳ Running...", else: "📍 Geocode (50)" %>
              </button>
              <button phx-click="run_enrichment" phx-value-type="backfill_types" disabled={@enrichment_running != nil}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @enrichment_running != nil, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}>
                <%= if @enrichment_running == :backfill_types, do: "⏳ Running...", else: "🏷️ Backfill Types" %>
              </button>
              <button phx-click="run_enrichment" phx-value-type="backfill_rooms" disabled={@enrichment_running != nil}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @enrichment_running != nil, do: "border-base-content/30 opacity-50", else: "border-base-content hover:bg-base-content hover:text-base-100"}"}>
                <%= if @enrichment_running == :backfill_rooms, do: "⏳ Running...", else: "🛏️ Backfill Rooms" %>
              </button>
            </div>
          </div>
        </div>

        <!-- Data Cleanup -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">🧹 Data Cleanup</h2>
          </div>
          <div class="p-4">
            <!-- Misclassified preview -->
            <%= if @misclassified_preview.sales_to_rent > 0 or @misclassified_preview.rent_to_sales > 0 do %>
              <div class="mb-3 flex gap-2 text-xs">
                <span class="px-2 py-1 bg-info/10 border border-info/30">
                  <span class="font-bold text-info"><%= @misclassified_preview.sales_to_rent %></span> sales→rent
                </span>
                <span class="px-2 py-1 bg-warning/10 border border-warning/30">
                  <span class="font-bold text-warning"><%= @misclassified_preview.rent_to_sales %></span> rent→sales
                </span>
              </div>
            <% end %>

            <%= if @cleanup_result do %>
              <div class="mb-3 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">✓ <%= @cleanup_result %></div>
            <% end %>

            <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
              <button phx-click="run_cleanup_task" phx-value-type="stale" disabled={@cleanup_running != nil}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @cleanup_running != nil, do: "border-base-content/30 opacity-50", else: "border-error text-error hover:bg-error hover:text-error-content"}"}>
                <%= if @cleanup_running == :stale, do: "⏳ Running...", else: "🗑️ Mark Stale Inactive" %>
              </button>
              <button phx-click="run_cleanup_task" phx-value-type="duplicates" disabled={@cleanup_running != nil || @db_stats.duplicates == 0}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @cleanup_running != nil || @db_stats.duplicates == 0, do: "border-base-content/30 opacity-50", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}>
                <%= if @cleanup_running == :duplicates, do: "⏳ Running...", else: "🔄 Remove Duplicates" %>
              </button>
              <button phx-click="run_cleanup_task" phx-value-type="misclassified" disabled={@cleanup_running != nil || (@misclassified_preview.sales_to_rent == 0 and @misclassified_preview.rent_to_sales == 0)}
                class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @cleanup_running != nil || (@misclassified_preview.sales_to_rent == 0 and @misclassified_preview.rent_to_sales == 0), do: "border-base-content/30 opacity-50", else: "border-primary text-primary hover:bg-primary hover:text-primary-content"}"}>
                <%= if @cleanup_running == :misclassified, do: "⏳ Running...", else: "🔧 Fix Misclassified" %>
              </button>
            </div>
          </div>
        </div>

        <!-- Quick Links -->
        <div class="bg-base-100 border-2 border-base-content">
          <div class="px-4 py-2 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">🔗 Quick Links</h2>
          </div>
          <div class="p-4 flex flex-wrap gap-3">
            <a href="/url-inspector" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">🔍 URL Inspector</a>
            <a href="/dev/dashboard" target="_blank" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">📊 Phoenix Dashboard</a>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("run_scrape", %{"source" => source}, socket) do
    source_atom = String.to_existing_atom(source)
    Logger.info("Starting #{source} scrape from admin panel")
    
    socket = assign(socket, :scrape_running, source_atom)
    
    parent = self()
    Task.start(fn ->
      result = run_scraper(source_atom)
      send(parent, {:scrape_complete, result})
    end)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("run_enrichment", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)
    Logger.info("Starting #{type} enrichment from admin panel")
    
    socket = assign(socket, :enrichment_running, type_atom)
    
    parent = self()
    target = socket.assigns.rescrape_target
    Task.start(fn ->
      result = run_enrichment_task(type_atom, target)
      send(parent, {:enrichment_complete, result})
    end)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("run_cleanup_task", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)
    Logger.info("Starting #{type} cleanup from admin panel")
    
    socket = assign(socket, :cleanup_running, type_atom)
    
    parent = self()
    Task.start(fn ->
      result = run_cleanup_task(type_atom)
      send(parent, {:cleanup_complete, result})
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

    {:noreply, socket}
  end

  @impl true
  def handle_info({:scrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:scrape_running, nil)
      |> assign(:scrape_result, result)
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:enrichment_complete, result}, socket) do
    socket =
      socket
      |> assign(:enrichment_running, nil)
      |> assign(:enrichment_result, result)
      |> assign(:rescrape_missing_count, get_missing_count(socket.assigns.rescrape_target))
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:cleanup_complete, result}, socket) do
    socket =
      socket
      |> assign(:cleanup_running, nil)
      |> assign(:cleanup_result, result)
      |> assign(:misclassified_preview, RealEstate.preview_misclassified_transaction_types())
      |> assign(:db_stats, get_db_stats())

    {:noreply, socket}
  end

  defp get_db_stats do
    active = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)

    # Source breakdown
    olx_count = Repo.aggregate(from(p in Property, where: p.active == true and p.source == "olx"), :count, :id)
    otodom_count = Repo.aggregate(from(p in Property, where: p.active == true and p.source == "otodom"), :count, :id)

    geocoded = Repo.aggregate(
      from(p in Property, where: p.active == true and not is_nil(p.latitude)),
      :count, :id
    )

    # Count duplicate URLs
    duplicate_query = """
    SELECT COUNT(*) FROM (
      SELECT url FROM properties WHERE url IS NOT NULL GROUP BY url HAVING COUNT(*) > 1
    ) as dupes
    """

    duplicates = case Ecto.Adapters.SQL.query(Repo, duplicate_query, []) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end

    # Count stale properties (active but not seen in 48+ hours)
    cutoff = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)
    stale = Repo.aggregate(
      from(p in Property, where: p.active == true and p.last_seen_at < ^cutoff),
      :count, :id
    )

    %{
      active: active,
      olx_count: olx_count,
      otodom_count: otodom_count,
      geocoded: geocoded,
      duplicates: duplicates,
      stale: stale
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

  # Scraper helpers
  defp run_scraper(:olx) do
    alias Rzeczywiscie.Scrapers.OlxScraper
    Logger.info("Running OLX scraper (3 pages)...")
    result = OlxScraper.scrape(pages: 3)
    "OLX: #{inspect(result)}"
  end

  defp run_scraper(:otodom) do
    alias Rzeczywiscie.Scrapers.OtodomScraper
    Logger.info("Running Otodom scraper (3 pages)...")
    result = OtodomScraper.scrape(pages: 3)
    "Otodom: #{inspect(result)}"
  end

  # Enrichment helpers
  defp run_enrichment_task(:rescrape, target) do
    alias Rzeczywiscie.Scrapers.PropertyRescraper
    Logger.info("Running rescrape for #{target}...")
    {:ok, stats} = PropertyRescraper.rescrape_missing(missing: target, limit: 50, delay: 2000)
    "Re-scraped: #{stats.updated} updated, #{stats.failed} failed"
  end

  defp run_enrichment_task(:geocode, _target) do
    run_geocode_task()
  end

  defp run_enrichment_task(:backfill_types, _target) do
    run_backfill_task()
  end

  defp run_enrichment_task(:backfill_rooms, _target) do
    run_backfill_rooms()
  end

  # Cleanup helpers
  defp run_cleanup_task(:stale) do
    {count, _} = RealEstate.mark_stale_properties_inactive(48)
    "Marked #{count} stale properties as inactive"
  end

  defp run_cleanup_task(:duplicates) do
    run_dedup_task()
  end

  defp run_cleanup_task(:misclassified) do
    {:ok, %{sales_to_rent: str, rent_to_sales: rts}} = RealEstate.fix_misclassified_transaction_types()
    "Fixed #{str} sales→rent, #{rts} rent→sales"
  end

  defp run_geocode_task do
    alias Rzeczywiscie.Workers.GeocodingWorker
    Logger.info("Running geocoding task...")
    :ok = GeocodingWorker.perform(%Oban.Job{})
    "Geocoding complete"
  end

  defp run_dedup_task do
    Logger.info("Starting deduplication...")

    # Find and remove duplicates
    duplicate_query = """
    WITH duplicates AS (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY url ORDER BY inserted_at) as rn
      FROM properties WHERE url IS NOT NULL
    )
    DELETE FROM properties WHERE id IN (SELECT id FROM duplicates WHERE rn > 1)
    """

    case Ecto.Adapters.SQL.query(Repo, duplicate_query, []) do
      {:ok, %{num_rows: count}} -> "Removed #{count} duplicates"
      {:error, reason} -> "Error: #{inspect(reason)}"
    end
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

end
