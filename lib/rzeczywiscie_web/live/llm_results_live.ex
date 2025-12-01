defmodule RzeczywiscieWeb.LLMResultsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  import Ecto.Query
  
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.Property

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:sort_by, "llm_investment_score")
      |> assign(:sort_dir, "desc")
      |> assign(:filter_investment, nil)
      |> assign(:filter_motivation, nil)
      |> assign(:filter_condition, nil)
      |> assign(:page, 1)
      |> assign(:per_page, 20)
      |> assign(:selected_property, nil)
      |> load_properties()
      |> load_stats()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <div class="bg-base-100 border-b-4 border-base-content">
        <div class="container mx-auto px-3 md:px-4 py-4 md:py-6">
          <Layouts.property_nav current_path={@current_path} />

          <div class="mt-3 md:mt-4 flex flex-col md:flex-row md:items-center md:justify-between gap-2">
            <div>
              <h1 class="text-xl md:text-3xl font-black uppercase tracking-tight">
                🤖 LLM Analysis
              </h1>
              <p class="text-xs md:text-sm font-bold uppercase tracking-wide opacity-60">
                AI-powered property insights
              </p>
            </div>
            <a href="/admin" class="px-3 py-1.5 text-xs font-bold uppercase border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors text-center">
              Run Analysis →
            </a>
          </div>
        </div>
      </div>

      <!-- Stats Bar -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-2 md:grid-cols-5 divide-x divide-y md:divide-y-0 divide-base-content/30">
            <div class="py-3 px-3 text-center">
              <div class="text-xl md:text-2xl font-black text-primary"><%= @stats.total_analyzed %></div>
              <div class="text-[9px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Total Analyzed</div>
            </div>
            <div class="py-3 px-3 text-center">
              <div class="text-xl md:text-2xl font-black text-success"><%= @stats.high_investment %></div>
              <div class="text-[9px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Score 8+ 🔥</div>
            </div>
            <div class="py-3 px-3 text-center">
              <div class="text-xl md:text-2xl font-black text-warning"><%= @stats.motivated_sellers %></div>
              <div class="text-[9px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Motivated</div>
            </div>
            <div class="py-3 px-3 text-center">
              <div class="text-xl md:text-2xl font-black text-error"><%= @stats.needs_renovation %></div>
              <div class="text-[9px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">To Renovate</div>
            </div>
            <div class="py-3 px-3 text-center col-span-2 md:col-span-1">
              <div class="text-xl md:text-2xl font-black text-info"><%= Float.round(@stats.avg_investment_score, 1) %>/10</div>
              <div class="text-[9px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Avg Investment</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Filters & Sort -->
      <div class="container mx-auto px-3 md:px-4 py-3">
        <div class="bg-base-100 border-2 border-base-content">
          <!-- Row 1: Quick Filters -->
          <div class="flex flex-wrap items-stretch border-b border-base-content/30">
            <!-- Investment Score -->
            <div class="flex items-center border-r border-base-content/30">
              <span class="px-2 py-2 text-[9px] font-bold uppercase tracking-wide opacity-50 bg-base-200 hidden sm:block">Score</span>
              <button phx-click="filter_investment" phx-value-score="" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold transition-colors cursor-pointer #{if @filter_investment == nil, do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}>
                All
              </button>
              <button phx-click="filter_investment" phx-value-score="8" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 8, do: "bg-success text-success-content", else: "hover:bg-base-200"}"}>
                8+ 🔥
              </button>
              <button phx-click="filter_investment" phx-value-score="5" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 5, do: "bg-info text-info-content", else: "hover:bg-base-200"}"}>
                5-7
              </button>
              <button phx-click="filter_investment" phx-value-score="0" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 0, do: "bg-base-300", else: "hover:bg-base-200"}"}>
                &lt;5
              </button>
            </div>
            
            <!-- Motivation -->
            <div class="flex items-center border-r border-base-content/30">
              <span class="px-2 py-2 text-[9px] font-bold uppercase tracking-wide opacity-50 bg-base-200 hidden sm:block">Seller</span>
              <button phx-click="filter_motivation" phx-value-motivation="" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold transition-colors cursor-pointer #{if @filter_motivation == nil, do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}>
                All
              </button>
              <button phx-click="filter_motivation" phx-value-motivation="very_motivated" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_motivation == "very_motivated", do: "bg-warning text-warning-content", else: "hover:bg-base-200"}"}>
                🔥 Very
              </button>
              <button phx-click="filter_motivation" phx-value-motivation="motivated" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_motivation == "motivated", do: "bg-info/80 text-info-content", else: "hover:bg-base-200"}"}>
                💰
              </button>
            </div>

            <!-- Condition -->
            <div class="flex items-center flex-1">
              <span class="px-2 py-2 text-[9px] font-bold uppercase tracking-wide opacity-50 bg-base-200 hidden sm:block">Condition</span>
              <button phx-click="filter_condition" phx-value-condition="" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold transition-colors cursor-pointer #{if @filter_condition == nil, do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}>
                All
              </button>
              <button phx-click="filter_condition" phx-value-condition="needs_renovation" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_condition == "needs_renovation", do: "bg-error/80 text-error-content", else: "hover:bg-base-200"}"}>
                🔧
              </button>
              <button phx-click="filter_condition" phx-value-condition="good" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_condition == "good", do: "bg-success/80 text-success-content", else: "hover:bg-base-200"}"}>
                ✓
              </button>
              <button phx-click="filter_condition" phx-value-condition="new" class={"px-2 md:px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_condition == "new", do: "bg-primary/80 text-primary-content", else: "hover:bg-base-200"}"}>
                ✨
              </button>
            </div>
            
            <!-- Sort Dropdown -->
            <div class="flex items-center border-l border-base-content/30">
              <form phx-change="sort_changed" class="flex items-center">
                <select name="sort_by" class="px-2 py-2 text-xs border-0 bg-base-100 focus:outline-none cursor-pointer font-bold">
                  <option value="llm_investment_score" selected={@sort_by == "llm_investment_score"}>📊 Investment</option>
                  <option value="llm_urgency" selected={@sort_by == "llm_urgency"}>⚡ Urgency</option>
                  <option value="price_asc" selected={@sort_by == "price_asc"}>💰 Price ↑</option>
                  <option value="price_desc" selected={@sort_by == "price_desc"}>💰 Price ↓</option>
                  <option value="llm_analyzed_at" selected={@sort_by == "llm_analyzed_at"}>🕐 Newest</option>
                </select>
              </form>
            </div>
          </div>

          <!-- Row 2: Active Filters Summary -->
          <%= if @filter_investment || @filter_motivation || @filter_condition do %>
            <div class="px-3 py-2 flex flex-wrap items-center gap-2 bg-base-200/50">
              <span class="text-[10px] font-bold uppercase opacity-50">Active:</span>
              <%= if @filter_investment do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-primary text-primary-content">
                  Score <%= if @filter_investment == 8, do: "8+", else: if(@filter_investment == 5, do: "5-7", else: "<5") %>
                  <button phx-click="filter_investment" phx-value-score="" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_motivation do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-warning text-warning-content">
                  <%= @filter_motivation %>
                  <button phx-click="filter_motivation" phx-value-motivation="" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_condition do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-info text-info-content">
                  <%= @filter_condition %>
                  <button phx-click="filter_condition" phx-value-condition="" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <button phx-click="clear_filters" class="ml-auto text-[10px] font-bold uppercase text-error hover:underline cursor-pointer">
                Clear all
              </button>
            </div>
          <% end %>
        </div>
        
        <!-- Results Count -->
        <div class="mt-3 mb-2 text-xs font-bold uppercase opacity-60">
          <%= @total_count %> properties
        </div>

        <!-- Results Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
          <%= for property <- @properties do %>
            <div class={"bg-base-100 border-2 transition-colors hover:shadow-lg #{border_class(property.llm_investment_score)}"}>
              <div class="flex">
                <!-- Left: Image + Score -->
                <div class="relative w-24 md:w-32 shrink-0">
                  <!-- Image -->
                  <%= if property.image_url do %>
                    <img 
                      src={property.image_url} 
                      alt="" 
                      class="w-full h-full object-cover min-h-[120px]"
                      loading="lazy"
                    />
                  <% else %>
                    <div class="w-full h-full min-h-[120px] bg-base-300 flex items-center justify-center text-2xl opacity-30">
                      🏠
                    </div>
                  <% end %>
                  
                  <!-- Investment Score Badge -->
                  <div class={"absolute top-0 left-0 px-2 py-1 text-lg font-black #{score_badge_class(property.llm_investment_score)}"}>
                    <%= property.llm_investment_score || "?" %>
                  </div>
                  
                  <!-- Motivation Badge -->
                  <%= if property.llm_motivation == "very_motivated" do %>
                    <div class="absolute top-0 right-0 px-1.5 py-0.5 bg-warning text-warning-content text-xs font-black">
                      🔥
                    </div>
                  <% end %>
                  
                  <!-- Condition Badge -->
                  <div class={"absolute bottom-0 left-0 right-0 px-2 py-1 text-[10px] font-bold uppercase text-center #{condition_badge_class(property.llm_condition)}"}>
                    <%= property.llm_condition || "?" %>
                  </div>
                </div>
                
                <!-- Right: Content -->
                <div class="flex-1 p-3 min-w-0">
                  <!-- Title -->
                  <a href={property.url} target="_blank" class="group">
                    <h3 class="font-bold text-sm leading-tight line-clamp-2 group-hover:text-primary transition-colors">
                      <%= property.title %>
                      <span class="text-primary opacity-0 group-hover:opacity-100">↗</span>
                    </h3>
                  </a>
                  
                  <!-- Location & Price -->
                  <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mt-1.5 text-[11px]">
                    <span class="opacity-60">📍 <%= property.district || property.city || "?" %></span>
                    <span class="font-bold text-primary"><%= format_price(property.price) %></span>
                    <span class="opacity-40"><%= format_area(property.area_sqm) %></span>
                    <%= if property.llm_monthly_fee do %>
                      <span class="text-warning">+<%= property.llm_monthly_fee %> zł/mies</span>
                    <% end %>
                  </div>
                  
                  <!-- AI Summary -->
                  <%= if property.llm_summary && not String.contains?(property.llm_summary || "", "Skipped") do %>
                    <div class="mt-2 p-2 bg-gradient-to-r from-info/10 to-transparent border-l-2 border-info text-xs leading-relaxed line-clamp-2">
                      💡 <%= property.llm_summary %>
                    </div>
                  <% end %>
                  
                  <!-- Tags -->
                  <div class="flex flex-wrap gap-1 mt-2">
                    <%= if property.llm_urgency && property.llm_urgency >= 5 do %>
                      <span class={"px-1.5 py-0.5 text-[9px] font-bold uppercase #{if property.llm_urgency >= 7, do: "bg-error text-error-content", else: "bg-warning/30 text-warning"}"}>
                        ⚡ <%= property.llm_urgency %>
                      </span>
                    <% end %>
                    <%= if property.llm_positive_signals && length(property.llm_positive_signals) > 0 do %>
                      <span class="px-1.5 py-0.5 text-[9px] font-bold bg-success/20 text-success">
                        ✨ <%= length(property.llm_positive_signals) %>
                      </span>
                    <% end %>
                    <%= if property.llm_red_flags && length(property.llm_red_flags) > 0 do %>
                      <span class="px-1.5 py-0.5 text-[9px] font-bold bg-error/20 text-error">
                        🚩 <%= length(property.llm_red_flags) %>
                      </span>
                    <% end %>
                    <%= if property.llm_hidden_costs && length(property.llm_hidden_costs) > 0 do %>
                      <span class="px-1.5 py-0.5 text-[9px] font-bold bg-warning/20 text-warning">
                        💸 <%= length(property.llm_hidden_costs) %>
                      </span>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          
          <%= if length(@properties) == 0 do %>
            <div class="col-span-full bg-base-100 border-2 border-base-content p-12 text-center">
              <div class="text-4xl mb-3">🤖</div>
              <div class="text-xl font-black uppercase mb-2">No Results</div>
              <div class="text-sm opacity-60">
                <%= if @filter_investment || @filter_motivation || @filter_condition do %>
                  Try adjusting your filters
                <% else %>
                  Run LLM Analysis from the Admin panel
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        
        <!-- Pagination -->
        <%= if @total_pages > 1 do %>
          <div class="mt-6 flex flex-col sm:flex-row items-center justify-between gap-4">
            <div class="text-xs opacity-60">
              Showing <%= (@page - 1) * @per_page + 1 %>-<%= min(@page * @per_page, @total_count) %> of <%= @total_count %>
            </div>
            <div class="flex border-2 border-base-content">
              <button phx-click="prev_page" disabled={@page == 1} class="px-4 py-2 text-sm font-bold hover:bg-base-content hover:text-base-100 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer">
                ← Prev
              </button>
              <span class="px-4 py-2 text-sm font-bold border-l-2 border-base-content bg-base-content text-base-100">
                <%= @page %>/<%= @total_pages %>
              </span>
              <button phx-click="next_page" disabled={@page == @total_pages} class="px-4 py-2 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer">
                Next →
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    </.app>
    """
  end

  # Event Handlers
  
  @impl true
  def handle_event("filter_investment", %{"score" => ""}, socket) do
    {:noreply, socket |> assign(:filter_investment, nil) |> assign(:page, 1) |> load_properties()}
  end
  
  def handle_event("filter_investment", %{"score" => score}, socket) do
    {:noreply, socket |> assign(:filter_investment, String.to_integer(score)) |> assign(:page, 1) |> load_properties()}
  end
  
  @impl true
  def handle_event("filter_motivation", %{"motivation" => ""}, socket) do
    {:noreply, socket |> assign(:filter_motivation, nil) |> assign(:page, 1) |> load_properties()}
  end
  
  def handle_event("filter_motivation", %{"motivation" => motivation}, socket) do
    {:noreply, socket |> assign(:filter_motivation, motivation) |> assign(:page, 1) |> load_properties()}
  end

  @impl true
  def handle_event("filter_condition", %{"condition" => ""}, socket) do
    {:noreply, socket |> assign(:filter_condition, nil) |> assign(:page, 1) |> load_properties()}
  end
  
  def handle_event("filter_condition", %{"condition" => condition}, socket) do
    {:noreply, socket |> assign(:filter_condition, condition) |> assign(:page, 1) |> load_properties()}
  end
  
  @impl true
  def handle_event("sort_changed", %{"sort_by" => sort_by}, socket) do
    {:noreply, socket |> assign(:sort_by, sort_by) |> assign(:page, 1) |> load_properties()}
  end

  @impl true
  def handle_event("clear_filters", _, socket) do
    {:noreply, 
      socket 
      |> assign(:filter_investment, nil) 
      |> assign(:filter_motivation, nil) 
      |> assign(:filter_condition, nil)
      |> assign(:page, 1) 
      |> load_properties()
    }
  end
  
  @impl true
  def handle_event("prev_page", _, socket) do
    {:noreply, socket |> assign(:page, max(1, socket.assigns.page - 1)) |> load_properties()}
  end
  
  @impl true
  def handle_event("next_page", _, socket) do
    {:noreply, socket |> assign(:page, min(socket.assigns.total_pages, socket.assigns.page + 1)) |> load_properties()}
  end

  # Data Loading

  defp load_properties(socket) do
    query = from(p in Property,
      where: p.active == true and not is_nil(p.llm_analyzed_at)
    )
    
    # Apply investment filter
    query = case socket.assigns.filter_investment do
      8 -> where(query, [p], p.llm_investment_score >= 8)
      5 -> where(query, [p], p.llm_investment_score >= 5 and p.llm_investment_score < 8)
      0 -> where(query, [p], p.llm_investment_score < 5 or is_nil(p.llm_investment_score))
      _ -> query
    end
    
    # Apply motivation filter
    query = case socket.assigns.filter_motivation do
      nil -> query
      motivation -> where(query, [p], p.llm_motivation == ^motivation)
    end

    # Apply condition filter
    query = case socket.assigns.filter_condition do
      nil -> query
      condition -> where(query, [p], p.llm_condition == ^condition)
    end
    
    # Get total count
    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(1, ceil(total_count / socket.assigns.per_page))
    
    # Apply sorting
    query = case socket.assigns.sort_by do
      "llm_investment_score" -> order_by(query, [p], [desc_nulls_last: p.llm_investment_score, desc: p.llm_analyzed_at])
      "llm_urgency" -> order_by(query, [p], [desc_nulls_last: p.llm_urgency, desc: p.llm_analyzed_at])
      "price_asc" -> order_by(query, [p], [asc_nulls_last: p.price])
      "price_desc" -> order_by(query, [p], [desc_nulls_last: p.price])
      "llm_analyzed_at" -> order_by(query, [p], [desc: p.llm_analyzed_at])
      _ -> order_by(query, [p], [desc_nulls_last: p.llm_investment_score, desc: p.llm_analyzed_at])
    end
    
    # Paginate
    offset = (socket.assigns.page - 1) * socket.assigns.per_page
    properties = query
    |> limit(^socket.assigns.per_page)
    |> offset(^offset)
    |> Repo.all()
    
    socket
    |> assign(:properties, properties)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end
  
  defp load_stats(socket) do
    base_query = from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at))
    
    stats = %{
      total_analyzed: Repo.aggregate(base_query, :count, :id),
      high_investment: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and p.llm_investment_score >= 8),
        :count, :id
      ),
      motivated_sellers: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and p.llm_motivation in ["motivated", "very_motivated"]),
        :count, :id
      ),
      needs_renovation: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and p.llm_condition == "needs_renovation"),
        :count, :id
      ),
      avg_investment_score: (Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and not is_nil(p.llm_investment_score)),
        :avg, :llm_investment_score
      ) || Decimal.new(0)) |> Decimal.to_float()
    }
    
    assign(socket, :stats, stats)
  end

  # Formatting Helpers
  
  defp format_price(nil), do: "?"
  defp format_price(price) do
    price
    |> Decimal.to_float()
    |> trunc()
    |> Number.Delimit.number_to_delimited(delimiter: " ", separator: ",", precision: 0)
    |> Kernel.<>(" zł")
  rescue
    _ -> "#{price} zł"
  end

  defp format_area(nil), do: ""
  defp format_area(area), do: "#{Decimal.to_string(area)} m²"
  
  # Styling Helpers
  
  defp border_class(score) when is_integer(score) and score >= 8, do: "border-success"
  defp border_class(score) when is_integer(score) and score >= 5, do: "border-info"
  defp border_class(score) when is_integer(score) and score >= 3, do: "border-warning"
  defp border_class(_), do: "border-base-content"
  
  defp score_badge_class(score) when is_integer(score) and score >= 8, do: "bg-success text-success-content"
  defp score_badge_class(score) when is_integer(score) and score >= 5, do: "bg-info text-info-content"
  defp score_badge_class(score) when is_integer(score) and score >= 3, do: "bg-warning text-warning-content"
  defp score_badge_class(score) when is_integer(score), do: "bg-error text-error-content"
  defp score_badge_class(_), do: "bg-base-300"

  defp condition_badge_class("new"), do: "bg-primary text-primary-content"
  defp condition_badge_class("renovated"), do: "bg-success text-success-content"
  defp condition_badge_class("good"), do: "bg-info/80 text-info-content"
  defp condition_badge_class("to_finish"), do: "bg-warning text-warning-content"
  defp condition_badge_class("needs_renovation"), do: "bg-error text-error-content"
  defp condition_badge_class(_), do: "bg-base-300/80"
end
