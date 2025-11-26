defmodule RzeczywiscieWeb.FavoritesLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.RealEstate

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_or_create_user_id(socket)
    favorites = load_favorites(user_id)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:favorites, favorites)
      |> assign(:sort_by, "added")
      |> assign(:editing_notes, nil)

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
            <a href="/favorites" class="px-3 py-2 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100">
              Favorites
            </a>
            <a href="/stats" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Stats
            </a>
            <a href="/admin" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
              Admin
            </a>
          </nav>

          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div>
              <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">Favorites</h1>
              <p class="text-sm font-bold uppercase tracking-wide opacity-60">
                <%= length(@favorites) %> saved properties
              </p>
            </div>

            <%= if length(@favorites) > 0 do %>
              <!-- Sort Options -->
              <div class="flex items-center gap-2">
                <span class="text-[10px] font-bold uppercase tracking-wide opacity-50">Sort:</span>
                <div class="flex border-2 border-base-content">
                  <button
                    phx-click="sort"
                    phx-value-by="added"
                    class={"px-3 py-1 text-xs font-bold transition-colors cursor-pointer #{if @sort_by == "added", do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}
                  >
                    Added
                  </button>
                  <button
                    phx-click="sort"
                    phx-value-by="price_asc"
                    class={"px-3 py-1 text-xs font-bold border-l-2 border-base-content transition-colors cursor-pointer #{if @sort_by == "price_asc", do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}
                  >
                    Price ↑
                  </button>
                  <button
                    phx-click="sort"
                    phx-value-by="price_desc"
                    class={"px-3 py-1 text-xs font-bold border-l-2 border-base-content transition-colors cursor-pointer #{if @sort_by == "price_desc", do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}
                  >
                    Price ↓
                  </button>
                  <button
                    phx-click="sort"
                    phx-value-by="area"
                    class={"px-3 py-1 text-xs font-bold border-l-2 border-base-content transition-colors cursor-pointer #{if @sort_by == "area", do: "bg-base-content text-base-100", else: "hover:bg-base-200"}"}
                  >
                    Area
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Summary Stats -->
      <%= if length(@favorites) > 0 do %>
        <div class="bg-base-100 border-b-2 border-base-content">
          <div class="container mx-auto">
            <div class="grid grid-cols-2 md:grid-cols-4 divide-x-2 divide-base-content">
              <div class="p-3 text-center">
                <div class="text-xl font-black text-primary"><%= length(@favorites) %></div>
                <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total</div>
              </div>
              <div class="p-3 text-center">
                <div class="text-xl font-black text-info"><%= count_by_type(@favorites, "sprzedaż") %></div>
                <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">For Sale</div>
              </div>
              <div class="p-3 text-center">
                <div class="text-xl font-black text-warning"><%= count_by_type(@favorites, "wynajem") %></div>
                <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">For Rent</div>
              </div>
              <div class="p-3 text-center">
                <div class="text-xl font-black text-secondary"><%= format_total_value(@favorites) %></div>
                <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total Value</div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div class="container mx-auto px-4 py-6">
        <%= if length(@favorites) == 0 do %>
          <!-- Empty State -->
          <div class="bg-base-100 border-2 border-base-content p-8 text-center">
            <div class="text-6xl mb-4">💔</div>
            <h3 class="text-xl font-black uppercase tracking-wide mb-2">No favorites yet</h3>
            <p class="text-sm opacity-60 mb-6">Click the heart icon on any property to save it here.</p>
            <a
              href="/real-estate"
              class="inline-block px-6 py-3 text-sm font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Browse Properties
            </a>
          </div>
        <% else %>
          <!-- Favorites List -->
          <div class="space-y-4">
            <%= for favorite <- sort_favorites(@favorites, @sort_by) do %>
              <div class="bg-base-100 border-2 border-base-content hover:border-primary transition-colors">
                <div class="flex">
                  <!-- Image -->
                  <div class="w-32 md:w-48 flex-shrink-0 border-r-2 border-base-content bg-base-300">
                    <%= if favorite.property.image_url do %>
                      <img
                        src={favorite.property.image_url}
                        alt=""
                        class="w-full h-full object-cover"
                        loading="lazy"
                      />
                    <% else %>
                      <div class="w-full h-full min-h-[100px] flex items-center justify-center text-3xl opacity-30">
                        🏠
                      </div>
                    <% end %>
                  </div>

                  <!-- Content -->
                  <div class="flex-1 p-4">
                    <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
                      <!-- Main Info -->
                      <div class="flex-1 min-w-0">
                        <!-- Title & Badges -->
                        <div class="flex flex-wrap items-center gap-2 mb-2">
                          <span class={"px-2 py-0.5 text-[10px] font-bold uppercase #{if favorite.property.source == "olx", do: "bg-primary/20 text-primary", else: "bg-secondary/20 text-secondary"}"}>
                            <%= favorite.property.source %>
                          </span>
                          <%= if favorite.property.transaction_type do %>
                            <span class={"px-2 py-0.5 text-[10px] font-bold #{if favorite.property.transaction_type == "sprzedaż", do: "bg-info/20 text-info", else: "bg-warning/20 text-warning"}"}>
                              <%= favorite.property.transaction_type %>
                            </span>
                          <% end %>
                          <%= if favorite.property.property_type do %>
                            <span class="px-2 py-0.5 text-[10px] font-bold bg-base-200">
                              <%= favorite.property.property_type %>
                            </span>
                          <% end %>
                        </div>

                        <h2 class="font-bold text-lg leading-tight line-clamp-2 mb-2">
                          <%= favorite.property.title %>
                        </h2>

                        <!-- Location -->
                        <div class="text-sm opacity-60 mb-3">
                          <%= favorite.property.city || "—" %><%= if favorite.property.district, do: " · #{favorite.property.district}" %>
                        </div>

                        <!-- Stats Grid -->
                        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
                          <div>
                            <div class="text-[10px] font-bold uppercase tracking-wide opacity-50">Price</div>
                            <div class="font-black text-lg"><%= format_price(favorite.property.price) %></div>
                          </div>
                          <%= if favorite.property.area_sqm do %>
                            <div>
                              <div class="text-[10px] font-bold uppercase tracking-wide opacity-50">Area</div>
                              <div class="font-bold"><%= Decimal.round(favorite.property.area_sqm, 0) %> m²</div>
                            </div>
                          <% end %>
                          <%= if favorite.property.price && favorite.property.area_sqm do %>
                            <div>
                              <div class="text-[10px] font-bold uppercase tracking-wide opacity-50">Price/m²</div>
                              <div class="font-bold text-sm"><%= format_price_per_sqm(favorite.property.price, favorite.property.area_sqm) %></div>
                            </div>
                          <% end %>
                          <%= if favorite.property.rooms do %>
                            <div>
                              <div class="text-[10px] font-bold uppercase tracking-wide opacity-50">Rooms</div>
                              <div class="font-bold"><%= favorite.property.rooms %></div>
                            </div>
                          <% end %>
                        </div>

                        <!-- Notes Section -->
                        <div class="mt-3 pt-3 border-t border-base-content/20">
                          <%= if @editing_notes == favorite.id do %>
                            <form phx-submit="save_notes" class="flex gap-2">
                              <input type="hidden" name="favorite_id" value={favorite.id} />
                              <input
                                type="text"
                                name="notes"
                                value={favorite.notes || ""}
                                placeholder="Add a note..."
                                class="flex-1 px-2 py-1 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                                autofocus
                              />
                              <button type="submit" class="px-3 py-1 text-xs font-bold bg-primary text-primary-content">
                                Save
                              </button>
                              <button type="button" phx-click="cancel_edit" class="px-3 py-1 text-xs font-bold border border-base-content">
                                Cancel
                              </button>
                            </form>
                          <% else %>
                            <div class="flex items-center gap-2">
                              <span class="text-[10px] font-bold uppercase tracking-wide opacity-50">Notes:</span>
                              <%= if favorite.notes do %>
                                <span class="text-sm"><%= favorite.notes %></span>
                              <% else %>
                                <span class="text-sm opacity-40 italic">No notes</span>
                              <% end %>
                              <button
                                phx-click="edit_notes"
                                phx-value-id={favorite.id}
                                class="text-xs opacity-50 hover:opacity-100 cursor-pointer"
                              >
                                ✏️
                              </button>
                            </div>
                          <% end %>
                        </div>

                        <div class="text-[10px] opacity-40 mt-2">
                          Saved <%= format_date(favorite.inserted_at) %>
                        </div>
                      </div>

                      <!-- Actions -->
                      <div class="flex md:flex-col gap-2">
                        <a
                          href={favorite.property.url}
                          target="_blank"
                          rel="noopener"
                          class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors text-center"
                        >
                          View ↗
                        </a>
                        <button
                          phx-click="remove_favorite"
                          phx-value-id={favorite.property.id}
                          class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-error text-error hover:bg-error hover:text-error-content transition-colors cursor-pointer"
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    </.app>
    """
  end

  @impl true
  def handle_event("remove_favorite", %{"id" => property_id}, socket) do
    property_id = String.to_integer(property_id)
    RealEstate.remove_favorite(property_id, socket.assigns.user_id)

    socket =
      socket
      |> assign(:favorites, load_favorites(socket.assigns.user_id))
      |> put_flash(:info, "Removed from favorites")

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_by}, socket) do
    {:noreply, assign(socket, :sort_by, sort_by)}
  end

  @impl true
  def handle_event("edit_notes", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_notes, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_notes, nil)}
  end

  @impl true
  def handle_event("save_notes", %{"favorite_id" => favorite_id, "notes" => notes}, socket) do
    favorite_id = String.to_integer(favorite_id)

    case RealEstate.update_favorite_notes(favorite_id, notes) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:favorites, load_favorites(socket.assigns.user_id))
          |> assign(:editing_notes, nil)
          |> put_flash(:info, "Notes saved")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save notes")}
    end
  end

  defp load_favorites(user_id) do
    RealEstate.list_favorites(user_id)
  end

  defp sort_favorites(favorites, "added"), do: favorites
  defp sort_favorites(favorites, "price_asc") do
    Enum.sort_by(favorites, fn f -> f.property.price || Decimal.new(0) end, Decimal)
  end
  defp sort_favorites(favorites, "price_desc") do
    Enum.sort_by(favorites, fn f -> f.property.price || Decimal.new(0) end, {:desc, Decimal})
  end
  defp sort_favorites(favorites, "area") do
    Enum.sort_by(favorites, fn f -> f.property.area_sqm || Decimal.new(0) end, {:desc, Decimal})
  end
  defp sort_favorites(favorites, _), do: favorites

  defp count_by_type(favorites, type) do
    Enum.count(favorites, fn f -> f.property.transaction_type == type end)
  end

  defp format_total_value(favorites) do
    total = favorites
      |> Enum.filter(fn f -> f.property.transaction_type == "sprzedaż" && f.property.price end)
      |> Enum.reduce(Decimal.new(0), fn f, acc -> Decimal.add(acc, f.property.price) end)

    cond do
      Decimal.compare(total, Decimal.new(1_000_000)) == :gt ->
        "#{Decimal.round(Decimal.div(total, Decimal.new(1_000_000)), 1)}M zł"
      Decimal.compare(total, Decimal.new(1_000)) == :gt ->
        "#{Decimal.round(Decimal.div(total, Decimal.new(1_000)), 0)}K zł"
      true ->
        "#{Decimal.round(total, 0)} zł"
    end
  end

  defp format_price_per_sqm(price, area) do
    if price && area && Decimal.compare(area, Decimal.new(0)) == :gt do
      per_sqm = Decimal.div(price, area) |> Decimal.round(0)
      "#{per_sqm} zł"
    else
      "—"
    end
  end

  defp get_or_create_user_id(socket) do
    # Priority: user_agent (most persistent) > peer IP > fallback
    user_id = get_user_agent_id(socket) || get_peer_ip_id(socket) || get_fallback_id()
    Logger.debug("Favorites page - Generated user_id: #{user_id}")
    user_id
  end

  defp get_user_agent_id(socket) do
    case get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) and byte_size(ua) > 0 ->
        user_id = :crypto.hash(:md5, ua)
          |> Base.encode16()
          |> String.slice(0, 16)
        Logger.debug("Favorites page - Using user_agent ID: #{user_id}")
        user_id
      _ ->
        Logger.debug("Favorites page - No user_agent available")
        nil
    end
  end

  defp get_peer_ip_id(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} when is_tuple(address) ->
        user_id = address
          |> :inet.ntoa()
          |> to_string()
          |> then(&:crypto.hash(:md5, &1))
          |> Base.encode16()
          |> String.slice(0, 16)
        Logger.debug("Favorites page - Using peer IP ID: #{user_id}")
        user_id
      _ ->
        Logger.debug("Favorites page - No peer data available")
        nil
    end
  end

  defp get_fallback_id do
    # Pure random - will NOT persist across sessions
    user_id = :crypto.strong_rand_bytes(8)
      |> Base.encode16()
    Logger.debug("Favorites page - Using fallback random ID: #{user_id}")
    user_id
  end

  defp format_price(nil), do: "—"

  defp format_price(price) do
    rounded = Decimal.round(price, 0) |> Decimal.to_integer()

    cond do
      rounded >= 1_000_000 ->
        "#{Float.round(rounded / 1_000_000, 1)}M zł"
      rounded >= 1_000 ->
        formatted = rounded
          |> Integer.to_string()
          |> String.reverse()
          |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
          |> String.reverse()
        "#{formatted} zł"
      true ->
        "#{rounded} zł"
    end
  rescue
    _ -> "#{price} zł"
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
