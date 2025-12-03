defmodule RzeczywiscieWeb.FriendsLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Friends
  alias Rzeczywiscie.Friends.Presence

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

    room = case Friends.get_room_by_code(room_code) do
      nil -> Friends.get_or_create_lobby()
      r -> r
    end

    if connected?(socket) do
      Friends.subscribe(room.code)
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:presence:#{room.code}")
      Presence.track_user(self(), room.code, user_id, user_color)
    end

    photos = Friends.list_photos(room.id)
    messages = Friends.list_messages(room.id)
    viewers = if connected?(socket), do: Presence.list_users(room.code), else: []

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_color, user_color)
      |> assign(:user_name, nil)
      |> assign(:session_id, session_id)
      |> assign(:room, room)
      |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
      |> assign(:photos, photos)
      |> assign(:photo_count, Friends.count_photos(room.id))
      |> assign(:messages, messages)
      |> assign(:message_input, "")
      |> assign(:viewers, viewers)
      |> assign(:uploading, false)
      |> assign(:show_room_modal, false)
      |> assign(:show_name_modal, false)
      |> assign(:show_lightbox, false)
      |> assign(:lightbox_photo, nil)
      |> assign(:join_room_code, "")
      |> assign(:new_room_name, "")
      |> assign(:name_input, "")
      |> stream(:photos, photos)
      |> stream(:messages, messages)
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
      old_room = socket.assigns.room
      
      # Untrack presence from old room first
      Presence.untrack(self(), old_room.code, socket.assigns.user_id)
      
      Friends.unsubscribe(old_room.code)
      Phoenix.PubSub.unsubscribe(Rzeczywiscie.PubSub, "friends:presence:#{old_room.code}")
      
      room = case Friends.get_room_by_code(room_code) do
        nil -> Friends.get_or_create_lobby()
        r -> r
      end
      
      Friends.subscribe(room.code)
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:presence:#{room.code}")
      Presence.track_user(self(), room.code, socket.assigns.user_id, socket.assigns.user_color)
      
      photos = Friends.list_photos(room.id)
      messages = Friends.list_messages(room.id)
      viewers = Presence.list_users(room.code)
      
      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
       |> assign(:photos, photos)
       |> assign(:photo_count, Friends.count_photos(room.id))
       |> assign(:messages, messages)
       |> assign(:viewers, viewers)
       |> stream(:photos, photos, reset: true)
       |> stream(:messages, messages, reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div id="friends-container" class="min-h-screen bg-gradient-to-br from-base-100 via-base-100 to-error/5" phx-hook="FriendsApp">
        <!-- Header -->
        <div class="border-b-4 border-base-content bg-base-100">
          <div class="container mx-auto px-4 py-4">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div class="flex items-center gap-4">
                <!-- Room Selector -->
                <button
                  type="button"
                  phx-click="open-room-modal"
                  class="flex items-center gap-2 px-4 py-2 border-4 border-base-content bg-base-100 hover:bg-base-content hover:text-base-100 transition-colors font-bold uppercase text-sm"
                >
                  <span class="text-xl">{@room.emoji}</span>
                  <span class="hidden sm:inline">{@room.name || @room.code}</span>
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                
                <!-- User Name / Profile -->
                <button
                  type="button"
                  phx-click="open-name-modal"
                  class="flex items-center gap-2 px-3 py-2 border-2 border-base-content/30 hover:border-base-content transition-colors text-sm"
                >
                  <div class="w-5 h-5 rounded-full border border-base-content" style={"background-color: #{@user_color}"}></div>
                  <span class="font-bold">{@user_name || String.slice(@user_id, 0, 6)}</span>
                  <svg class="w-3 h-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                </button>
                
                <!-- Live Viewers -->
                <div class="flex items-center gap-2">
                  <div class="flex -space-x-2">
                    <%= for {viewer, idx} <- Enum.with_index(Enum.take(@viewers, 4)) do %>
                      <div
                        class="w-7 h-7 rounded-full border-2 border-base-100"
                        style={"background-color: #{viewer.user_color}; animation: pulse 2s infinite; animation-delay: #{idx * 150}ms"}
                      ></div>
                    <% end %>
                    <%= if length(@viewers) > 4 do %>
                      <div class="w-7 h-7 rounded-full border-2 border-base-100 bg-base-content text-base-100 flex items-center justify-center text-[10px] font-bold">
                        +{length(@viewers) - 4}
                      </div>
                    <% end %>
                  </div>
                  <span class="text-xs font-bold opacity-60">👀 {length(@viewers)}</span>
                </div>
              </div>

              <!-- Upload Button -->
              <form id="upload-form" phx-submit="save" phx-change="validate" class="relative flex-shrink-0">
                <label
                  for={@uploads.photo.ref}
                  class={[
                    "cursor-pointer flex items-center gap-2 px-4 py-2 border-4 border-base-content font-bold uppercase text-sm transition-all",
                    @uploading && "bg-base-content text-base-100",
                    not @uploading && "bg-error text-error-content hover:translate-x-1 hover:translate-y-1"
                  ]}
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="square" stroke-width="2.5" d="M12 4v16m8-8H4" />
                  </svg>
                  <span class="hidden sm:inline"><%= if @uploading, do: "Uploading...", else: "Photo" %></span>
                </label>
                <.live_file_input upload={@uploads.photo} class="hidden" />
                <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
              </form>
            </div>
          </div>
        </div>

        <!-- Upload Progress -->
        <%= for entry <- @uploads.photo.entries do %>
          <div class="border-b-2 border-base-content/20 bg-base-200/50">
            <div class="container mx-auto px-4 py-2">
              <div class="flex items-center gap-3">
                <div class="flex-1 bg-base-300 h-2 border border-base-content">
                  <div class="bg-error h-full transition-all" style={"width: #{entry.progress}%"}></div>
                </div>
                <span class="text-xs font-bold">{entry.progress}%</span>
                <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="text-error">✕</button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Main Content: Photos + Chat -->
        <div class="container mx-auto px-4 py-6">
          <div class="grid lg:grid-cols-3 gap-6">
            <!-- Photos Grid (2/3) - Masonry Layout -->
            <div class="lg:col-span-2">
              <%= if @photos == [] do %>
                <div class="flex flex-col items-center justify-center py-16 text-center border-4 border-dashed border-base-content/20">
                  <div class="text-5xl mb-4">{@room.emoji}</div>
                  <h3 class="text-xl font-black uppercase mb-2 opacity-50">No Photos Yet</h3>
                  <p class="text-sm opacity-40 mb-4">Share the first photo in this room!</p>
                  <p class="text-xs font-mono opacity-30">kruk.live/friends/{@room.code}</p>
                </div>
              <% else %>
                <div class="columns-2 sm:columns-3 gap-3 space-y-3" id="photos-grid" phx-update="stream">
                  <%= for {dom_id, photo} <- @streams.photos do %>
                    <div
                      id={dom_id}
                      class="group relative border-4 border-base-content bg-base-100 overflow-hidden hover:translate-x-0.5 hover:translate-y-0.5 transition-transform break-inside-avoid"
                    >
                      <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                      
                      <%= if photo.user_id == @user_id do %>
                        <button
                          type="button"
                          phx-click="delete-photo"
                          phx-value-id={photo.id}
                          data-confirm="Delete?"
                          class="absolute top-1 right-1 z-10 p-1.5 bg-error/90 text-error-content text-xs opacity-0 group-hover:opacity-100 transition-opacity"
                        >✕</button>
                      <% end %>
                      
                      <button
                        type="button"
                        phx-click="open-lightbox"
                        phx-value-id={photo.id}
                        class="overflow-hidden bg-base-200 w-full cursor-zoom-in block"
                      >
                        <img src={photo.data_url} alt="" class="w-full h-auto" loading="lazy" />
                      </button>
                      
                      <div class="p-2 border-t-2 border-base-content bg-base-100 flex items-center gap-2">
                        <div class="w-3 h-3 rounded-full border border-base-content flex-shrink-0" style={"background-color: #{photo.user_color}"}></div>
                        <span class="text-[10px] font-bold truncate flex-1">
                          {photo.user_name || String.slice(photo.user_id, 0, 6)}
                        </span>
                        <span class="text-[10px] opacity-50 flex-shrink-0">{format_time(photo.uploaded_at)}</span>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Chat Panel (1/3) -->
            <div class="lg:col-span-1">
              <div class="border-4 border-base-content bg-base-100 h-[500px] flex flex-col">
                <!-- Chat Header -->
                <div class="p-3 border-b-2 border-base-content bg-base-200/50">
                  <h3 class="font-black uppercase text-sm">💬 Chat</h3>
                </div>

                <!-- Messages -->
                <div class="flex-1 overflow-y-auto p-3 space-y-3" id="messages-container" phx-update="stream" phx-hook="ScrollToBottom">
                  <%= for {dom_id, message} <- @streams.messages do %>
                    <div id={dom_id} class="group flex gap-2">
                      <div class="w-6 h-6 rounded-full border border-base-content flex-shrink-0" style={"background-color: #{message.user_color}"}></div>
                      <div class="flex-1 min-w-0">
                        <div class="text-[10px] font-bold opacity-40 mb-0.5 flex items-center gap-2">
                          <span>{message.user_name || String.slice(message.user_id, 0, 6)}</span>
                          <span>·</span>
                          <span>{format_time(message.sent_at)}</span>
                          <%= if message.user_id == @user_id do %>
                            <button
                              type="button"
                              phx-click="delete-message"
                              phx-value-id={message.id}
                              class="opacity-0 group-hover:opacity-100 text-error hover:text-error/80 transition-opacity"
                            >✕</button>
                          <% end %>
                        </div>
                        <div class="text-sm break-words">{message.content}</div>
                      </div>
                    </div>
                  <% end %>
                  <%= if @messages == [] do %>
                    <div class="text-center text-sm opacity-40 py-8">
                      No messages yet.<br/>Say hi! 👋
                    </div>
                  <% end %>
                </div>

                <!-- Message Input -->
                <form phx-submit="send-message" class="p-3 border-t-2 border-base-content">
                  <div class="flex gap-2">
                    <input
                      type="text"
                      name="content"
                      value={@message_input}
                      phx-change="update-message"
                      placeholder="Type a message..."
                      autocomplete="off"
                      class="flex-1 px-3 py-2 border-2 border-base-content text-sm bg-base-100 focus:outline-none focus:bg-base-200"
                    />
                    <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold text-sm hover:bg-primary hover:border-primary transition-colors">
                      Send
                    </button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        </div>

        <!-- Lightbox Modal -->
        <%= if @show_lightbox && @lightbox_photo do %>
          <div 
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 cursor-zoom-out"
            phx-click="close-lightbox"
          >
            <button 
              type="button" 
              phx-click="close-lightbox"
              class="absolute top-4 right-4 text-white text-3xl hover:opacity-60 z-10"
            >×</button>
            <img 
              src={@lightbox_photo.data_url} 
              alt="" 
              class="max-w-[95vw] max-h-[95vh] object-contain"
              phx-click="close-lightbox"
            />
            <div class="absolute bottom-4 left-1/2 -translate-x-1/2 bg-black/70 text-white px-4 py-2 rounded flex items-center gap-3">
              <div class="w-4 h-4 rounded-full" style={"background-color: #{@lightbox_photo.user_color}"}></div>
              <span class="font-bold">{@lightbox_photo.user_name || String.slice(@lightbox_photo.user_id, 0, 6)}</span>
              <span class="opacity-60">{format_time(@lightbox_photo.uploaded_at)}</span>
            </div>
          </div>
        <% end %>

        <!-- Name Edit Modal -->
        <%= if @show_name_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-sm w-full shadow-2xl" phx-click-away="close-name-modal">
              <div class="flex justify-between items-center mb-6">
                <h2 class="text-xl font-black uppercase">Your Profile</h2>
                <button type="button" phx-click="close-name-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>
              
              <!-- Current Identity -->
              <div class="mb-6 flex items-center gap-4">
                <div class="w-12 h-12 rounded-full border-2 border-base-content" style={"background-color: #{@user_color}"}></div>
                <div>
                  <div class="font-bold">{@user_name || String.slice(@user_id, 0, 6)}</div>
                  <div class="text-xs opacity-40">ID: {String.slice(@user_id, 0, 8)}</div>
                </div>
              </div>

              <!-- Change Name -->
              <form phx-submit="save-name">
                <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Display Name</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@name_input}
                    phx-change="update-name-input"
                    placeholder="Enter name (max 20 chars)"
                    maxlength="20"
                    class="flex-1 px-3 py-2 border-2 border-base-content text-sm bg-base-100"
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold text-sm">
                    Save
                  </button>
                </div>
                <p class="text-xs opacity-40 mt-2">Your name is stored locally and shown with your messages and photos.</p>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Room Modal -->
        <%= if @show_room_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-sm w-full shadow-2xl" phx-click-away="close-room-modal">
              <div class="flex justify-between items-center mb-6">
                <h2 class="text-xl font-black uppercase">Rooms</h2>
                <button type="button" phx-click="close-room-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>
              
              <!-- Current Room -->
              <div class="mb-6 p-3 border-2 border-base-content/20 bg-base-200/30">
                <div class="text-[10px] font-bold uppercase opacity-40 mb-1">Current Room</div>
                <div class="flex items-center gap-2 font-bold">
                  <span class="text-xl">{@room.emoji}</span>
                  <span>{@room.name || @room.code}</span>
                </div>
                <div class="text-xs font-mono opacity-40 mt-1">kruk.live/friends/{@room.code}</div>
              </div>

              <!-- Join Room -->
              <form phx-submit="join-room" class="mb-4">
                <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Join Room</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="code"
                    value={@join_room_code}
                    phx-change="update-join-code"
                    placeholder="room-code"
                    class="flex-1 px-3 py-2 border-2 border-base-content font-mono text-sm bg-base-100"
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold text-sm">
                    Go
                  </button>
                </div>
              </form>

              <!-- Create Room -->
              <form phx-submit="create-room" class="mb-4">
                <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Create New</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@new_room_name}
                    phx-change="update-room-name"
                    placeholder="Room name"
                    class="flex-1 px-3 py-2 border-2 border-base-content text-sm bg-base-100"
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-error bg-error text-error-content font-bold text-sm">
                    Create
                  </button>
                </div>
              </form>

              <!-- Lobby -->
              <%= if @room.code != "lobby" do %>
                <button
                  type="button"
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

  def handle_event("set_user_id", %{"user_id" => device_user_id} = params, socket) do
    # Client sends device-specific user_id (fingerprint based on hardware)
    old_user_id = socket.assigns.user_id
    room = socket.assigns.room
    user_name = params["user_name"]

    if old_user_id != device_user_id do
      # Update presence with new device-based user_id
      Presence.untrack(self(), room.code, old_user_id)

      # Generate new color based on device fingerprint (consistent across browsers)
      new_user_color = generate_user_color(device_user_id)

      # Track with new device-based user_id
      Presence.track_user(self(), room.code, device_user_id, new_user_color)

      {:noreply,
       socket
       |> assign(:user_id, device_user_id)
       |> assign(:user_color, new_user_color)
       |> assign(:user_name, user_name)}
    else
      {:noreply, assign(socket, :user_name, user_name)}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}
  def handle_event("save", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photo, ref)}
  end

  # --- Photo Events ---

  def handle_event("delete-photo", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)
    room = socket.assigns.room
    
    case Friends.get_photo(photo_id) do
      nil -> {:noreply, put_flash(socket, :error, "Photo not found")}
      photo ->
        if photo.user_id == socket.assigns.user_id do
          case Friends.delete_photo(photo_id, room.code) do
            {:ok, _} ->
              Friends.broadcast(room.code, :photo_deleted_from_session, %{id: photo_id}, socket.assigns.session_id)
              {:noreply,
               socket
               |> assign(:photo_count, max(0, socket.assigns.photo_count - 1))
               |> stream_delete(:photos, %{id: photo_id})
               |> put_flash(:info, "Deleted")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed")}
          end
        else
          {:noreply, put_flash(socket, :error, "Not yours")}
        end
    end
  end

  def handle_event("open-lightbox", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)
    # Find the photo in the stream
    photo = Enum.find(socket.assigns.photos, fn p -> p.id == photo_id end)
    {:noreply, socket |> assign(:show_lightbox, true) |> assign(:lightbox_photo, photo)}
  end

  def handle_event("close-lightbox", _params, socket) do
    {:noreply, socket |> assign(:show_lightbox, false) |> assign(:lightbox_photo, nil)}
  end

  # --- Message Events ---

  def handle_event("delete-message", %{"id" => id}, socket) do
    message_id = String.to_integer(id)
    room = socket.assigns.room
    
    case Friends.get_message(message_id) do
      nil -> {:noreply, put_flash(socket, :error, "Message not found")}
      message ->
        if message.user_id == socket.assigns.user_id do
          case Friends.delete_message(message_id, room.code) do
            {:ok, _} ->
              Friends.broadcast(room.code, :message_deleted_from_session, %{id: message_id}, socket.assigns.session_id)
              {:noreply, stream_delete(socket, :messages, %{id: message_id})}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed")}
          end
        else
          {:noreply, put_flash(socket, :error, "Not yours")}
        end
    end
  end

  def handle_event("update-message", %{"content" => content}, socket) do
    {:noreply, assign(socket, :message_input, content)}
  end

  def handle_event("send-message", %{"content" => content}, socket) do
    content = String.trim(content)
    room = socket.assigns.room
    
    if content != "" do
      case Friends.create_message(%{
        user_id: socket.assigns.user_id,
        user_color: socket.assigns.user_color,
        user_name: socket.assigns.user_name,
        content: content,
        room_id: room.id
      }, room.code) do
        {:ok, message} ->
          Friends.broadcast(room.code, :new_message_from_session, message, socket.assigns.session_id)
          {:noreply,
           socket
           |> assign(:message_input, "")
           |> stream_insert(:messages, message)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Name Events ---

  def handle_event("open-name-modal", _params, socket) do
    {:noreply, socket |> assign(:show_name_modal, true) |> assign(:name_input, socket.assigns.user_name || "")}
  end

  def handle_event("close-name-modal", _params, socket) do
    {:noreply, assign(socket, :show_name_modal, false)}
  end

  def handle_event("update-name-input", %{"name" => name}, socket) do
    {:noreply, assign(socket, :name_input, name)}
  end

  def handle_event("save-name", %{"name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: nil, else: String.slice(name, 0, 20)
    
    {:noreply,
     socket
     |> assign(:user_name, name)
     |> assign(:show_name_modal, false)
     |> push_event("save_user_name", %{name: name})}
  end

  # --- Room Events ---

  def handle_event("open-room-modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, true)}
  end

  def handle_event("close-room-modal", _params, socket) do
    {:noreply, assign(socket, :show_room_modal, false)}
  end

  def handle_event("update-join-code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :join_room_code, code)}
  end

  def handle_event("update-room-name", %{"name" => name}, socket) do
    {:noreply, assign(socket, :new_room_name, name)}
  end

  def handle_event("join-room", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "")
    if code != "" do
      {:noreply,
       socket
       |> assign(:show_room_modal, false)
       |> assign(:join_room_code, "")
       |> push_navigate(to: ~p"/friends/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "Enter a room code")}
    end
  end

  def handle_event("create-room", %{"name" => name}, socket) do
    code = Friends.generate_room_code()
    name = if name == "", do: nil, else: String.trim(name)
    emoji = Enum.random(~w(📸 🎉 🌟 🔥 💫 🎨 🌈 ✨ 🎭 🎪 🍕 🎸 🌮 🍿))
    
    case Friends.create_room(%{code: code, name: name, emoji: emoji, created_by: socket.assigns.user_id}) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:show_room_modal, false)
         |> assign(:new_room_name, "")
         |> push_navigate(to: ~p"/friends/#{code}")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create")}
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
        {:ok, %{data_url: "data:#{content_type};base64,#{base64}", content_type: content_type, file_size: file_size}}
      end)

    room = socket.assigns.room

    case Friends.create_photo(%{
      user_id: socket.assigns.user_id,
      user_color: socket.assigns.user_color,
      user_name: socket.assigns.user_name,
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
         |> put_flash(:info, "📸 Shared!")}
      {:error, _} ->
        {:noreply, socket |> assign(:uploading, false) |> put_flash(:error, "Failed")}
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

  def handle_info({:new_photo, _}, socket), do: {:noreply, socket}

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

  def handle_info({:photo_deleted, _}, socket), do: {:noreply, socket}

  def handle_info({:new_message_from_session, message, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply, stream_insert(socket, :messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_message, _}, socket), do: {:noreply, socket}

  def handle_info({:message_deleted_from_session, %{id: id}, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply, stream_delete(socket, :messages, %{id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:message_deleted, _}, socket), do: {:noreply, socket}

  def handle_info(%{event: "presence_diff", payload: _}, socket) do
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
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  defp generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp format_time(datetime) do
    now = DateTime.utc_now()
    datetime = case datetime do
      %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
      %DateTime{} -> datetime
      _ -> DateTime.utc_now()
    end
    diff = DateTime.diff(now, datetime, :second)
    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
