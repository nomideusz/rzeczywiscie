defmodule RzeczywiscieWeb.FriendsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Friends
  alias Rzeczywiscie.Friends.{Room, Presence}

  def mount(%{"room" => room_code}, _session, socket) do
    mount_room(socket, room_code)
  end

  def mount(_params, _session, socket) do
    mount_room(socket, "lobby")
  end

  defp mount_room(socket, room_code) do
    user_id = get_or_create_user_id(socket)
    user_color = generate_user_color(user_id)
    session_id = generate_session_id()

    # Get or create room
    room = case Friends.get_room_by_code(room_code) do
      nil -> Friends.get_or_create_lobby()
      r -> r
    end

    if connected?(socket) do
      # Subscribe to room updates
      Friends.subscribe(room.code)
      
      # Subscribe to presence
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:presence:#{room.code}")
      
      # Track presence
      Presence.track_user(self(), room.code, user_id, user_color)
    end

    photos = Friends.list_photos(room.id)
    viewers = if connected?(socket), do: Presence.list_users(room.code), else: []

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_color, user_color)
      |> assign(:session_id, session_id)
      |> assign(:room, room)
      |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
      |> assign(:photos, photos)
      |> assign(:photo_count, Friends.count_photos(room.id))
      |> assign(:viewers, viewers)
      |> assign(:uploading, false)
      |> assign(:show_room_modal, false)
      |> assign(:new_room_code, "")
      |> assign(:join_room_code, "")
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

  def handle_params(%{"room" => room_code}, _uri, socket) do
    if socket.assigns.room.code != room_code do
      # Switch rooms
      old_room = socket.assigns.room
      
      # Unsubscribe from old room
      Friends.unsubscribe(old_room.code)
      Phoenix.PubSub.unsubscribe(Rzeczywiscie.PubSub, "friends:presence:#{old_room.code}")
      
      # Get new room
      room = case Friends.get_room_by_code(room_code) do
        nil -> Friends.get_or_create_lobby()
        r -> r
      end
      
      # Subscribe to new room
      Friends.subscribe(room.code)
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:presence:#{room.code}")
      
      # Track presence in new room
      Presence.track_user(self(), room.code, socket.assigns.user_id, socket.assigns.user_color)
      
      photos = Friends.list_photos(room.id)
      viewers = Presence.list_users(room.code)
      
      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
       |> assign(:photos, photos)
       |> assign(:photo_count, Friends.count_photos(room.id))
       |> assign(:viewers, viewers)
       |> stream(:photos, photos, reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="min-h-screen bg-gradient-to-br from-base-100 via-base-100 to-error/5">
        <!-- Header Section -->
        <div class="border-b-4 border-base-content bg-base-100">
          <div class="container mx-auto px-4 py-6">
            <div class="flex flex-col gap-4">
              <!-- Room Info & Viewers -->
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
                <div class="flex items-center gap-4">
                  <!-- Room Selector -->
                  <button
                    phx-click="toggle-room-modal"
                    class="flex items-center gap-2 px-4 py-2 border-4 border-base-content bg-base-100 hover:bg-base-content hover:text-base-100 transition-colors font-bold uppercase text-sm"
                  >
                    <span class="text-2xl">{@room.emoji}</span>
                    <span>{@room.name || @room.code}</span>
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  
                  <!-- Live Viewers -->
                  <div class="flex items-center gap-2">
                    <div class="flex -space-x-2">
                      <%= for {viewer, idx} <- Enum.with_index(Enum.take(@viewers, 5)) do %>
                        <div
                          class="w-8 h-8 rounded-full border-2 border-base-100 flex items-center justify-center text-xs font-bold animate-pulse"
                          style={"background-color: #{viewer.user_color}; animation-delay: #{idx * 100}ms"}
                          title={String.slice(viewer.user_id, 0, 8)}
                        >
                        </div>
                      <% end %>
                      <%= if length(@viewers) > 5 do %>
                        <div class="w-8 h-8 rounded-full border-2 border-base-100 bg-base-content text-base-100 flex items-center justify-center text-xs font-bold">
                          +{length(@viewers) - 5}
                        </div>
                      <% end %>
                    </div>
                    <span class="text-xs font-bold uppercase tracking-wide opacity-70">
                      👀 {length(@viewers)} viewing
                    </span>
                  </div>
                </div>

                <!-- Upload Button -->
                <div class="flex-shrink-0">
                  <form id="upload-form" phx-submit="save" phx-change="validate" class="relative">
                    <label
                      for={@uploads.photo.ref}
                      class={[
                        "group cursor-pointer flex items-center gap-3 px-5 py-3 border-4 border-base-content",
                        "font-bold uppercase tracking-wide transition-all text-sm",
                        @uploading && "bg-base-content text-base-100",
                        not @uploading && "bg-error text-error-content hover:translate-x-1 hover:translate-y-1"
                      ]}
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="square" stroke-width="2.5" d="M12 4v16m8-8H4" />
                      </svg>
                      <%= if @uploading do %>
                        <span>Uploading...</span>
                      <% else %>
                        <span>Add Photo</span>
                      <% end %>
                      <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                    </label>
                    <.live_file_input upload={@uploads.photo} class="hidden" />
                  </form>
                </div>
              </div>

              <!-- Stats Bar -->
              <div class="flex items-center gap-4 text-xs font-bold uppercase tracking-wide opacity-60">
                <span>{@photo_count} photos</span>
                <span>•</span>
                <span>Room: {@room.code}</span>
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
              <div class="text-6xl mb-6">{@room.emoji}</div>
              <h3 class="text-2xl font-black uppercase tracking-tight mb-2 opacity-50">No Photos Yet</h3>
              <p class="text-sm opacity-50 max-w-md mb-6">
                Be the first to share a photo in {@room.name || @room.code}!
              </p>
              <p class="text-xs font-mono opacity-30">
                Share this room: kruk.live/friends/{@room.code}
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
                  
                  <!-- Delete Button -->
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
                  
                  <!-- Image -->
                  <div class="aspect-square overflow-hidden bg-base-200">
                    <img
                      src={photo.data_url}
                      alt="Shared photo"
                      class="w-full h-full object-cover transition-transform group-hover:scale-105"
                      loading="lazy"
                    />
                  </div>
                  
                  <!-- Photo Info -->
                  <div class="p-3 border-t-4 border-base-content bg-base-100">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-2">
                        <div
                          class="w-4 h-4 border-2 border-base-content rounded-full"
                          style={"background-color: #{photo.user_color}"}
                        ></div>
                        <span class="text-xs font-bold uppercase tracking-wide text-base-content/70">
                          {String.slice(photo.user_id, 0, 8)}
                        </span>
                      </div>
                      <span class="text-xs font-bold uppercase tracking-wide text-base-content/50">
                        {format_time(photo.uploaded_at)}
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Room Modal -->
        <%= if @show_room_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-base-content/50" phx-click="toggle-room-modal">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-md w-full" phx-click-away="toggle-room-modal">
              <h2 class="text-2xl font-black uppercase tracking-tight mb-6">Switch Room</h2>
              
              <!-- Current Room -->
              <div class="mb-6 p-4 border-2 border-base-content/20 bg-base-200/50">
                <div class="text-xs font-bold uppercase tracking-wide opacity-50 mb-1">Current</div>
                <div class="flex items-center gap-2">
                  <span class="text-2xl">{@room.emoji}</span>
                  <span class="font-bold">{@room.name || @room.code}</span>
                </div>
              </div>

              <!-- Join Existing Room -->
              <div class="mb-6">
                <label class="text-xs font-bold uppercase tracking-wide opacity-70 mb-2 block">Join Room</label>
                <form phx-submit="join-room" class="flex gap-2">
                  <input
                    type="text"
                    name="code"
                    value={@join_room_code}
                    phx-change="update-join-code"
                    placeholder="room-code"
                    class="flex-1 px-4 py-2 border-2 border-base-content font-mono text-sm bg-base-100 focus:outline-none focus:bg-base-200"
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase text-sm hover:bg-primary hover:border-primary transition-colors">
                    Join
                  </button>
                </form>
              </div>

              <!-- Create New Room -->
              <div class="mb-6">
                <label class="text-xs font-bold uppercase tracking-wide opacity-70 mb-2 block">Create New Room</label>
                <form phx-submit="create-room" class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    placeholder="Room name (optional)"
                    class="flex-1 px-4 py-2 border-2 border-base-content text-sm bg-base-100 focus:outline-none focus:bg-base-200"
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-base-content bg-error text-error-content font-bold uppercase text-sm hover:bg-base-content hover:text-base-100 transition-colors">
                    Create
                  </button>
                </form>
              </div>

              <!-- Back to Lobby -->
              <%= if @room.code != "lobby" do %>
                <button
                  phx-click="go-to-lobby"
                  class="w-full px-4 py-3 border-2 border-base-content font-bold uppercase text-sm hover:bg-base-content hover:text-base-100 transition-colors"
                >
                  🏠 Back to Lobby
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </.app>
    """
  end

  # --- Events ---

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
    photo_id = String.to_integer(id)
    room = socket.assigns.room
    
    case Friends.get_photo(photo_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Photo not found")}
      
      photo ->
        if photo.user_id == socket.assigns.user_id do
          case Friends.delete_photo(photo_id, room.code) do
            {:ok, _} ->
              Friends.broadcast(room.code, :photo_deleted_from_session, %{id: photo_id}, socket.assigns.session_id)
              
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

  def handle_event("toggle-room-modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, !socket.assigns.show_room_modal)}
  end

  def handle_event("update-join-code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :join_room_code, code)}
  end

  def handle_event("join-room", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.downcase()
    
    if code != "" do
      {:noreply,
       socket
       |> assign(:show_room_modal, false)
       |> push_navigate(to: ~p"/friends/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "Please enter a room code")}
    end
  end

  def handle_event("create-room", %{"name" => name}, socket) do
    code = Friends.generate_room_code()
    name = if name == "", do: nil, else: name
    emoji = Enum.random(~w(📸 🎉 🌟 🔥 💫 🎨 🌈 ✨ 🎭 🎪))
    
    case Friends.create_room(%{code: code, name: name, emoji: emoji, created_by: socket.assigns.user_id}) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:show_room_modal, false)
         |> push_navigate(to: ~p"/friends/#{code}")}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create room")}
    end
  end

  def handle_event("go-to-lobby", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_room_modal, false)
     |> push_navigate(to: ~p"/friends/lobby")}
  end

  # --- Progress Handler ---

  def handle_progress(:photo, entry, socket) when entry.done? do
    [photo_result] =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, _entry ->
        binary = File.read!(path)
        base64 = Base.encode64(binary)
        content_type = entry.client_type || "image/jpeg"
        file_size = byte_size(binary)
        data_url = "data:#{content_type};base64,#{base64}"
        {:ok, %{data_url: data_url, content_type: content_type, file_size: file_size}}
      end)

    room = socket.assigns.room
    user_id = socket.assigns.user_id
    user_color = socket.assigns.user_color

    case Friends.create_photo(%{
      user_id: user_id,
      user_color: user_color,
      image_data: photo_result.data_url,
      content_type: photo_result.content_type,
      file_size: photo_result.file_size,
      room_id: room.id
    }, room.code) do
      {:ok, photo} ->
        Friends.broadcast(room.code, :new_photo_from_session, photo, socket.assigns.session_id)
        
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

  # --- PubSub Handlers ---

  def handle_info({:new_photo_from_session, photo, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:photo_count, socket.assigns.photo_count + 1)
       |> stream_insert(:photos, photo, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_photo, _photo}, socket) do
    {:noreply, socket}
  end

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

  def handle_info({:photo_deleted, %{id: _id}}, socket) do
    {:noreply, socket}
  end

  # Presence updates
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    viewers = Presence.list_users(socket.assigns.room.code)
    {:noreply, assign(socket, :viewers, viewers)}
  end

  # --- Helpers ---

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
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
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
