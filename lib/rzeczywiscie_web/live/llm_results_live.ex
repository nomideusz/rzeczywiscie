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
      |> assign(:sort_by, "llm_analyzed_at")
      |> assign(:sort_dir, "desc")
      |> assign(:filter_investment, nil)
      |> assign(:filter_motivation, nil)
      |> assign(:page, 1)
      |> assign(:per_page, 25)
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
          <!-- Navigation -->
          <nav class="flex gap-1 overflow-x-auto scrollbar-hide -mx-3 px-3 md:mx-0 md:px-0 md:flex-wrap">
            <a href="/real-estate" class="px-2 md:px-3 py-1.5 md:py-2 text-[10px] md:text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors whitespace-nowrap shrink-0">
              Properties
            </a>
            <a href="/hot-deals" class="px-2 md:px-3 py-1.5 md:py-2 text-[10px] md:text-xs font-bold uppercase tracking-wide border-2 border-warning text-warning hover:bg-warning hover:text-warning-content transition-colors whitespace-nowrap shrink-0">
              🔥 Hot Deals
            </a>
            <a href="/llm-results" class="px-2 md:px-3 py-1.5 md:py-2 text-[10px] md:text-xs font-bold uppercase tracking-wide bg-base-content text-base-100 whitespace-nowrap shrink-0">
              🤖 LLM Results
            </a>
            <a href="/admin" class="px-2 md:px-3 py-1.5 md:py-2 text-[10px] md:text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors whitespace-nowrap shrink-0">
              Admin
            </a>
          </nav>

          <div class="mt-3 md:mt-4">
            <h1 class="text-xl md:text-3xl font-black uppercase tracking-tight">
              🤖 LLM Analysis Results
            </h1>
            <p class="text-xs md:text-sm font-bold uppercase tracking-wide opacity-60">
              Properties analyzed by AI
            </p>
          </div>
        </div>
      </div>

      <!-- Stats -->
      <div class="bg-base-100 border-b-2 border-base-content">
        <div class="container mx-auto">
          <div class="grid grid-cols-4 divide-x-2 divide-base-content">
            <div class="py-2 px-2 md:px-3 text-center">
              <div class="text-lg md:text-2xl font-black text-primary"><%= @stats.total_analyzed %></div>
              <div class="text-[8px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Analyzed</div>
            </div>
            <div class="py-2 px-2 md:px-3 text-center">
              <div class="text-lg md:text-2xl font-black text-success"><%= @stats.high_investment %></div>
              <div class="text-[8px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Score 8+</div>
            </div>
            <div class="py-2 px-2 md:px-3 text-center">
              <div class="text-lg md:text-2xl font-black text-warning"><%= @stats.motivated_sellers %></div>
              <div class="text-[8px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Motivated</div>
            </div>
            <div class="py-2 px-2 md:px-3 text-center">
              <div class="text-lg md:text-2xl font-black text-info"><%= Float.round(@stats.avg_score, 1) %></div>
              <div class="text-[8px] md:text-[10px] font-bold uppercase tracking-wide opacity-60">Avg Score</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="container mx-auto px-3 md:px-4 py-3 md:py-4">
        <div class="bg-base-100 border-2 border-base-content p-3 mb-4">
          <div class="flex flex-wrap gap-2 items-center">
            <span class="text-[10px] md:text-xs font-bold uppercase opacity-60">Filter:</span>
            
            <!-- Investment Score Filter -->
            <div class="flex border-2 border-base-content">
              <button phx-click="filter_investment" phx-value-score="" class={"px-2 py-1 text-[10px] md:text-xs font-bold transition-colors cursor-pointer #{if @filter_investment == nil, do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}>
                All
              </button>
              <button phx-click="filter_investment" phx-value-score="8" class={"px-2 py-1 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 8, do: "bg-success text-success-content", else: "hover:bg-base-200"}"}>
                8+ 🔥
              </button>
              <button phx-click="filter_investment" phx-value-score="5" class={"px-2 py-1 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 5, do: "bg-info text-info-content", else: "hover:bg-base-200"}"}>
                5-7
              </button>
              <button phx-click="filter_investment" phx-value-score="0" class={"px-2 py-1 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_investment == 0, do: "bg-error text-error-content", else: "hover:bg-base-200"}"}>
                0-4
              </button>
            </div>
            
            <!-- Motivation Filter -->
            <div class="flex border-2 border-base-content">
              <button phx-click="filter_motivation" phx-value-motivation="" class={"px-2 py-1 text-[10px] md:text-xs font-bold transition-colors cursor-pointer #{if @filter_motivation == nil, do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}>
                All
              </button>
              <button phx-click="filter_motivation" phx-value-motivation="very_motivated" class={"px-2 py-1 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_motivation == "very_motivated", do: "bg-warning text-warning-content", else: "hover:bg-base-200"}"}>
                Very 🔥
              </button>
              <button phx-click="filter_motivation" phx-value-motivation="motivated" class={"px-2 py-1 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @filter_motivation == "motivated", do: "bg-info text-info-content", else: "hover:bg-base-200"}"}>
                Motivated
              </button>
            </div>
            
            <!-- Sort -->
            <div class="ml-auto flex items-center gap-2">
              <span class="text-[10px] md:text-xs font-bold uppercase opacity-60 hidden sm:inline">Sort:</span>
              <select phx-change="sort_changed" class="px-2 py-1 text-xs border-2 border-base-content bg-base-100">
                <option value="llm_analyzed_at" selected={@sort_by == "llm_analyzed_at"}>Newest</option>
                <option value="llm_investment_score" selected={@sort_by == "llm_investment_score"}>Investment ↓</option>
                <option value="llm_score" selected={@sort_by == "llm_score"}>LLM Score ↓</option>
                <option value="llm_urgency" selected={@sort_by == "llm_urgency"}>Urgency ↓</option>
              </select>
            </div>
          </div>
        </div>

        <!-- Results -->
        <div class="space-y-3">
          <%= for property <- @properties do %>
            <div class="bg-base-100 border-2 border-base-content hover:border-primary transition-colors">
              <div class="flex flex-col md:flex-row">
                <!-- Scores Column -->
                <div class="flex md:flex-col items-center justify-around md:justify-center gap-2 p-3 md:p-4 bg-base-200 border-b md:border-b-0 md:border-r border-base-content/30 md:w-24 shrink-0">
                  <div class={"text-center p-2 border-2 #{investment_score_class(property.llm_investment_score)}"}>
                    <div class={"text-xl md:text-2xl font-black #{investment_score_text_class(property.llm_investment_score)}"}>
                      <%= property.llm_investment_score || "?" %>
                    </div>
                    <div class="text-[8px] font-bold uppercase opacity-60">INV</div>
                  </div>
                  <div class="text-center">
                    <div class="text-lg font-bold text-primary"><%= property.llm_score || 0 %></div>
                    <div class="text-[8px] font-bold uppercase opacity-60">Score</div>
                  </div>
                </div>
                
                <!-- Main Content -->
                <div class="flex-1 p-3 md:p-4 min-w-0">
                  <!-- Title & Meta -->
                  <div class="flex items-start gap-2 mb-2">
                    <div class="flex-1 min-w-0">
                      <h3 class="font-bold text-sm md:text-base leading-tight line-clamp-2"><%= property.title %></h3>
                      <div class="text-[10px] md:text-xs opacity-60 mt-1">
                        <%= property.district || property.city || "?" %> · 
                        <%= if property.price, do: "#{Decimal.to_string(property.price)} PLN", else: "?" %> · 
                        <%= if property.area_sqm, do: "#{Decimal.to_string(property.area_sqm)} m²", else: "?" %>
                      </div>
                    </div>
                    <a href={property.url} target="_blank" class="px-2 py-1 text-xs font-bold border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors shrink-0">
                      ↗
                    </a>
                  </div>
                  
                  <!-- AI Summary -->
                  <%= if property.llm_summary do %>
                    <div class="bg-info/10 border border-info/30 p-2 mb-2 text-xs">
                      💡 <%= property.llm_summary %>
                    </div>
                  <% end %>
                  
                  <!-- Tags Row -->
                  <div class="flex flex-wrap gap-1.5">
                    <!-- Condition -->
                    <%= if property.llm_condition && property.llm_condition != "unknown" do %>
                      <span class="px-2 py-0.5 text-[10px] font-bold uppercase bg-base-200 border border-base-content/30">
                        <%= property.llm_condition %>
                      </span>
                    <% end %>
                    
                    <!-- Motivation -->
                    <%= if property.llm_motivation && property.llm_motivation not in ["unknown", "standard"] do %>
                      <span class={"px-2 py-0.5 text-[10px] font-bold uppercase #{if property.llm_motivation == "very_motivated", do: "bg-warning text-warning-content", else: "bg-info/20 text-info"}"}>
                        <%= property.llm_motivation %>
                      </span>
                    <% end %>
                    
                    <!-- Urgency -->
                    <%= if property.llm_urgency && property.llm_urgency >= 5 do %>
                      <span class={"px-2 py-0.5 text-[10px] font-bold uppercase #{if property.llm_urgency >= 7, do: "bg-error text-error-content", else: "bg-warning/20 text-warning"}"}>
                        Urgency <%= property.llm_urgency %>/10
                      </span>
                    <% end %>
                    
                    <!-- Positive Signals -->
                    <%= if property.llm_positive_signals && length(property.llm_positive_signals) > 0 do %>
                      <span class="px-2 py-0.5 text-[10px] font-bold bg-success/20 text-success">
                        ✨ <%= length(property.llm_positive_signals) %> positive
                      </span>
                    <% end %>
                    
                    <!-- Red Flags -->
                    <%= if property.llm_red_flags && length(property.llm_red_flags) > 0 do %>
                      <span class="px-2 py-0.5 text-[10px] font-bold bg-error/20 text-error">
                        🚩 <%= length(property.llm_red_flags) %> flags
                      </span>
                    <% end %>
                    
                    <!-- Hidden Costs -->
                    <%= if property.llm_hidden_costs && length(property.llm_hidden_costs) > 0 do %>
                      <span class="px-2 py-0.5 text-[10px] font-bold bg-warning/20 text-warning">
                        💸 <%= length(property.llm_hidden_costs) %> costs
                      </span>
                    <% end %>
                    
                    <!-- Monthly Fee -->
                    <%= if property.llm_monthly_fee do %>
                      <span class="px-2 py-0.5 text-[10px] font-bold bg-base-200">
                        Czynsz: <%= property.llm_monthly_fee %> PLN
                      </span>
                    <% end %>
                  </div>
                  
                  <!-- Analyzed timestamp -->
                  <div class="text-[10px] opacity-40 mt-2">
                    Analyzed: <%= if property.llm_analyzed_at, do: Calendar.strftime(property.llm_analyzed_at, "%Y-%m-%d %H:%M"), else: "?" %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          
          <%= if length(@properties) == 0 do %>
            <div class="bg-base-100 border-2 border-base-content p-8 text-center">
              <div class="text-2xl mb-2">🤖</div>
              <div class="font-bold uppercase">No LLM-analyzed properties found</div>
              <div class="text-sm opacity-60 mt-1">Run LLM Analysis from the Admin panel</div>
            </div>
          <% end %>
        </div>
        
        <!-- Pagination -->
        <%= if @total_pages > 1 do %>
          <div class="mt-4 flex justify-center">
            <div class="flex border-2 border-base-content">
              <button phx-click="prev_page" disabled={@page == 1} class="px-3 py-1.5 text-sm font-bold hover:bg-base-content hover:text-base-100 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer">
                ←
              </button>
              <span class="px-4 py-1.5 text-sm font-bold border-l-2 border-base-content bg-base-content text-base-100">
                <%= @page %>/<%= @total_pages %>
              </span>
              <button phx-click="next_page" disabled={@page == @total_pages} class="px-3 py-1.5 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer">
                →
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    </.app>
    """
  end

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
  def handle_event("sort_changed", %{"value" => sort_by}, socket) do
    {:noreply, socket |> assign(:sort_by, sort_by) |> assign(:page, 1) |> load_properties()}
  end
  
  @impl true
  def handle_event("prev_page", _, socket) do
    {:noreply, socket |> assign(:page, max(1, socket.assigns.page - 1)) |> load_properties()}
  end
  
  @impl true
  def handle_event("next_page", _, socket) do
    {:noreply, socket |> assign(:page, min(socket.assigns.total_pages, socket.assigns.page + 1)) |> load_properties()}
  end

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
    
    # Get total count
    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(1, ceil(total_count / socket.assigns.per_page))
    
    # Apply sorting
    query = case socket.assigns.sort_by do
      "llm_investment_score" -> order_by(query, [p], [desc_nulls_last: p.llm_investment_score, desc: p.llm_analyzed_at])
      "llm_score" -> order_by(query, [p], [desc_nulls_last: p.llm_score, desc: p.llm_analyzed_at])
      "llm_urgency" -> order_by(query, [p], [desc_nulls_last: p.llm_urgency, desc: p.llm_analyzed_at])
      _ -> order_by(query, [p], [desc: p.llm_analyzed_at])
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
    stats = %{
      total_analyzed: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at)),
        :count, :id
      ),
      high_investment: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and p.llm_investment_score >= 8),
        :count, :id
      ),
      motivated_sellers: Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and p.llm_motivation in ["motivated", "very_motivated"]),
        :count, :id
      ),
      avg_score: (Repo.aggregate(
        from(p in Property, where: p.active == true and not is_nil(p.llm_analyzed_at) and not is_nil(p.llm_score)),
        :avg, :llm_score
      ) || Decimal.new(0)) |> Decimal.to_float()
    }
    
    assign(socket, :stats, stats)
  end
  
  # Investment score styling helpers
  defp investment_score_class(score) when is_integer(score) and score >= 8, do: "bg-success/20 border-success"
  defp investment_score_class(score) when is_integer(score) and score >= 5, do: "bg-info/20 border-info"
  defp investment_score_class(score) when is_integer(score) and score >= 3, do: "bg-warning/20 border-warning"
  defp investment_score_class(score) when is_integer(score), do: "bg-error/20 border-error"
  defp investment_score_class(_), do: "bg-base-200 border-base-content/30"
  
  defp investment_score_text_class(score) when is_integer(score) and score >= 8, do: "text-success"
  defp investment_score_text_class(score) when is_integer(score) and score >= 5, do: "text-info"
  defp investment_score_text_class(score) when is_integer(score) and score >= 3, do: "text-warning"
  defp investment_score_text_class(score) when is_integer(score), do: "text-error"
  defp investment_score_text_class(_), do: ""
end

