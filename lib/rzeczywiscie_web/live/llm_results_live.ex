defmodule RzeczywiscieWeb.LLMResultsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  import Ecto.Query
  
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.RealEstate.Property

  @impl true
  def mount(_params, _session, socket) do
    districts = load_districts()
    cities = load_cities()
    property_types = load_property_types()
    
    socket =
      socket
      |> assign(:sort_by, "llm_investment_score")
      |> assign(:sort_dir, "desc")
      # Basic filters
      |> assign(:filter_investment, nil)
      |> assign(:filter_motivation, nil)
      |> assign(:filter_condition, nil)
      # Advanced filters
      |> assign(:filter_district, nil)
      |> assign(:filter_city, nil)
      |> assign(:filter_price_min, nil)
      |> assign(:filter_price_max, nil)
      |> assign(:filter_area_min, nil)
      |> assign(:filter_area_max, nil)
      |> assign(:filter_transaction, nil)
      |> assign(:filter_source, nil)
      |> assign(:filter_property_type, nil)
      |> assign(:filter_urgency, nil)
      |> assign(:filter_has_red_flags, nil)
      |> assign(:filter_has_positive, nil)
      |> assign(:search_query, nil)
      |> assign(:show_advanced, false)
      # Dropdown options
      |> assign(:districts, districts)
      |> assign(:cities, cities)
      |> assign(:property_types, property_types)
      # Pagination
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
                  <option value="price_per_sqm_asc" selected={@sort_by == "price_per_sqm_asc"}>📐 zł/m² ↑</option>
                  <option value="price_per_sqm_desc" selected={@sort_by == "price_per_sqm_desc"}>📐 zł/m² ↓</option>
                  <option value="llm_analyzed_at" selected={@sort_by == "llm_analyzed_at"}>🕐 Newest</option>
                </select>
              </form>
            </div>
            
            <!-- Advanced Toggle -->
            <button phx-click="toggle_advanced" class={"px-3 py-2 text-[10px] md:text-xs font-bold border-l border-base-content/30 transition-colors cursor-pointer #{if @show_advanced, do: "bg-primary text-primary-content", else: "hover:bg-base-200"}"}>
              ⚙️ <span class="hidden sm:inline">More</span>
            </button>
          </div>
          
          <!-- Row 2: Advanced Filters (collapsible) -->
          <%= if @show_advanced do %>
            <div class="border-b border-base-content/30 bg-base-200/30">
              <form phx-change="advanced_filter" class="p-3">
                <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
                  <!-- Search -->
                  <div class="col-span-2">
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Search title</label>
                    <input 
                      type="text" 
                      name="search_query" 
                      value={@search_query || ""} 
                      placeholder="Search..."
                      phx-debounce="300"
                      class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                    />
                  </div>
                  
                  <!-- District -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">District</label>
                    <select name="filter_district" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">All districts</option>
                      <%= for district <- @districts do %>
                        <option value={district} selected={@filter_district == district}><%= district %></option>
                      <% end %>
                    </select>
                  </div>
                  
                  <!-- City -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">City</label>
                    <select name="filter_city" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">All cities</option>
                      <%= for city <- @cities do %>
                        <option value={city} selected={@filter_city == city}><%= city %></option>
                      <% end %>
                    </select>
                  </div>
                  
                  <!-- Transaction -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Transaction</label>
                    <select name="filter_transaction" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">All</option>
                      <option value="sprzedaż" selected={@filter_transaction == "sprzedaż"}>🏷️ Sale</option>
                      <option value="wynajem" selected={@filter_transaction == "wynajem"}>🔑 Rent</option>
                    </select>
                  </div>
                  
                  <!-- Property Type -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Property</label>
                    <select name="filter_property_type" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">All types</option>
                      <%= for ptype <- @property_types do %>
                        <option value={ptype} selected={@filter_property_type == ptype}><%= property_type_label(ptype) %></option>
                      <% end %>
                    </select>
                  </div>
                  
                  <!-- Source -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Source</label>
                    <select name="filter_source" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">All sources</option>
                      <option value="otodom" selected={@filter_source == "otodom"}>Otodom</option>
                      <option value="olx" selected={@filter_source == "olx"}>OLX</option>
                    </select>
                  </div>
                  
                  <!-- Price Range -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Price min (zł)</label>
                    <input 
                      type="number" 
                      name="filter_price_min" 
                      value={@filter_price_min || ""} 
                      placeholder="0"
                      phx-debounce="500"
                      class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                    />
                  </div>
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Price max (zł)</label>
                    <input 
                      type="number" 
                      name="filter_price_max" 
                      value={@filter_price_max || ""} 
                      placeholder="∞"
                      phx-debounce="500"
                      class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                    />
                  </div>
                  
                  <!-- Area Range -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Area min (m²)</label>
                    <input 
                      type="number" 
                      name="filter_area_min" 
                      value={@filter_area_min || ""} 
                      placeholder="0"
                      phx-debounce="500"
                      class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                    />
                  </div>
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Area max (m²)</label>
                    <input 
                      type="number" 
                      name="filter_area_max" 
                      value={@filter_area_max || ""} 
                      placeholder="∞"
                      phx-debounce="500"
                      class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none"
                    />
                  </div>
                  
                  <!-- Urgency -->
                  <div>
                    <label class="text-[9px] font-bold uppercase tracking-wide opacity-50 block mb-1">Urgency</label>
                    <select name="filter_urgency" class="w-full px-2 py-1.5 text-xs border-2 border-base-content/30 bg-base-100 focus:border-primary focus:outline-none cursor-pointer">
                      <option value="">Any urgency</option>
                      <option value="7" selected={@filter_urgency == 7}>⚡ 7+ Hot</option>
                      <option value="5" selected={@filter_urgency == 5}>⚡ 5+ Medium</option>
                    </select>
                  </div>
                  
                  <!-- Signal filters -->
                  <div class="col-span-2 flex items-end gap-3">
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input 
                        type="checkbox" 
                        name="filter_has_red_flags" 
                        value="true"
                        checked={@filter_has_red_flags == true}
                        class="w-4 h-4 accent-error cursor-pointer"
                      />
                      <span class="text-xs font-bold">🚩 Has red flags</span>
                    </label>
                    <label class="flex items-center gap-2 cursor-pointer">
                      <input 
                        type="checkbox" 
                        name="filter_has_positive" 
                        value="true"
                        checked={@filter_has_positive == true}
                        class="w-4 h-4 accent-success cursor-pointer"
                      />
                      <span class="text-xs font-bold">✨ Has positives</span>
                    </label>
                  </div>
                </div>
              </form>
            </div>
          <% end %>

          <!-- Row 3: Active Filters Summary -->
          <%= if has_active_filters?(assigns) do %>
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
              <%= if @filter_district do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-accent text-accent-content">
                  📍 <%= @filter_district %>
                  <button phx-click="clear_filter" phx-value-filter="district" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_city do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-secondary text-secondary-content">
                  🏙️ <%= @filter_city %>
                  <button phx-click="clear_filter" phx-value-filter="city" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_transaction do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-base-300">
                  <%= if @filter_transaction == "sprzedaż", do: "🏷️ Sale", else: "🔑 Rent" %>
                  <button phx-click="clear_filter" phx-value-filter="transaction" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_source do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-base-300">
                  <%= @filter_source %>
                  <button phx-click="clear_filter" phx-value-filter="source" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_property_type do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-primary/30">
                  🏠 <%= property_type_label(@filter_property_type) %>
                  <button phx-click="clear_filter" phx-value-filter="property_type" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_price_min || @filter_price_max do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-success/30">
                  💰 <%= @filter_price_min || 0 %>-<%= @filter_price_max || "∞" %> zł
                  <button phx-click="clear_filter" phx-value-filter="price" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_area_min || @filter_area_max do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-info/30">
                  📐 <%= @filter_area_min || 0 %>-<%= @filter_area_max || "∞" %> m²
                  <button phx-click="clear_filter" phx-value-filter="area" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_urgency do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-error/30">
                  ⚡ <%= @filter_urgency %>+
                  <button phx-click="clear_filter" phx-value-filter="urgency" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_has_red_flags do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-error/30">
                  🚩 Red flags
                  <button phx-click="clear_filter" phx-value-filter="red_flags" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @filter_has_positive do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-success/30">
                  ✨ Positives
                  <button phx-click="clear_filter" phx-value-filter="positive" class="hover:opacity-70 cursor-pointer">×</button>
                </span>
              <% end %>
              <%= if @search_query && @search_query != "" do %>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold bg-base-300">
                  🔍 "<%= String.slice(@search_query, 0, 15) %><%= if String.length(@search_query) > 15, do: "..." %>"
                  <button phx-click="clear_filter" phx-value-filter="search" class="hover:opacity-70 cursor-pointer">×</button>
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
            <div class={"bg-base-100 border-2 transition-colors hover:shadow-lg overflow-hidden min-w-0 #{border_class(property.llm_investment_score)}"}>
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
                <div class="flex-1 p-3 min-w-0 overflow-hidden">
                  <!-- Title -->
                  <a href={property.url} target="_blank" class="group block">
                    <h3 class="font-bold text-sm leading-tight line-clamp-2 break-words group-hover:text-primary transition-colors">
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
                    <div class="mt-2 p-2 bg-gradient-to-r from-info/10 to-transparent border-l-2 border-info text-xs leading-relaxed line-clamp-2 overflow-hidden break-words">
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
  def handle_event("toggle_advanced", _, socket) do
    {:noreply, assign(socket, :show_advanced, !socket.assigns.show_advanced)}
  end

  @impl true
  def handle_event("advanced_filter", params, socket) do
    socket =
      socket
      |> assign(:search_query, parse_string(params["search_query"]))
      |> assign(:filter_district, parse_string(params["filter_district"]))
      |> assign(:filter_city, parse_string(params["filter_city"]))
      |> assign(:filter_transaction, parse_string(params["filter_transaction"]))
      |> assign(:filter_source, parse_string(params["filter_source"]))
      |> assign(:filter_property_type, parse_string(params["filter_property_type"]))
      |> assign(:filter_price_min, parse_number(params["filter_price_min"]))
      |> assign(:filter_price_max, parse_number(params["filter_price_max"]))
      |> assign(:filter_area_min, parse_number(params["filter_area_min"]))
      |> assign(:filter_area_max, parse_number(params["filter_area_max"]))
      |> assign(:filter_urgency, parse_number(params["filter_urgency"]))
      |> assign(:filter_has_red_flags, params["filter_has_red_flags"] == "true")
      |> assign(:filter_has_positive, params["filter_has_positive"] == "true")
      |> assign(:page, 1)
      |> load_properties()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filter", %{"filter" => filter}, socket) do
    socket = case filter do
      "district" -> assign(socket, :filter_district, nil)
      "city" -> assign(socket, :filter_city, nil)
      "transaction" -> assign(socket, :filter_transaction, nil)
      "source" -> assign(socket, :filter_source, nil)
      "property_type" -> assign(socket, :filter_property_type, nil)
      "price" -> socket |> assign(:filter_price_min, nil) |> assign(:filter_price_max, nil)
      "area" -> socket |> assign(:filter_area_min, nil) |> assign(:filter_area_max, nil)
      "urgency" -> assign(socket, :filter_urgency, nil)
      "red_flags" -> assign(socket, :filter_has_red_flags, nil)
      "positive" -> assign(socket, :filter_has_positive, nil)
      "search" -> assign(socket, :search_query, nil)
      _ -> socket
    end
    
    {:noreply, socket |> assign(:page, 1) |> load_properties()}
  end

  @impl true
  def handle_event("clear_filters", _, socket) do
    {:noreply, 
      socket 
      |> assign(:filter_investment, nil) 
      |> assign(:filter_motivation, nil) 
      |> assign(:filter_condition, nil)
      |> assign(:filter_district, nil)
      |> assign(:filter_city, nil)
      |> assign(:filter_transaction, nil)
      |> assign(:filter_source, nil)
      |> assign(:filter_property_type, nil)
      |> assign(:filter_price_min, nil)
      |> assign(:filter_price_max, nil)
      |> assign(:filter_area_min, nil)
      |> assign(:filter_area_max, nil)
      |> assign(:filter_urgency, nil)
      |> assign(:filter_has_red_flags, nil)
      |> assign(:filter_has_positive, nil)
      |> assign(:search_query, nil)
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
    
    # Apply district filter
    query = case socket.assigns.filter_district do
      nil -> query
      district -> where(query, [p], p.district == ^district)
    end
    
    # Apply city filter
    query = case socket.assigns.filter_city do
      nil -> query
      city -> where(query, [p], p.city == ^city)
    end
    
    # Apply transaction type filter
    query = case socket.assigns.filter_transaction do
      nil -> query
      transaction -> where(query, [p], p.transaction_type == ^transaction)
    end
    
    # Apply source filter
    query = case socket.assigns.filter_source do
      nil -> query
      source -> where(query, [p], p.source == ^source)
    end
    
    # Apply property type filter
    query = case socket.assigns.filter_property_type do
      nil -> query
      ptype -> where(query, [p], p.property_type == ^ptype)
    end
    
    # Apply price range filters
    query = case socket.assigns.filter_price_min do
      nil -> query
      min -> where(query, [p], p.price >= ^Decimal.new(min))
    end
    
    query = case socket.assigns.filter_price_max do
      nil -> query
      max -> where(query, [p], p.price <= ^Decimal.new(max))
    end
    
    # Apply area range filters
    query = case socket.assigns.filter_area_min do
      nil -> query
      min -> where(query, [p], p.area_sqm >= ^Decimal.new(min))
    end
    
    query = case socket.assigns.filter_area_max do
      nil -> query
      max -> where(query, [p], p.area_sqm <= ^Decimal.new(max))
    end
    
    # Apply urgency filter
    query = case socket.assigns.filter_urgency do
      nil -> query
      urgency -> where(query, [p], p.llm_urgency >= ^urgency)
    end
    
    # Apply red flags filter
    query = if socket.assigns.filter_has_red_flags do
      where(query, [p], fragment("array_length(?, 1) > 0", p.llm_red_flags))
    else
      query
    end
    
    # Apply positive signals filter
    query = if socket.assigns.filter_has_positive do
      where(query, [p], fragment("array_length(?, 1) > 0", p.llm_positive_signals))
    else
      query
    end
    
    # Apply search query
    query = case socket.assigns.search_query do
      nil -> query
      "" -> query
      search -> 
        search_term = "%#{search}%"
        where(query, [p], ilike(p.title, ^search_term) or ilike(p.llm_summary, ^search_term))
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
      "price_per_sqm_asc" -> order_by(query, [p], [asc_nulls_last: fragment("CASE WHEN ? > 0 THEN ? / ? ELSE NULL END", p.area_sqm, p.price, p.area_sqm)])
      "price_per_sqm_desc" -> order_by(query, [p], [desc_nulls_last: fragment("CASE WHEN ? > 0 THEN ? / ? ELSE NULL END", p.area_sqm, p.price, p.area_sqm)])
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
  
  # Data Loading Helpers
  
  defp load_districts do
    from(p in Property, 
      where: p.active == true and not is_nil(p.llm_analyzed_at) and not is_nil(p.district) and p.district != "",
      select: p.district,
      distinct: true,
      order_by: p.district
    )
    |> Repo.all()
  end
  
  defp load_cities do
    from(p in Property, 
      where: p.active == true and not is_nil(p.llm_analyzed_at) and not is_nil(p.city) and p.city != "",
      select: p.city,
      distinct: true,
      order_by: p.city
    )
    |> Repo.all()
  end
  
  defp load_property_types do
    from(p in Property, 
      where: p.active == true and not is_nil(p.llm_analyzed_at) and not is_nil(p.property_type) and p.property_type != "",
      select: p.property_type,
      distinct: true,
      order_by: p.property_type
    )
    |> Repo.all()
  end
  
  defp property_type_label("mieszkanie"), do: "🏢 Mieszkanie"
  defp property_type_label("dom"), do: "🏠 Dom"
  defp property_type_label("pokój"), do: "🛏️ Pokój"
  defp property_type_label("działka"), do: "🌳 Działka"
  defp property_type_label("garaż"), do: "🚗 Garaż"
  defp property_type_label("lokal"), do: "🏪 Lokal"
  defp property_type_label("biuro"), do: "💼 Biuro"
  defp property_type_label("magazyn"), do: "📦 Magazyn"
  defp property_type_label("hala"), do: "🏭 Hala"
  defp property_type_label(other), do: other
  
  # Parsing Helpers
  
  defp parse_string(nil), do: nil
  defp parse_string(""), do: nil
  defp parse_string(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      s -> s
    end
  end
  
  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil
  defp parse_number(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end
  defp parse_number(num) when is_integer(num), do: num
  
  # Filter state helper
  
  defp has_active_filters?(assigns) do
    assigns.filter_investment || 
    assigns.filter_motivation || 
    assigns.filter_condition ||
    assigns.filter_district ||
    assigns.filter_city ||
    assigns.filter_transaction ||
    assigns.filter_source ||
    assigns.filter_property_type ||
    assigns.filter_price_min ||
    assigns.filter_price_max ||
    assigns.filter_area_min ||
    assigns.filter_area_max ||
    assigns.filter_urgency ||
    assigns.filter_has_red_flags ||
    assigns.filter_has_positive ||
    (assigns.search_query && assigns.search_query != "")
  end
end
