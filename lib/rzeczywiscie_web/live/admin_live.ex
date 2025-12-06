defmodule RzeczywiscieWeb.AdminLive do
  @moduledoc """
  Simplified Admin dashboard showing automation status and manual triggers.
  Most tasks are now automated - this page shows status and allows manual runs if needed.
  """
  
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  import Ecto.Query
  require Logger
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate
  alias Rzeczywiscie.RealEstate.Property

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to job updates if connected
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "oban:jobs")
    end
    
    socket =
      socket
      |> assign(:stats, get_stats())
      |> assign(:job_status, get_job_status())
      |> assign(:running_task, nil)
      |> assign(:task_result, nil)
      |> assign(:show_manual, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <.property_page_header current_path={@current_path} title="System Status" subtitle="Automated monitoring & maintenance">
        <:actions>
          <button phx-click="refresh" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer">
            🔄 Refresh
          </button>
        </:actions>
      </.property_page_header>

      <!-- Quick Stats -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-2 md:grid-cols-6 divide-x divide-base-content/30">
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-primary"><%= @stats.active %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Active Properties</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black"><%= @stats.olx %> / <%= @stats.otodom %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">OLX / Otodom</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-success"><%= @stats.geocoded_pct %>%</div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Geocoded</div>
            </div>
            <div class="p-4 text-center">
              <div class="text-3xl font-black text-info"><%= @stats.llm_analyzed %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">LLM Analyzed</div>
            </div>
            <div class="p-4 text-center">
              <div class={"text-3xl font-black #{if @stats.stale > 0, do: "text-warning", else: "text-success"}"}><%= @stats.stale %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Stale (4d+)</div>
            </div>
            <div class="p-4 text-center">
              <div class={"text-3xl font-black #{if @stats.duplicates > 0, do: "text-error", else: "text-success"}"}><%= @stats.duplicates %></div>
              <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Duplicates</div>
            </div>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-6">
        <!-- Automation Status -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <div class="px-4 py-3 border-b-2 border-base-content bg-gradient-to-r from-success/20 to-transparent">
            <h2 class="text-sm font-bold uppercase tracking-wide">⚡ Automated Tasks</h2>
            <p class="text-[10px] opacity-60">All tasks run automatically on schedule</p>
          </div>
          
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 p-4">
            <!-- Scraping -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">🌐 Scraping</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• OLX: every 6h (regular) + every 8h (enriched)</p>
                <p>• Otodom: every 6h with enrichment</p>
              </div>
              <%= if @job_status.last_scrape do %>
                <div class="mt-2 text-[10px] opacity-50">Last: <%= format_time_ago(@job_status.last_scrape) %></div>
              <% end %>
            </div>
            
            <!-- Geocoding -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">📍 Geocoding</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• Runs every hour</p>
                <p>• <%= @stats.pending_geocode %> pending</p>
              </div>
              <%= if @job_status.last_geocode do %>
                <div class="mt-2 text-[10px] opacity-50">Last: <%= format_time_ago(@job_status.last_geocode) %></div>
              <% end %>
            </div>
            
            <!-- LLM Analysis -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">🤖 LLM Analysis</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• Runs every 6h (30 properties)</p>
                <p>• <%= @stats.pending_llm %> with descriptions pending</p>
              </div>
              <%= if @job_status.last_llm do %>
                <div class="mt-2 text-[10px] opacity-50">Last: <%= format_time_ago(@job_status.last_llm) %></div>
              <% end %>
            </div>
            
            <!-- Price Tracking -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">📉 Price Tracking</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• Runs every 2 hours</p>
                <p>• <%= @stats.price_drops_7d %> drops in last 7 days</p>
              </div>
            </div>
            
            <!-- Data Maintenance -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">🧹 Maintenance</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• Daily at 4 AM</p>
                <p>• Dedup, fix types, backfill data</p>
              </div>
            </div>
            
            <!-- Cleanup -->
            <div class="border border-base-content/20 p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="font-bold text-sm">🗑️ Stale Cleanup</h3>
                <span class="px-2 py-1 text-[10px] font-bold bg-success/20 text-success">AUTO</span>
              </div>
              <div class="text-xs space-y-1 opacity-70">
                <p>• Daily at 5 AM</p>
                <p>• Deactivates properties not seen in 4+ days</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Manual Actions (collapsed by default) -->
        <div class="bg-base-100 border-2 border-base-content mb-6">
          <button 
            phx-click="toggle_manual" 
            class="w-full px-4 py-3 flex items-center justify-between hover:bg-base-200 transition-colors cursor-pointer"
          >
            <div>
              <h2 class="text-sm font-bold uppercase tracking-wide">🔧 Manual Actions</h2>
              <p class="text-[10px] opacity-60">Run tasks manually if needed</p>
            </div>
            <span class={"transition-transform #{if @show_manual, do: "rotate-180"}"}>▼</span>
          </button>
          
          <%= if @show_manual do %>
            <div class="border-t border-base-content/20 p-4">
              <%= if @task_result do %>
                <div class="mb-4 px-3 py-2 text-xs font-bold bg-success/20 text-success border border-success">
                  ✔ <%= @task_result %>
                </div>
              <% end %>
              
              <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
                <button 
                  phx-click="run_task" 
                  phx-value-task="scrape_olx"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-primary text-primary hover:bg-primary hover:text-primary-content"}"}
                >
                  <%= if @running_task == "scrape_olx", do: "⏳ Running...", else: "🌐 Scrape OLX" %>
                </button>
                
                <button 
                  phx-click="run_task" 
                  phx-value-task="scrape_otodom"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-secondary text-secondary hover:bg-secondary hover:text-secondary-content"}"}
                >
                  <%= if @running_task == "scrape_otodom", do: "⏳ Running...", else: "🌐 Scrape Otodom" %>
                </button>
                
                <button 
                  phx-click="run_task" 
                  phx-value-task="geocode"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-info text-info hover:bg-info hover:text-info-content"}"}
                >
                  <%= if @running_task == "geocode", do: "⏳ Running...", else: "📍 Geocode (50)" %>
                </button>
                
                <button 
                  phx-click="run_task" 
                  phx-value-task="llm"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-accent text-accent hover:bg-accent hover:text-accent-content"}"}
                >
                  <%= if @running_task == "llm", do: "⏳ Running...", else: "🤖 LLM Analysis" %>
                </button>
                
                <button 
                  phx-click="run_task" 
                  phx-value-task="maintenance"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-warning text-warning hover:bg-warning hover:text-warning-content"}"}
                >
                  <%= if @running_task == "maintenance", do: "⏳ Running...", else: "🧹 Maintenance" %>
                </button>
                
                <button 
                  phx-click="run_task" 
                  phx-value-task="cleanup"
                  disabled={@running_task != nil}
                  class={"px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 transition-colors cursor-pointer #{if @running_task != nil, do: "opacity-50 border-base-content/30", else: "border-error text-error hover:bg-error hover:text-error-content"}"}
                >
                  <%= if @running_task == "cleanup", do: "⏳ Running...", else: "🗑️ Mark Stale" %>
                </button>
              </div>
              
              <p class="mt-3 text-[10px] opacity-50">
                These tasks are already scheduled. Only use manual triggers if you need immediate results.
              </p>
            </div>
          <% end %>
        </div>

        <!-- LLM Stats (if any analyzed) -->
        <%= if @stats.llm_analyzed > 0 do %>
          <div class="bg-base-100 border-2 border-base-content mb-6">
            <div class="px-4 py-3 border-b-2 border-base-content bg-info/10">
              <h2 class="text-sm font-bold uppercase tracking-wide">🤖 LLM Analysis Overview</h2>
            </div>
            <div class="p-4">
              <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
                <div class="text-center">
                  <div class="text-2xl font-black text-success"><%= @stats.llm_high_score %></div>
                  <div class="text-[10px] font-bold uppercase opacity-60">Score 8+</div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-black text-warning"><%= @stats.llm_motivated %></div>
                  <div class="text-[10px] font-bold uppercase opacity-60">Very Motivated</div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-black text-error"><%= @stats.llm_renovation %></div>
                  <div class="text-[10px] font-bold uppercase opacity-60">Needs Renovation</div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-black"><%= @stats.llm_avg_score %></div>
                  <div class="text-[10px] font-bold uppercase opacity-60">Avg Score</div>
                </div>
                <div class="text-center">
                  <a href="/llm-results" class="inline-block px-4 py-2 text-xs font-bold uppercase border-2 border-info text-info hover:bg-info hover:text-info-content transition-colors">
                    View Results →
                  </a>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Quick Links -->
        <div class="bg-base-100 border-2 border-base-content">
          <div class="px-4 py-3 border-b-2 border-base-content bg-base-200">
            <h2 class="text-sm font-bold uppercase tracking-wide">🔗 Quick Links</h2>
          </div>
          <div class="p-4 flex flex-wrap gap-3">
            <a href="/real-estate" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">📋 Properties</a>
            <a href="/hot-deals" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-warning text-warning hover:bg-warning hover:text-warning-content transition-colors">🔥 Hot Deals</a>
            <a href="/llm-results" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-info text-info hover:bg-info hover:text-info-content transition-colors">🤖 LLM Results</a>
            <a href="/stats" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">📊 Statistics</a>
            <a href="/dev/dashboard" target="_blank" class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">⚙️ Phoenix Dashboard</a>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, 
      socket
      |> assign(:stats, get_stats())
      |> assign(:job_status, get_job_status())
    }
  end

  @impl true
  def handle_event("toggle_manual", _params, socket) do
    {:noreply, assign(socket, :show_manual, !socket.assigns.show_manual)}
  end

  @impl true
  def handle_event("run_task", %{"task" => task}, socket) do
    socket = 
      socket
      |> assign(:running_task, task)
      |> assign(:task_result, nil)
    
    parent = self()
    Task.start(fn ->
      result = run_task(task)
      send(parent, {:task_complete, result})
    end)
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:task_complete, result}, socket) do
    {:noreply, 
      socket
      |> assign(:running_task, nil)
      |> assign(:task_result, result)
      |> assign(:stats, get_stats())
    }
  end

  defp run_task("scrape_olx") do
    alias Rzeczywiscie.Scrapers.OlxScraper
    case OlxScraper.scrape(pages: 3, enrich: true) do
      {:ok, result} -> "OLX: #{result.saved}/#{result.total} saved"
      {:error, e} -> "OLX error: #{inspect(e)}"
    end
  end

  defp run_task("scrape_otodom") do
    alias Rzeczywiscie.Scrapers.OtodomScraper
    case OtodomScraper.scrape(pages: 3, enrich: true) do
      {:ok, result} -> "Otodom: #{result.saved}/#{result.total} saved"
      {:error, e} -> "Otodom error: #{inspect(e)}"
    end
  end

  defp run_task("geocode") do
    alias Rzeczywiscie.Workers.GeocodingWorker
    :ok = GeocodingWorker.perform(%Oban.Job{args: %{"batch_size" => 50, "delay_ms" => 500}})
    "Geocoded up to 50 properties"
  end

  defp run_task("llm") do
    alias Rzeczywiscie.Workers.LLMAnalysisWorker
    {:ok, _job} = LLMAnalysisWorker.trigger(limit: 30)
    "LLM analysis job queued (30 properties)"
  end

  defp run_task("maintenance") do
    alias Rzeczywiscie.Workers.DataMaintenanceWorker
    {:ok, _job} = DataMaintenanceWorker.trigger()
    "Maintenance job queued"
  end

  defp run_task("cleanup") do
    {count, _} = RealEstate.mark_stale_properties_inactive(96)
    "Marked #{count} stale properties as inactive"
  end

  defp get_stats do
    active = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)
    olx = Repo.aggregate(from(p in Property, where: p.active == true and p.source == "olx"), :count, :id)
    otodom = Repo.aggregate(from(p in Property, where: p.active == true and p.source == "otodom"), :count, :id)
    
    geocoded = Repo.aggregate(
      from(p in Property, where: p.active == true and not is_nil(p.latitude)),
      :count, :id
    )
    geocoded_pct = if active > 0, do: round(geocoded / active * 100), else: 0
    
    pending_geocode = Repo.aggregate(
      from(p in Property, where: p.active == true and is_nil(p.latitude)),
      :count, :id
    )
    
    llm_analyzed = Repo.aggregate(
      from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at)),
      :count, :id
    )
    
    pending_llm = Repo.aggregate(
      from(p in Property, 
        where: p.active == true and 
               is_nil(p.llm_analyzed_at) and 
               not is_nil(p.description) and 
               fragment("length(?)", p.description) > 100
      ),
      :count, :id
    )
    
    cutoff = DateTime.utc_now() |> DateTime.add(-96 * 3600, :second)
    stale = Repo.aggregate(
      from(p in Property, where: p.active == true and p.last_seen_at < ^cutoff),
      :count, :id
    )
    
    duplicate_query = """
    SELECT COUNT(*) FROM (
      SELECT url FROM properties WHERE url IS NOT NULL GROUP BY url HAVING COUNT(*) > 1
    ) as dupes
    """
    duplicates = case Ecto.Adapters.SQL.query(Repo, duplicate_query, []) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
    
    # Price drops in last 7 days
    week_ago = DateTime.utc_now() |> DateTime.add(-7 * 24 * 3600, :second)
    price_drops_7d = Repo.aggregate(
      from(ph in Rzeczywiscie.RealEstate.PriceHistory,
        where: ph.detected_at >= ^week_ago and ph.change_percentage < 0
      ),
      :count, :id
    )
    
    # LLM stats
    llm_high_score = Repo.aggregate(
      from(p in Property, where: p.active == true and p.llm_investment_score >= 8),
      :count, :id
    )
    llm_motivated = Repo.aggregate(
      from(p in Property, where: p.active == true and p.llm_motivation == "very_motivated"),
      :count, :id
    )
    llm_renovation = Repo.aggregate(
      from(p in Property, where: p.active == true and p.llm_condition == "needs_renovation"),
      :count, :id
    )
    llm_avg = Repo.one(
      from(p in Property,
        where: p.active == true and not is_nil(p.llm_investment_score),
        select: avg(p.llm_investment_score)
      )
    )
    llm_avg_score = if llm_avg, do: Float.round(Decimal.to_float(llm_avg), 1), else: 0
    
    %{
      active: active,
      olx: olx,
      otodom: otodom,
      geocoded_pct: geocoded_pct,
      pending_geocode: pending_geocode,
      llm_analyzed: llm_analyzed,
      pending_llm: pending_llm,
      stale: stale,
      duplicates: duplicates,
      price_drops_7d: price_drops_7d,
      llm_high_score: llm_high_score,
      llm_motivated: llm_motivated,
      llm_renovation: llm_renovation,
      llm_avg_score: llm_avg_score
    }
  end

  defp get_job_status do
    # Get last completed jobs from Oban
    # This is a simplified version - you could query oban_jobs table for more detail
    %{
      last_scrape: nil,
      last_geocode: nil,
      last_llm: nil
    }
  end

  defp format_time_ago(nil), do: "—"
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
