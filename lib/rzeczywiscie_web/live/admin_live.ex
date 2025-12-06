defmodule RzeczywiscieWeb.FriendsAdminLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Friends

  @photos_per_page 50

  def mount(_params, _session, socket) do
    stats = get_stats()
    photos = list_photos_for_admin(0)
    
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:photos, photos)
     |> assign(:stats, stats)
     |> assign(:page, 0)
     |> assign(:selected_photos, MapSet.new())
     |> assign(:filter, "all")}
  end

  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <div class="min-h-screen bg-base-200 p-4">
        <div class="container mx-auto max-w-6xl">
          <!-- Header -->
          <div class="mb-6">
            <div class="flex items-center justify-between mb-4">
              <h1 class="text-2xl font-black uppercase">🔧 Admin</h1>
              <.link navigate="/friends" class="px-4 py-2 border-2 border-base-content font-bold uppercase text-sm hover:bg-base-content hover:text-base-100 transition-colors">
                ← Back to Friends
              </.link>
            </div>
            
            <!-- Stats -->
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
              <div class="bg-base-100 border-2 border-base-content p-4">
                <div class="text-3xl font-black">{@stats.total_photos}</div>
                <div class="text-sm opacity-60">Total Photos</div>
              </div>
              <div class="bg-base-100 border-2 border-base-content p-4">
                <div class="text-3xl font-black">{@stats.with_thumbnails}</div>
                <div class="text-sm opacity-60">With Thumbnails</div>
              </div>
              <div class="bg-base-100 border-2 border-base-content p-4">
                <div class="text-3xl font-black">{@stats.without_thumbnails}</div>
                <div class="text-sm opacity-60">Without Thumbnails</div>
              </div>
              <div class="bg-base-100 border-2 border-base-content p-4">
                <div class="text-3xl font-black">{format_size(@stats.total_size)}</div>
                <div class="text-sm opacity-60">Total Size</div>
              </div>
            </div>
          </div>

          <!-- Filters -->
          <div class="bg-base-100 border-2 border-base-content p-4 mb-4">
            <div class="flex flex-wrap gap-2 items-center">
              <span class="font-bold text-sm">Filter:</span>
              <button
                type="button"
                phx-click="filter"
                phx-value-filter="all"
                class={["px-3 py-1 border-2 border-base-content text-sm font-bold cursor-pointer", @filter == "all" && "bg-base-content text-base-100"]}
              >All</button>
              <button
                type="button"
                phx-click="filter"
                phx-value-filter="no_thumbnail"
                class={["px-3 py-1 border-2 border-base-content text-sm font-bold cursor-pointer", @filter == "no_thumbnail" && "bg-base-content text-base-100"]}
              >Without Thumbnail ({@stats.without_thumbnails})</button>
              
              <%= if MapSet.size(@selected_photos) > 0 do %>
                <div class="ml-auto flex gap-2">
                  <span class="text-sm opacity-60">{MapSet.size(@selected_photos)} selected</span>
                  <button
                    type="button"
                    phx-click="delete-selected"
                    data-confirm={"Delete #{MapSet.size(@selected_photos)} photos? This cannot be undone."}
                    class="px-3 py-1 border-2 border-error bg-error text-error-content text-sm font-bold cursor-pointer"
                  >Delete Selected</button>
                  <button
                    type="button"
                    phx-click="clear-selection"
                    class="px-3 py-1 border-2 border-base-content text-sm font-bold cursor-pointer"
                  >Clear</button>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Photos Grid -->
          <div class="bg-base-100 border-2 border-base-content p-4">
            <%= if @photos == [] do %>
              <div class="text-center py-8 opacity-50">
                No photos found
              </div>
            <% else %>
              <div class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-2">
                <%= for photo <- @photos do %>
                  <div
                    class={[
                      "relative border-2 cursor-pointer transition-all",
                      if(MapSet.member?(@selected_photos, photo.id), do: "border-primary ring-2 ring-primary", else: "border-base-content/30 hover:border-base-content")
                    ]}
                    phx-click="toggle-select"
                    phx-value-id={photo.id}
                  >
                    <!-- Thumbnail or placeholder -->
                    <div class="aspect-square bg-base-200 overflow-hidden">
                      <%= if photo.has_thumbnail do %>
                        <div class="w-full h-full bg-base-300 flex items-center justify-center text-2xl">✓</div>
                      <% else %>
                        <div class="w-full h-full bg-warning/20 flex items-center justify-center text-2xl">⚠️</div>
                      <% end %>
                    </div>
                    
                    <!-- Info -->
                    <div class="p-1 text-[9px] leading-tight">
                      <div class="font-bold truncate">{photo.user_name || String.slice(photo.user_id, 0, 6)}</div>
                      <div class="opacity-50">{format_size(photo.file_size)}</div>
                      <div class="opacity-50">{format_date(photo.inserted_at)}</div>
                    </div>
                    
                    <!-- Selection indicator -->
                    <%= if MapSet.member?(@selected_photos, photo.id) do %>
                      <div class="absolute top-1 right-1 w-5 h-5 bg-primary text-primary-content rounded-full flex items-center justify-center text-xs font-bold">✓</div>
                    <% end %>
                    
                    <!-- Delete button -->
                    <button
                      type="button"
                      phx-click="delete-photo"
                      phx-value-id={photo.id}
                      data-confirm="Delete this photo?"
                      class="absolute top-1 left-1 w-5 h-5 bg-error text-error-content rounded-full flex items-center justify-center text-xs font-bold opacity-0 hover:opacity-100 transition-opacity cursor-pointer"
                    >✕</button>
                  </div>
                <% end %>
              </div>
              
              <!-- Pagination -->
              <div class="flex justify-center gap-2 mt-4">
                <%= if @page > 0 do %>
                  <button
                    type="button"
                    phx-click="prev-page"
                    class="px-4 py-2 border-2 border-base-content font-bold text-sm cursor-pointer hover:bg-base-content hover:text-base-100"
                  >← Previous</button>
                <% end %>
                
                <span class="px-4 py-2 text-sm opacity-60">Page {@page + 1}</span>
                
                <%= if length(@photos) == @photos_per_page do %>
                  <button
                    type="button"
                    phx-click="next-page"
                    class="px-4 py-2 border-2 border-base-content font-bold text-sm cursor-pointer hover:bg-base-content hover:text-base-100"
                  >Next →</button>
                <% end %>
              </div>
            <% end %>
          </div>
          
          <!-- Danger Zone -->
          <div class="mt-6 bg-error/10 border-2 border-error p-4">
            <h2 class="font-black uppercase text-error mb-4">⚠️ Danger Zone</h2>
            <div class="flex flex-wrap gap-4">
              <button
                type="button"
                phx-click="delete-all-without-thumbnails"
                data-confirm={"Delete ALL #{@stats.without_thumbnails} photos without thumbnails? This cannot be undone!"}
                class="px-4 py-2 border-2 border-error bg-error text-error-content font-bold uppercase text-sm cursor-pointer"
              >
                Delete All Without Thumbnails ({@stats.without_thumbnails})
              </button>
            </div>
          </div>
        </div>
      </div>
    </.app>
    """
  end

  # Events
  
  def handle_event("filter", %{"filter" => filter}, socket) do
    photos = list_photos_for_admin(0, filter)
    {:noreply,
     socket
     |> assign(:photos, photos)
     |> assign(:filter, filter)
     |> assign(:page, 0)
     |> assign(:selected_photos, MapSet.new())}
  end

  def handle_event("prev-page", _params, socket) do
    page = max(0, socket.assigns.page - 1)
    photos = list_photos_for_admin(page, socket.assigns.filter)
    {:noreply, socket |> assign(:photos, photos) |> assign(:page, page)}
  end

  def handle_event("next-page", _params, socket) do
    page = socket.assigns.page + 1
    photos = list_photos_for_admin(page, socket.assigns.filter)
    {:noreply, socket |> assign(:photos, photos) |> assign(:page, page)}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)
    selected = socket.assigns.selected_photos
    
    new_selected = if MapSet.member?(selected, photo_id) do
      MapSet.delete(selected, photo_id)
    else
      MapSet.put(selected, photo_id)
    end
    
    {:noreply, assign(socket, :selected_photos, new_selected)}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selected_photos, MapSet.new())}
  end

  def handle_event("delete-photo", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)
    Friends.admin_delete_photo(photo_id)
    
    photos = list_photos_for_admin(socket.assigns.page, socket.assigns.filter)
    stats = get_stats()
    
    {:noreply,
     socket
     |> assign(:photos, photos)
     |> assign(:stats, stats)
     |> assign(:selected_photos, MapSet.delete(socket.assigns.selected_photos, photo_id))
     |> put_flash(:info, "Photo deleted")}
  end

  def handle_event("delete-selected", _params, socket) do
    selected = socket.assigns.selected_photos
    
    Enum.each(selected, fn photo_id ->
      Friends.admin_delete_photo(photo_id)
    end)
    
    photos = list_photos_for_admin(socket.assigns.page, socket.assigns.filter)
    stats = get_stats()
    
    {:noreply,
     socket
     |> assign(:photos, photos)
     |> assign(:stats, stats)
     |> assign(:selected_photos, MapSet.new())
     |> put_flash(:info, "#{MapSet.size(selected)} photos deleted")}
  end

  def handle_event("delete-all-without-thumbnails", _params, socket) do
    count = Friends.admin_delete_photos_without_thumbnails()
    
    photos = list_photos_for_admin(0, socket.assigns.filter)
    stats = get_stats()
    
    {:noreply,
     socket
     |> assign(:photos, photos)
     |> assign(:stats, stats)
     |> assign(:page, 0)
     |> assign(:selected_photos, MapSet.new())
     |> put_flash(:info, "#{count} photos deleted")}
  end

  # Helpers

  defp list_photos_for_admin(page, filter \\ "all") do
    Friends.admin_list_photos(page * @photos_per_page, @photos_per_page, filter)
  end

  defp get_stats do
    Friends.admin_get_photo_stats()
  end

  defp format_size(nil), do: "?"
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_date(nil), do: ""
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end

  defp photos_per_page, do: @photos_per_page
end
