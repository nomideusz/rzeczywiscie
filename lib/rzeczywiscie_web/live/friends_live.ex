defmodule RzeczywiscieWeb.FriendsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts

  @topic "friends:photos"
  @max_photos 50

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
    end

    user_id = get_or_create_user_id(socket)
    user_color = generate_user_color(user_id)
    photos = get_photos()

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_color, user_color)
      |> assign(:page_title, "Friends")
      |> assign(:photos, photos)
      |> assign(:online_count, 1)
      |> assign(:uploading, false)
      |> stream(:photos, photos)
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    # Broadcast presence
    if connected?(socket) do
      Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {:user_joined, user_id})
    end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="min-h-screen bg-gradient-to-br from-base-100 via-base-100 to-error/5">
        <!-- Header Section -->
        <div class="border-b-4 border-base-content bg-base-100">
          <div class="container mx-auto px-4 py-8">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
              <div>
                <div class="flex items-center gap-3 mb-2">
                  <div class="w-3 h-3 bg-error rounded-none animate-pulse"></div>
                  <span class="text-xs uppercase tracking-[0.3em] font-bold opacity-70">
                    Live • {@online_count} online
                  </span>
                </div>
                <h1 class="text-4xl md:text-5xl font-black uppercase tracking-tighter">
                  Friends Photos
                </h1>
                <p class="text-sm opacity-70 mt-2 max-w-md">
                  Share photos in real-time. Everyone connected sees new uploads instantly.
                </p>
              </div>

              <!-- Upload Section -->
              <div class="flex-shrink-0">
                <form id="upload-form" phx-submit="save" phx-change="validate" class="relative">
                  <label
                    for={@uploads.photo.ref}
                    class={[
                      "group cursor-pointer flex items-center gap-3 px-6 py-4 border-4 border-base-content",
                      "font-bold uppercase tracking-wide transition-all",
                      @uploading && "bg-base-content text-base-100",
                      not @uploading && "bg-error text-error-content hover:translate-x-1 hover:translate-y-1"
                    ]}
                  >
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="square" stroke-width="2.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <%= if @uploading do %>
                      <span>Uploading...</span>
                    <% else %>
                      <span>Upload Photo</span>
                    <% end %>
                    <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                  </label>
                  <.live_file_input upload={@uploads.photo} class="hidden" />
                </form>
              </div>
            </div>
          </div>
        </div>

        <!-- Upload Progress -->
        <%= for entry <- @uploads.photo.entries do %>
          <div class="border-b-4 border-base-content bg-base-200/50">
            <div class="container mx-auto px-4 py-4">
              <div class="flex items-center gap-4">
                <div class="flex-1 bg-base-300 h-3 border-2 border-base-content">
                  <div class="bg-error h-full transition-all" style={"width: #{entry.progress}%"}></div>
                </div>
                <span class="text-sm font-bold uppercase">{entry.progress}%</span>
                <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="p-1 hover:bg-base-content hover:text-base-100">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="square" stroke-width="2.5" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              <%= for err <- upload_errors(@uploads.photo, entry) do %>
                <p class="text-error text-sm font-bold mt-2">{error_to_string(err)}</p>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Photos Grid -->
        <div class="container mx-auto px-4 py-8">
          <%= if @photos == [] do %>
            <div class="flex flex-col items-center justify-center py-24 text-center">
              <div class="w-32 h-32 border-4 border-base-content/20 mb-8 flex items-center justify-center">
                <svg class="w-16 h-16 opacity-20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="square" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              </div>
              <h3 class="text-2xl font-black uppercase tracking-tight mb-2 opacity-50">No Photos Yet</h3>
              <p class="text-sm opacity-50 max-w-md">
                Be the first to share a photo! Click the upload button above.
              </p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6" id="photos-grid" phx-update="stream">
              <%= for {dom_id, photo} <- @streams.photos do %>
                <div
                  id={dom_id}
                  class="group relative border-4 border-base-content bg-base-100 overflow-hidden hover:translate-x-1 hover:translate-y-1 transition-transform"
                >
                  <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                  
                  <!-- Image Container -->
                  <div class="aspect-square overflow-hidden bg-base-200">
                    <img
                      src={photo.data_url}
                      alt="Shared photo"
                      class="w-full h-full object-cover transition-transform group-hover:scale-105"
                    />
                  </div>
                  
                  <!-- Photo Info -->
                  <div class="p-3 border-t-4 border-base-content">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class="w-4 h-4 border-2 border-base-content"
                          style={"background-color: #{photo.user_color}"}
                        ></div>
                        <span class="text-xs font-bold uppercase tracking-wide opacity-70">
                          {String.slice(photo.user_id, 0, 8)}
                        </span>
                      </div>
                      <span class="text-xs font-bold uppercase tracking-wide opacity-50">
                        {format_time(photo.uploaded_at)}
                      </span>
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

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  # Handle completed uploads
  def handle_progress(:photo, entry, socket) when entry.done? do
    # Consume the uploaded entry
    [photo_data] =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
        # Read file and convert to base64 data URL
        binary = File.read!(path)
        base64 = Base.encode64(binary)
        content_type = entry.client_type || "image/jpeg"
        {:ok, "data:#{content_type};base64,#{base64}"}
      end)

    user_id = socket.assigns.user_id
    user_color = socket.assigns.user_color

    photo = %{
      id: generate_photo_id(),
      user_id: user_id,
      user_color: user_color,
      data_url: photo_data,
      uploaded_at: DateTime.utc_now()
    }

    # Save photo to ETS
    save_photo(photo)

    # Broadcast to all connected users
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {:new_photo, photo}
    )

    {:noreply,
     socket
     |> assign(:uploading, false)
     |> stream_insert(:photos, photo, at: 0)
     |> put_flash(:info, "📸 Photo shared!")}
  end

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  # Handle new photos from other users
  def handle_info({:new_photo, photo}, socket) do
    # Only add if not from this user (we already added it locally)
    if photo.user_id != socket.assigns.user_id do
      {:noreply, stream_insert(socket, :photos, photo, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:user_joined, _user_id}, socket) do
    {:noreply, assign(socket, :online_count, socket.assigns.online_count + 1)}
  end

  def handle_info({:user_left, _user_id}, socket) do
    count = max(1, socket.assigns.online_count - 1)
    {:noreply, assign(socket, :online_count, count)}
  end

  def terminate(_reason, socket) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {:user_left, socket.assigns.user_id}
    )
    :ok
  end

  # --- Helper Functions ---

  defp get_or_create_user_id(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} ->
        ip_string = :inet.ntoa(address) |> to_string()
        :crypto.hash(:md5, ip_string) |> Base.encode16(case: :lower) |> String.slice(0, 16)
      _ ->
        :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    end
  end

  defp generate_user_color(user_id) do
    # Generate a consistent color from user ID
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    
    # Ensure colors are vibrant (not too dark or light)
    r = rem(r, 156) + 100
    g = rem(g, 156) + 100
    b = rem(b, 156) + 100
    
    "rgb(#{r}, #{g}, #{b})"
  end

  defp generate_photo_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp error_to_string(:too_large), do: "File too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "Invalid file type (use JPG, PNG, GIF, or WebP)"
  defp error_to_string(err), do: "Error: #{inspect(err)}"

  # --- ETS Storage for Photos ---

  defp photos_table do
    table = :friends_photos
    
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
      _ ->
        table
    end
  end

  defp save_photo(photo) do
    table = photos_table()
    
    # Get current photos
    photos = get_photos_from_ets()
    
    # Keep only last N photos
    photos = [photo | photos] |> Enum.take(@max_photos)
    
    # Store all photos
    :ets.insert(table, {:photos, photos})
  end

  defp get_photos do
    photos = get_photos_from_ets()
    
    # Return as stream-compatible format
    Enum.map(photos, fn photo ->
      photo
    end)
  end

  defp get_photos_from_ets do
    table = photos_table()
    
    case :ets.lookup(table, :photos) do
      [{:photos, photos}] -> photos
      [] -> []
    end
  end
end

