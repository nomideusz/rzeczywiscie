defmodule RzeczywiscieWeb.FavoritesLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.RealEstate

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user_id = get_or_create_user_id(socket)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:favorites, load_favorites(user_id))
      |> assign(:price_drops, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
    <div class="container mx-auto p-8">
      <!-- Sub-navigation tabs -->
      <div class="mb-6">
        <div class="tabs tabs-boxed bg-base-200 border-2 border-base-content">
          <a href="/real-estate" class="tab font-bold">Properties</a>
          <a href="/favorites" class="tab tab-active font-bold">Favorites</a>
          <a href="/stats" class="tab font-bold">Stats</a>
          <a href="/admin" class="tab font-bold">Admin</a>
        </div>
      </div>

      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold">My Favorites</h1>
          <p class="text-sm opacity-70"><%= length(@favorites) %> saved properties</p>
        </div>
      </div>

      <%= if length(@favorites) == 0 do %>
        <div class="alert alert-info">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <div>
            <h3 class="font-bold">No favorites yet</h3>
            <div class="text-xs">Click the heart icon on any property to add it to your favorites.</div>
          </div>
        </div>
      <% else %>
        <div class="grid grid-cols-1 gap-6">
          <%= for favorite <- @favorites do %>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <div class="flex justify-between items-start">
                  <div class="flex-grow">
                    <h2 class="card-title"><%= favorite.property.title %></h2>
                    <div class="flex gap-4 text-sm mt-2">
                      <span class="badge badge-primary"><%= String.upcase(favorite.property.source) %></span>
                      <%= if favorite.property.transaction_type do %>
                        <span class="badge badge-secondary"><%= favorite.property.transaction_type %></span>
                      <% end %>
                      <%= if favorite.property.property_type do %>
                        <span class="badge badge-ghost"><%= favorite.property.property_type %></span>
                      <% end %>
                    </div>

                    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mt-4">
                      <div>
                        <div class="text-xs opacity-70">Price</div>
                        <div class="font-bold"><%= format_price(favorite.property.price) %></div>
                      </div>
                      <%= if favorite.property.area_sqm do %>
                        <div>
                          <div class="text-xs opacity-70">Area</div>
                          <div class="font-bold"><%= favorite.property.area_sqm %> m²</div>
                        </div>
                      <% end %>
                      <%= if favorite.property.rooms do %>
                        <div>
                          <div class="text-xs opacity-70">Rooms</div>
                          <div class="font-bold"><%= favorite.property.rooms %></div>
                        </div>
                      <% end %>
                      <div>
                        <div class="text-xs opacity-70">Location</div>
                        <div class="font-bold text-sm"><%= favorite.property.city || "N/A" %></div>
                      </div>
                    </div>

                    <%= if favorite.notes do %>
                      <div class="mt-4">
                        <div class="text-xs opacity-70">Notes</div>
                        <div class="text-sm"><%= favorite.notes %></div>
                      </div>
                    <% end %>

                    <div class="text-xs opacity-50 mt-4">
                      Added <%= format_date(favorite.inserted_at) %>
                    </div>
                  </div>

                  <div class="flex flex-col gap-2">
                    <a href={favorite.property.url} target="_blank" class="btn btn-primary btn-sm">
                      View Listing
                    </a>
                    <button
                      phx-click="remove_favorite"
                      phx-value-id={favorite.property.id}
                      class="btn btn-error btn-sm"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
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

  defp load_favorites(user_id) do
    RealEstate.list_favorites(user_id)
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

  defp format_price(nil), do: "N/A"

  defp format_price(price) do
    price
    |> Decimal.to_float()
    |> then(fn p ->
      Number.Currency.number_to_currency(p, unit: "zł", separator: " ", delimiter: " ", format: "%n %u")
    end)
  rescue
    _ ->
      # Fallback if Number library not available
      "#{price} zł"
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
