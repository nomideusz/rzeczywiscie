defmodule RzeczywiscieWeb.FriendsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Friends

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Friends.subscribe()
    end

    user_id = get_or_create_user_id(socket)
    user_color = generate_user_color(user_id)
    session_id = generate_session_id()
    photos = Friends.list_photos()

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_color, user_color)
      |> assign(:session_id, session_id)
      |> assign(:page_title, "Friends")
      |> assign(:photos, photos)
      |> assign(:photo_count, Friends.count_photos())
      |> assign(:uploading, false)
      |> stream(:photos, photos)
      |> allow_upload(:photo,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

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
                    Live • {@photo_count} photos shared
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
                  
                  <!-- Delete Button (visible on hover, only for own photos) -->
                  <%= if photo.user_id == @user_id do %>
                    <button
                      type="button"
                      phx-click="delete-photo"
                      phx-value-id={photo.id}
                      data-confirm="Delete this photo?"
                      class="absolute top-2 right-2 z-10 p-2 bg-error text-error-content border-2 border-base-content opacity-0 group-hover:opacity-100 transition-opacity hover:bg-base-content hover:text-base-100"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="square" stroke-width="2.5" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </button>
                  <% end %>
                  
                  <!-- Image Container -->
                  <div class="aspect-square overflow-hidden bg-base-200">
                    <img
                      src={photo.data_url}
                      alt="Shared photo"
                      class="w-full h-full object-cover transition-transform group-hover:scale-105"
                      loading="lazy"
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

  def handle_event("delete-photo", %{"id" => id}, socket) do
    # Convert string ID to integer
    photo_id = String.to_integer(id)
    
    # Verify the photo belongs to this user before deleting
    case Friends.get_photo(photo_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Photo not found")}
      
      photo ->
        if photo.user_id == socket.assigns.user_id do
          case Friends.delete_photo(photo_id) do
            {:ok, _} ->
              # Broadcast deletion with session_id
              Friends.broadcast(:photo_deleted_from_session, %{id: photo_id}, socket.assigns.session_id)
              
              {:noreply,
               socket
               |> assign(:photo_count, max(0, socket.assigns.photo_count - 1))
               |> stream_delete(:photos, %{id: photo_id})
               |> put_flash(:info, "🗑️ Photo deleted")}
            
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete photo")}
          end
        else
          {:noreply, put_flash(socket, :error, "You can only delete your own photos")}
        end
    end
  end

  # Handle completed uploads
  def handle_progress(:photo, entry, socket) when entry.done? do
    # Consume the uploaded entry
    [photo_result] =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
        # Read file and convert to base64 data URL
        binary = File.read!(path)
        base64 = Base.encode64(binary)
        content_type = entry.client_type || "image/jpeg"
        file_size = byte_size(binary)
        data_url = "data:#{content_type};base64,#{base64}"
        {:ok, %{data_url: data_url, content_type: content_type, file_size: file_size}}
      end)

    user_id = socket.assigns.user_id
    user_color = socket.assigns.user_color

    # Save to database (create_photo broadcasts automatically, but we'll also track session)
    case Friends.create_photo(%{
      user_id: user_id,
      user_color: user_color,
      image_data: photo_result.data_url,
      content_type: photo_result.content_type,
      file_size: photo_result.file_size
    }) do
      {:ok, photo} ->
        # Broadcast with session_id so other tabs know to show it
        Friends.broadcast(:new_photo_from_session, photo, socket.assigns.session_id)
        
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:photo_count, socket.assigns.photo_count + 1)
         |> stream_insert(:photos, photo, at: 0)
         |> put_flash(:info, "📸 Photo shared!")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, "Failed to save photo")}
    end
  end

  def handle_progress(:photo, _entry, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  # Handle new photos from other sessions (with session_id tracking)
  def handle_info({:new_photo_from_session, photo, from_session_id}, socket) do
    # Only add if not from this specific session (we already added it locally)
    if from_session_id != socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:photo_count, socket.assigns.photo_count + 1)
       |> stream_insert(:photos, photo, at: 0)}
    else
      {:noreply, socket}
    end
  end

  # Handle new photos from context (fallback for old broadcasts)
  def handle_info({:new_photo, _photo}, socket) do
    # Ignore - we now use :new_photo_from_session for real-time updates
    {:noreply, socket}
  end

  # Handle photo deletion from other sessions
  def handle_info({:photo_deleted_from_session, %{id: id}, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:photo_count, max(0, socket.assigns.photo_count - 1))
       |> stream_delete(:photos, %{id: id})}
    else
      {:noreply, socket}
    end
  end

  # Handle photo deletion from context (fallback)
  def handle_info({:photo_deleted, %{id: _id}}, socket) do
    # Ignore - we now use :photo_deleted_from_session for real-time updates
    {:noreply, socket}
  end

  def handle_info({:user_photos_deleted, %{user_id: _user_id}}, socket) do
    # Reload photos when bulk deletion happens
    photos = Friends.list_photos()
    {:noreply,
     socket
     |> assign(:photo_count, Friends.count_photos())
     |> stream(:photos, photos, reset: true)}
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

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp format_time(datetime) do
    now = DateTime.utc_now()
    
    # Handle NaiveDateTime from database
    datetime = case datetime do
      %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
      %DateTime{} -> datetime
      _ -> DateTime.utc_now()
    end
    
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
end
