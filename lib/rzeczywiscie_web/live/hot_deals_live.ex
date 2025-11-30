defmodule RzeczywiscieWeb.HotDealsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  require Logger
  alias Rzeczywiscie.RealEstate.DealScorer

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> assign(:transaction_type, nil)
      |> assign(:property_type, nil)
      |> assign(:min_score, 15)
      |> assign(:hot_deals, [])
      |> assign(:price_drops, [])
      |> assign(:summary, %{recent_price_drops: 0, total_active_with_price: 0})
      |> assign(:last_updated, nil)

    # Load data async
    if connected?(socket) do
      send(self(), :load_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_data, socket) do
    hot_deals = DealScorer.get_hot_deals(
      limit: 30,
      transaction_type: socket.assigns.transaction_type,
      property_type: socket.assigns.property_type,
      min_score: socket.assigns.min_score
    )
    
    price_drops = DealScorer.get_price_drops(7, 15)
    summary = DealScorer.get_hot_deals_summary()
    
    {:noreply, 
      socket 
      |> assign(:loading, false)
      |> assign(:hot_deals, hot_deals)
      |> assign(:price_drops, price_drops)
      |> assign(:summary, summary)
      |> assign(:last_updated, DateTime.utc_now())
    }
  end

  @impl true
  def handle_event("filter_transaction", %{"type" => type}, socket) do
    type = if type == "all", do: nil, else: type
    
    socket = 
      socket 
      |> assign(:transaction_type, type)
      |> assign(:loading, true)
    
    send(self(), :load_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_property", %{"type" => type}, socket) do
    type = if type == "all", do: nil, else: type
    
    socket = 
      socket 
      |> assign(:property_type, type)
      |> assign(:loading, true)
    
    send(self(), :load_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_min_score", %{"score" => score}, socket) do
    {score, _} = Integer.parse(score)
    
    socket = 
      socket 
      |> assign(:min_score, score)
      |> assign(:loading, true)
    
    send(self(), :load_data)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("refresh", _params, socket) do
    socket = assign(socket, :loading, true)
    send(self(), :load_data)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
    <div class="min-h-screen bg-base-200">
      <!-- Header -->
      <.property_page_header current_path={@current_path} title="🔥 Hot Deals" subtitle="AI-scored property opportunities">
        <:actions>
          <div class="flex items-center gap-3">
            <%= if @last_updated do %>
              <span class="text-xs opacity-50">
                Updated <%= format_time_ago(@last_updated) %>
              </span>
            <% end %>
            <button
              phx-click="refresh"
              disabled={@loading}
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer"
            >
              <%= if @loading, do: "Loading...", else: "🔄 Refresh" %>
            </button>
          </div>
        </:actions>
      </.property_page_header>
      
      <div class="container mx-auto px-4 py-6">
        <!-- Summary Cards -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <div class="bg-base-100 border-2 border-base-content p-4">
            <div class="text-3xl font-black text-warning"><%= @summary.recent_price_drops %></div>
            <div class="text-xs font-bold uppercase tracking-wide opacity-60">Price Drops (7d)</div>
          </div>
          <div class="bg-base-100 border-2 border-base-content p-4">
            <div class="text-3xl font-black text-success"><%= length(@hot_deals) %></div>
            <div class="text-xs font-bold uppercase tracking-wide opacity-60">Hot Deals Found</div>
          </div>
          <div class="bg-base-100 border-2 border-base-content p-4">
            <div class="text-3xl font-black"><%= @summary.total_active_with_price %></div>
            <div class="text-xs font-bold uppercase tracking-wide opacity-60">Total Analyzed</div>
          </div>
          <div class="bg-base-100 border-2 border-base-content p-4">
            <div class="text-3xl font-black text-info"><%= @min_score %>+</div>
            <div class="text-xs font-bold uppercase tracking-wide opacity-60">Min Score Filter</div>
          </div>
        </div>
        
        <!-- Filters -->
        <div class="bg-base-100 border-2 border-base-content p-4 mb-6">
          <div class="flex flex-wrap gap-4 items-center">
            <div>
              <span class="text-xs font-bold uppercase tracking-wide opacity-60 mr-2">Transaction:</span>
              <div class="inline-flex gap-1">
                <button 
                  phx-click="filter_transaction" 
                  phx-value-type="all"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @transaction_type == nil, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >All</button>
                <button 
                  phx-click="filter_transaction" 
                  phx-value-type="sprzedaż"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @transaction_type == "sprzedaż", do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >Sale</button>
                <button 
                  phx-click="filter_transaction" 
                  phx-value-type="wynajem"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @transaction_type == "wynajem", do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >Rent</button>
              </div>
            </div>
            
            <div>
              <span class="text-xs font-bold uppercase tracking-wide opacity-60 mr-2">Property:</span>
              <div class="inline-flex gap-1">
                <button 
                  phx-click="filter_property" 
                  phx-value-type="all"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @property_type == nil, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >All</button>
                <button 
                  phx-click="filter_property" 
                  phx-value-type="mieszkanie"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @property_type == "mieszkanie", do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >Mieszkanie</button>
                <button 
                  phx-click="filter_property" 
                  phx-value-type="dom"
                  class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @property_type == "dom", do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                >Dom</button>
              </div>
            </div>
            
            <div>
              <span class="text-xs font-bold uppercase tracking-wide opacity-60 mr-2">Min Score:</span>
              <div class="inline-flex gap-1">
                <%= for score <- [10, 15, 20, 25, 30] do %>
                  <button 
                    phx-click="set_min_score" 
                    phx-value-score={score}
                    class={"px-2 py-1 text-xs font-bold border transition-colors cursor-pointer #{if @min_score == score, do: "bg-accent text-accent-content border-accent", else: "border-base-content/30 hover:bg-base-200"}"}
                  ><%= score %>+</button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        
        <%= if @loading do %>
          <div class="flex items-center justify-center py-20">
            <div class="text-center">
              <div class="text-4xl animate-pulse mb-2">🔍</div>
              <div class="text-sm font-bold uppercase tracking-wide opacity-60">Analyzing properties...</div>
            </div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- Hot Deals List -->
            <div class="lg:col-span-2">
              <div class="bg-base-100 border-2 border-base-content">
                <div class="px-4 py-3 border-b-2 border-base-content bg-warning/10">
                  <h2 class="text-sm font-black uppercase tracking-wide flex items-center gap-2">
                    🔥 Top Scored Deals
                    <span class="text-xs font-normal opacity-60">(<%= length(@hot_deals) %> found)</span>
                  </h2>
                </div>
                
                <%= if @hot_deals == [] do %>
                  <div class="p-8 text-center opacity-60">
                    <div class="text-4xl mb-2">📭</div>
                    <div class="text-sm">No deals match current filters</div>
                  </div>
                <% else %>
                  <div class="divide-y-2 divide-base-content/10">
                    <%= for {property, score_data} <- @hot_deals do %>
                      <div class="p-4 hover:bg-base-200/50 transition-colors">
                        <div class="flex gap-4">
                          <!-- Score Badge -->
                          <div class="flex-shrink-0">
                            <div class={"w-16 h-16 flex items-center justify-center text-2xl font-black rounded border-2 #{score_badge_class(score_data.total_score)}"}>
                              <%= score_data.total_score %>
                            </div>
                          </div>
                          
                          <!-- Property Info -->
                          <div class="flex-1 min-w-0">
                            <a href={property.url} target="_blank" class="font-bold text-sm hover:text-primary transition-colors line-clamp-1">
                              <%= property.title %>
                            </a>
                            
                            <div class="flex flex-wrap gap-2 mt-1 text-xs">
                              <span class="font-black text-success"><%= format_price(property.price) %> zł</span>
                              <%= if property.area_sqm do %>
                                <span class="opacity-60"><%= format_area(property.area_sqm) %> m²</span>
                              <% end %>
                              <%= if property.rooms do %>
                                <span class="opacity-60"><%= property.rooms %> pok.</span>
                              <% end %>
                              <%= if property.district do %>
                                <span class="opacity-60"><%= property.district %></span>
                              <% end %>
                              <%= if property.description && String.length(property.description || "") > 50 do %>
                                <span class="text-info">📝 Has description</span>
                              <% end %>
                            </div>
                            
                            <!-- Description Preview (if available) -->
                            <%= if property.description && String.length(property.description || "") > 50 do %>
                              <details class="mt-2">
                                <summary class="text-xs cursor-pointer text-info hover:text-info/80 select-none">
                                  📖 Show description (<%= String.length(property.description) %> chars)
                                </summary>
                                <div class="mt-2 p-3 bg-base-200 text-xs leading-relaxed max-h-48 overflow-y-auto">
                                  <%= String.slice(property.description, 0, 1000) %><%= if String.length(property.description) > 1000, do: "..." %>
                                </div>
                              </details>
                            <% end %>
                            
                            <!-- Score Breakdown -->
                            <div class="flex flex-wrap gap-1 mt-2">
                              <%= if score_data.scores.price_vs_avg > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-success/20 text-success border border-success/30">
                                  📉 Price -<%= score_data.scores.price_vs_avg %>pts
                                </span>
                              <% end %>
                              <%= if score_data.scores.price_per_sqm > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-info/20 text-info border border-info/30">
                                  📐 Value +<%= score_data.scores.price_per_sqm %>pts
                                </span>
                              <% end %>
                              <%= if score_data.scores.price_drop > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-warning/20 text-warning border border-warning/30">
                                  🔻 Drop +<%= score_data.scores.price_drop %>pts
                                </span>
                              <% end %>
                              <%= if score_data.scores.urgency_keywords > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-error/20 text-error border border-error/30">
                                  ⚡ Urgent +<%= score_data.scores.urgency_keywords %>pts
                                </span>
                              <% end %>
                              <%= if score_data.scores.days_on_market > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-base-300 opacity-60">
                                  📅 Long listing +<%= score_data.scores.days_on_market %>pts
                                </span>
                              <% end %>
                              <%= if score_data.scores.district_quality && score_data.scores.district_quality > 0 do %>
                                <span class="px-1.5 py-0.5 text-xs bg-accent/20 text-accent border border-accent/30">
                                  📍 District +<%= score_data.scores.district_quality %>pts
                                </span>
                              <% end %>
                            </div>
                            
                            <!-- Market Context: Avg for same property type in same district -->
                            <%= if score_data.market_context && score_data.market_context.avg_price do %>
                              <div class="mt-2 flex items-center gap-2 text-xs">
                                <%= if score_data[:district_info] && score_data.district_info do %>
                                  <span class={"px-2 py-0.5 font-bold rounded #{district_grade_class(score_data.district_info.grade)}"}>
                                    <%= score_data.district_info.grade %>
                                  </span>
                                <% end %>
                                <span class="opacity-60">
                                  Avg in <%= property.district || "area" %>: <%= format_price(score_data.market_context.avg_price) %> zł
                                  <%= if score_data.market_context.avg_price_per_sqm do %>
                                    (<%= format_number(score_data.market_context.avg_price_per_sqm) %> zł/m²)
                                  <% end %>
                                </span>
                              </div>
                            <% end %>
                          </div>
                          
                          <!-- Source -->
                          <div class="flex-shrink-0 text-right">
                            <div class={"px-2 py-1 text-xs font-bold uppercase #{source_class(property.source)}"}>
                              <%= property.source %>
                            </div>
                            <div class="text-xs opacity-40 mt-1">
                              <%= format_date(property.inserted_at) %>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
            
            <!-- Sidebar - Price Drops -->
            <div>
              <div class="bg-base-100 border-2 border-base-content">
                <div class="px-4 py-3 border-b-2 border-base-content bg-error/10">
                  <h2 class="text-sm font-black uppercase tracking-wide flex items-center gap-2">
                    🔻 Recent Price Drops
                  </h2>
                </div>
                
                <%= if @price_drops == [] do %>
                  <div class="p-6 text-center opacity-60">
                    <div class="text-2xl mb-1">📊</div>
                    <div class="text-xs">No price drops in last 7 days</div>
                    <div class="text-xs opacity-50 mt-1">Price tracking is active</div>
                  </div>
                <% else %>
                  <div class="divide-y divide-base-content/10">
                    <%= for {property, history} <- @price_drops do %>
                      <a href={property.url} target="_blank" class="block p-3 hover:bg-base-200/50 transition-colors">
                        <div class="flex items-start gap-2">
                          <div class="flex-shrink-0 px-2 py-1 text-xs font-black bg-error/20 text-error border border-error/30">
                            <%= format_percentage(history.change_percentage) %>%
                          </div>
                          <div class="flex-1 min-w-0">
                            <div class="text-xs font-bold line-clamp-1"><%= property.title %></div>
                            <div class="text-xs opacity-60 mt-0.5">
                              <%= format_price(property.price) %> zł
                              <%= if property.district do %>
                                · <%= property.district %>
                              <% end %>
                            </div>
                          </div>
                        </div>
                      </a>
                    <% end %>
                  </div>
                <% end %>
              </div>
              
              <!-- Scoring Legend -->
              <div class="bg-base-100 border-2 border-base-content mt-4">
                <div class="px-4 py-3 border-b-2 border-base-content">
                  <h2 class="text-sm font-black uppercase tracking-wide">📊 Score Breakdown</h2>
                </div>
                <div class="p-4 text-xs space-y-2">
                  <div class="flex justify-between">
                    <span>📉 Below market price</span>
                    <span class="font-bold">0-30 pts</span>
                  </div>
                  <div class="flex justify-between">
                    <span>📐 Low price/m²</span>
                    <span class="font-bold">0-25 pts</span>
                  </div>
                  <div class="flex justify-between">
                    <span>🔻 Price history trend</span>
                    <span class="font-bold">0-30 pts</span>
                  </div>
                  <div class="text-[10px] opacity-60 pl-4 space-y-0.5">
                    <div>• Multiple drops: 0-10</div>
                    <div>• Total % dropped: 0-15</div>
                    <div>• Recent drop: 0-5</div>
                  </div>
                  <div class="flex justify-between">
                    <span>⚡ Urgency keywords</span>
                    <span class="font-bold">0-10 pts</span>
                  </div>
                  <div class="flex justify-between">
                    <span>📅 Long time listed</span>
                    <span class="font-bold">0-10 pts</span>
                  </div>
                  <div class="flex justify-between">
                    <span>📍 District quality</span>
                    <span class="font-bold">0-15 pts</span>
                  </div>
                  <div class="text-[10px] opacity-60 pl-4 space-y-0.5">
                    <div>• A+/A district below avg: 10-15</div>
                    <div>• B+/B district below avg: 5-10</div>
                    <div>• C+/C significant discount: 0-5</div>
                  </div>
                  <div class="border-t border-base-content/20 pt-2 mt-2 flex justify-between font-bold">
                    <span>Max possible</span>
                    <span>120 pts</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    </.app>
    """
  end

  # Helper functions

  defp format_price(nil), do: "—"
  defp format_price(price) when is_float(price) do
    price
    |> trunc()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end
  defp format_price(%Decimal{} = price), do: format_price(Decimal.to_float(price))
  defp format_price(price) when is_integer(price), do: format_price(price * 1.0)

  defp format_area(nil), do: "—"
  defp format_area(%Decimal{} = area), do: Decimal.to_float(area) |> Float.round(1)
  defp format_area(area), do: area

  defp format_percentage(nil), do: "0"
  defp format_percentage(%Decimal{} = pct), do: Decimal.to_float(pct) |> Float.round(1)
  defp format_percentage(pct) when is_float(pct), do: Float.round(pct, 1)

  defp format_date(nil), do: "—"
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp score_badge_class(score) when score >= 50, do: "bg-warning text-warning-content border-warning"
  defp score_badge_class(score) when score >= 35, do: "bg-success text-success-content border-success"
  defp score_badge_class(score) when score >= 25, do: "bg-info text-info-content border-info"
  defp score_badge_class(_), do: "bg-base-200 border-base-content/30"

  defp format_number(nil), do: "—"
  defp format_number(num) when is_float(num) do
    num
    |> trunc()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end
  defp format_number(num), do: to_string(num)
  
  defp district_grade_class("A+"), do: "bg-yellow-500 text-yellow-900"
  defp district_grade_class("A"), do: "bg-yellow-400 text-yellow-900"
  defp district_grade_class("B+"), do: "bg-green-500 text-green-900"
  defp district_grade_class("B"), do: "bg-green-400 text-green-900"
  defp district_grade_class("C+"), do: "bg-gray-400 text-gray-900"
  defp district_grade_class("C"), do: "bg-gray-300 text-gray-800"
  defp district_grade_class(_), do: "bg-base-300"

  defp source_class("otodom"), do: "bg-blue-500/20 text-blue-600 border border-blue-500/30"
  defp source_class("olx"), do: "bg-green-500/20 text-green-600 border border-green-500/30"
  defp source_class(_), do: "bg-base-200"
  
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

