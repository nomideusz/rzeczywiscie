defmodule RzeczywiscieWeb.AdminLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:backfill_status, nil)
      |> assign(:backfill_running, false)
      |> assign(:backfill_result, nil)
      |> assign(:olx_scrape_running, false)
      |> assign(:olx_scrape_result, nil)
      |> assign(:otodom_scrape_running, false)
      |> assign(:otodom_scrape_result, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
    <div class="container mx-auto p-8 max-w-2xl">
      <!-- Sub-navigation tabs -->
      <div class="mb-6">
        <div class="tabs tabs-boxed bg-base-200 border-2 border-base-content">
          <a href="/real-estate" class="tab font-bold">Properties</a>
          <a href="/favorites" class="tab font-bold">Favorites</a>
          <a href="/stats" class="tab font-bold">Stats</a>
          <a href="/admin" class="tab tab-active font-bold">Admin</a>
        </div>
      </div>

      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Admin Tasks</h1>
      </div>

      <div class="alert alert-info mb-6">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <div>
          <div class="font-bold">Need to debug URLs?</div>
          <div class="text-xs">
            <a href="/url-inspector" class="link">Visit URL Inspector</a> to see sample property URLs
          </div>
        </div>
      </div>

      <!-- Manual Scrapers -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
        <!-- OLX Scraper -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">OLX Scraper</h2>
            <p class="text-sm opacity-70 mb-4">
              Manually trigger OLX scraping. Will scrape 2 pages of listings.
            </p>

            <%= if @olx_scrape_running do %>
              <div class="alert alert-info">
                <div class="loading loading-spinner"></div>
                <span>Scraping OLX...</span>
              </div>
            <% end %>

            <%= if @olx_scrape_result do %>
              <div class="alert alert-success">
                <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div class="text-sm"><%= @olx_scrape_result %></div>
              </div>
            <% end %>

            <div class="card-actions justify-end mt-4">
              <button
                phx-click="run_olx_scrape"
                class="btn btn-primary btn-sm"
                disabled={@olx_scrape_running}
              >
                <%= if @olx_scrape_running, do: "Running...", else: "Scrape OLX" %>
              </button>
            </div>
          </div>
        </div>

        <!-- Otodom Scraper -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Otodom Scraper</h2>
            <p class="text-sm opacity-70 mb-4">
              Manually trigger Otodom scraping. Will scrape 2 pages each of sale and rent listings.
            </p>

            <%= if @otodom_scrape_running do %>
              <div class="alert alert-info">
                <div class="loading loading-spinner"></div>
                <span>Scraping Otodom...</span>
              </div>
            <% end %>

            <%= if @otodom_scrape_result do %>
              <div class="alert alert-success">
                <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div class="text-sm"><%= @otodom_scrape_result %></div>
              </div>
            <% end %>

            <div class="card-actions justify-end mt-4">
              <button
                phx-click="run_otodom_scrape"
                class="btn btn-primary btn-sm"
                disabled={@otodom_scrape_running}
              >
                <%= if @otodom_scrape_running, do: "Running...", else: "Scrape Otodom" %>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Backfill Property Types -->
      <div class="card bg-base-200 shadow-xl mb-6">
        <div class="card-body">
          <h2 class="card-title">Backfill Property Types</h2>
          <p class="text-sm opacity-70 mb-4">
            This task updates existing properties with transaction_type and property_type
            by extracting them from the URL patterns. Run this once after deployment.
          </p>

          <%= if @backfill_running do %>
            <div class="alert alert-info">
              <div class="loading loading-spinner"></div>
              <span>Running backfill task...</span>
            </div>
          <% end %>

          <%= if @backfill_result do %>
            <div class="alert alert-success">
              <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div>
                <h3 class="font-bold">Backfill completed!</h3>
                <div class="text-sm"><%= @backfill_result %></div>
              </div>
            </div>
          <% end %>

          <div class="card-actions justify-end mt-4">
            <button
              phx-click="run_backfill"
              class="btn btn-primary"
              disabled={@backfill_running}
            >
              <%= if @backfill_running, do: "Running...", else: "Run Backfill" %>
            </button>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("run_backfill", _params, socket) do
    Logger.info("Starting backfill from admin panel")

    socket = assign(socket, :backfill_running, true)

    # Run backfill in a task to avoid blocking
    parent = self()
    Task.start(fn ->
      result = run_backfill_task()
      send(parent, {:backfill_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_olx_scrape", _params, socket) do
    Logger.info("Starting OLX scrape from admin panel")

    socket = assign(socket, :olx_scrape_running, true)

    parent = self()
    Task.start(fn ->
      result = run_olx_scraper()
      send(parent, {:olx_scrape_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_otodom_scrape", _params, socket) do
    Logger.info("Starting Otodom scrape from admin panel")

    socket = assign(socket, :otodom_scrape_running, true)

    parent = self()
    Task.start(fn ->
      result = run_otodom_scraper()
      send(parent, {:otodom_scrape_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:backfill_complete, result}, socket) do
    socket =
      socket
      |> assign(:backfill_running, false)
      |> assign(:backfill_result, result)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:olx_scrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:olx_scrape_running, false)
      |> assign(:olx_scrape_result, result)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:otodom_scrape_complete, result}, socket) do
    socket =
      socket
      |> assign(:otodom_scrape_running, false)
      |> assign(:otodom_scrape_result, result)

    {:noreply, socket}
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
          transaction_type = extract_transaction_type(property.url)
          property_type = extract_property_type(property.url)

          changes = %{}
          changes = if transaction_type, do: Map.put(changes, :transaction_type, transaction_type), else: changes
          changes = if property_type, do: Map.put(changes, :property_type, property_type), else: changes

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
            Logger.info("- No type info found in URL for property #{property.id}")
            count
          end
        end)

      result = "Updated #{updated} out of #{length(properties)} properties"
      Logger.info("✓ Backfill completed: #{result}")
      result
    end
  end

  defp extract_transaction_type(url) do
    url_lower = String.downcase(url)

    cond do
      # Keywords for sale (sprzedaż)
      String.contains?(url_lower, "sprzedam") -> "sprzedaż"
      String.contains?(url_lower, "sprzedaz") -> "sprzedaż"
      String.contains?(url_lower, "na-sprzedaz") -> "sprzedaż"

      # Keywords for rent (wynajem)
      String.contains?(url_lower, "wynajme") -> "wynajem"
      String.contains?(url_lower, "wynajem") -> "wynajem"
      String.contains?(url_lower, "do-wynajecia") -> "wynajem"
      String.contains?(url_lower, "na-wynajem") -> "wynajem"

      true -> nil
    end
  end

  defp extract_property_type(url) do
    url_lower = String.downcase(url)

    cond do
      # Apartment (mieszkanie)
      String.contains?(url_lower, "mieszkanie") -> "mieszkanie"
      String.contains?(url_lower, "mieszkania") -> "mieszkanie"

      # House (dom)
      String.contains?(url_lower, "-dom-") -> "dom"
      String.contains?(url_lower, "/dom-") -> "dom"
      String.match?(url_lower, ~r/\bdom\b/) -> "dom"

      # Room (pokój)
      String.contains?(url_lower, "pokoj") -> "pokój"

      # Garage (garaż)
      String.contains?(url_lower, "garaz") -> "garaż"

      # Plot/land (działka)
      String.contains?(url_lower, "dzialka") -> "działka"

      # Commercial space (lokal użytkowy)
      String.contains?(url_lower, "lokal-uzytkowy") -> "lokal użytkowy"
      String.contains?(url_lower, "lokal-biurowo") -> "lokal użytkowy"
      String.contains?(url_lower, "lokal-handlowy") -> "lokal użytkowy"

      # Student accommodation (stancja)
      String.contains?(url_lower, "stancja") -> "stancja"

      true -> nil
    end
  end

  defp run_olx_scraper do
    alias Rzeczywiscie.Scrapers.OlxScraper

    Logger.info("Running manual OLX scrape...")

    case OlxScraper.scrape(pages: 2, delay: 2000) do
      {:ok, %{total: total, saved: saved}} ->
        "OLX: Found #{total} listings, saved #{saved} properties"

      {:error, reason} ->
        "OLX scrape failed: #{inspect(reason)}"
    end
  end

  defp run_otodom_scraper do
    alias Rzeczywiscie.Scrapers.OtodomScraper

    Logger.info("Running manual Otodom scrape...")

    case OtodomScraper.scrape(pages: 2, delay: 3000) do
      {:ok, %{total: total, saved: saved}} ->
        "Otodom: Found #{total} listings, saved #{saved} properties"

      {:error, reason} ->
        "Otodom scrape failed: #{inspect(reason)}"
    end
  end
end
