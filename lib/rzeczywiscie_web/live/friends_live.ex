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

    is_connected = connected?(socket)

    # ALWAYS load data - even on static render for instant content
    # This makes the first page load show real content immediately
    photos = Friends.list_photos(room.id, 20)
    notes = Friends.list_room_text_cards(room.id)
    items = build_room_items(photos, notes)
    item_count = length(items)

    # Only subscribe when connected - presence tracking happens in set_user_id
    # when we have the real device fingerprint
    {messages, viewers, message_count} = if is_connected do
      Friends.subscribe(room.code)
      Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:presence:#{room.code}")
      # Don't track presence here - wait for set_user_id with real fingerprint
      
      msgs = Friends.list_messages(room.id, 50)
      v = Presence.list_users(room.code)
      {msgs, v, length(msgs)}
    else
      {[], [], 0}
    end

    # Build items map for quick lookup (only IDs and essential data)
    items_map = Map.new(items, fn item -> 
      key = "#{item.type}-#{item.id}"
      {key, item}
    end)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:user_color, user_color)
      |> assign(:user_name, nil)
      |> assign(:device_fingerprint, nil)
      |> assign(:is_linked_device, false)
      |> assign(:session_id, session_id)
      |> assign(:room, room)
      |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
      |> assign(:items_map, items_map)
      |> assign(:item_count, item_count)
      |> assign(:message_count, message_count)
      |> assign(:loading, false)
      |> assign(:chat_loading, not is_connected)
      |> assign(:message_input, "")
      |> assign(:viewers, viewers)
      |> assign(:uploading, false)
      |> assign(:show_room_modal, false)
      |> assign(:show_name_modal, false)
      |> assign(:show_link_modal, false)
      |> assign(:show_lightbox, false)
      |> assign(:lightbox_item, nil)
      |> assign(:join_room_code, "")
      |> assign(:new_room_name, "")
      |> assign(:name_input, "")
      |> assign(:link_code, nil)
      |> assign(:link_code_input, "")
      |> assign(:link_error, nil)
      |> assign(:name_error, nil)
      |> assign(:show_note_modal, false)
      |> assign(:note_input, "")
      |> assign(:show_photo_edit_modal, false)
      |> assign(:editing_photo, nil)
      |> assign(:photo_description_input, "")
      |> assign(:show_note_edit_modal, false)
      |> assign(:editing_note, nil)
      |> assign(:note_edit_input, "")
      # Map/location assigns
      |> assign(:view_mode, "feed")  # "feed" or "map"
      |> assign(:places, [])
      |> assign(:live_locations, [])
      |> assign(:sharing_location, false)
      |> assign(:location_expires_at, nil)
      |> assign(:show_place_modal, false)
      |> assign(:adding_place, false)
      |> assign(:new_place_lat, nil)
      |> assign(:new_place_lng, nil)
      |> assign(:new_place_name, "")
      |> assign(:new_place_description, "")
      |> assign(:new_place_emoji, "📍")
      |> stream(:items, items)
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
      Presence.track_user(self(), room.code, socket.assigns.user_id, socket.assigns.user_color, socket.assigns.user_name)
      
      photos = Friends.list_photos(room.id, 50)
      notes = Friends.list_room_text_cards(room.id)
      messages = Friends.list_messages(room.id, 100)
      viewers = Presence.list_users(room.code)
      items = build_room_items(photos, notes)
      items_map = Map.new(items, fn item -> {"#{item.type}-#{item.id}", item} end)
      
      {:noreply,
       socket
       |> assign(:room, room)
       |> assign(:page_title, "#{room.emoji} #{room.name || room.code}")
       |> assign(:items_map, items_map)
       |> assign(:item_count, length(items))
       |> assign(:message_count, length(messages))
       |> assign(:viewers, viewers)
       |> stream(:items, items, reset: true)
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
                
                <!-- My Board -->
                <.link
                  navigate="/friends/my-photos"
                  class="h-10 px-3 border-2 border-base-content font-bold uppercase text-sm bg-base-100 hover:bg-base-content hover:text-base-100 transition-colors flex items-center gap-2 cursor-pointer"
                >
                  <span>🎨</span>
                  <span class="hidden sm:inline">Board</span>
                </.link>
                
                <!-- User Name / Profile -->
                <button
                  type="button"
                  phx-click="open-name-modal"
                  class="h-10 px-3 border-2 border-base-content/30 hover:border-base-content transition-colors flex items-center gap-2 cursor-pointer"
                >
                  <div class="w-5 h-5 rounded-full border border-base-content" style={"background-color: #{@user_color}"}></div>
                  <span class="font-bold">{@user_name || if(is_nil(@device_fingerprint), do: "...", else: String.slice(@user_id, 0, 6))}</span>
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

              <div class="flex items-center gap-2">
                <!-- View Mode Tabs -->
                <div class="flex border-2 border-base-content">
                  <button
                    type="button"
                    phx-click="switch-view"
                    phx-value-mode="feed"
                    class={["h-10 px-3 font-bold text-sm cursor-pointer transition-colors", if(@view_mode == "feed", do: "bg-base-content text-base-100", else: "hover:bg-base-200")]}
                  >📷</button>
                  <button
                    type="button"
                    phx-click="switch-view"
                    phx-value-mode="map"
                    class={["h-10 px-3 font-bold text-sm cursor-pointer transition-colors border-l-2 border-base-content", if(@view_mode == "map", do: "bg-base-content text-base-100", else: "hover:bg-base-200")]}
                  >🗺️</button>
                </div>
                
                <%= if @view_mode == "feed" do %>
                  <!-- Add Note Button -->
                  <button
                    type="button"
                    phx-click="open-note-modal"
                    class="h-10 px-3 border-2 border-base-content font-bold uppercase text-sm bg-base-100 hover:bg-base-content hover:text-base-100 transition-colors flex items-center gap-2 cursor-pointer"
                  >
                    <span>📝</span>
                    <span class="hidden sm:inline">Note</span>
                  </button>

                  <!-- Upload Button -->
                  <form id="upload-form" phx-submit="save" phx-change="validate">
                <% else %>
                  <!-- Add Place Button -->
                  <button
                    type="button"
                    phx-click="toggle-add-place"
                    class={["h-10 px-3 border-2 border-base-content font-bold uppercase text-sm transition-colors flex items-center gap-2 cursor-pointer", if(@adding_place, do: "bg-primary text-primary-content border-primary", else: "bg-base-100 hover:bg-base-content hover:text-base-100")]}
                  >
                    <span>📍</span>
                    <span class="hidden sm:inline">{if @adding_place, do: "Click Map", else: "Add Place"}</span>
                  </button>
                  
                  <!-- Share Location Button -->
                  <button
                    type="button"
                    phx-click="toggle-location-sharing"
                    class={["h-10 px-3 border-2 font-bold uppercase text-sm transition-colors flex items-center gap-2 cursor-pointer", if(@sharing_location, do: "bg-success text-success-content border-success animate-pulse", else: "border-base-content bg-base-100 hover:bg-base-content hover:text-base-100")]}
                  >
                    <span>{if @sharing_location, do: "🔴", else: "📡"}</span>
                    <span class="hidden sm:inline">{if @sharing_location, do: "Sharing", else: "Share Location"}</span>
                  </button>
                <% end %>

                <%= if @view_mode == "feed" do %>
                <!-- Note: Upload form continues here -->
                    <label
                      for={@uploads.photo.ref}
                      class={[
                        "h-10 px-3 border-2 border-base-content font-bold uppercase text-sm transition-colors flex items-center gap-2 cursor-pointer",
                        if(@uploading, do: "bg-base-content text-base-100 opacity-70", else: "bg-primary text-primary-content hover:opacity-80")
                      ]}
                    >
                      <span>📷</span>
                      <span class="hidden sm:inline"><%= if @uploading, do: "...", else: "Photo" %></span>
                    </label>
                    <.live_file_input upload={@uploads.photo} class="sr-only" />
                  </form>
                <% end %>
              </div>
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

        <!-- Main Content: Photos/Map + Chat -->
        <div class="container mx-auto px-4 py-6">
          <div class="grid lg:grid-cols-3 gap-6">
            <!-- Content Grid (2/3) -->
            <div class="lg:col-span-2">
              <%= if @view_mode == "map" do %>
                <!-- Map View -->
                <div 
                  id="friends-map" 
                  phx-hook="FriendsMap"
                  phx-update="ignore"
                  data-places={Jason.encode!(@places)}
                  data-live-locations={Jason.encode!(@live_locations)}
                  data-adding-place={to_string(@adding_place)}
                  class="border-4 border-base-content bg-base-100 overflow-hidden"
                >
                  <div class="map-container" style="height: 500px;"></div>
                </div>
                
                <!-- Places List -->
                <%= if @places != [] do %>
                  <div class="mt-4 border-4 border-base-content bg-base-100">
                    <div class="p-3 border-b-2 border-base-content bg-base-200">
                      <h3 class="font-black uppercase text-sm">📍 Saved Places ({length(@places)})</h3>
                    </div>
                    <div class="divide-y-2 divide-base-content/20 max-h-60 overflow-y-auto">
                      <%= for place <- @places do %>
                        <div class="p-3 flex items-start gap-3 group hover:bg-base-200 transition-colors">
                          <div class="text-xl">{place.emoji}</div>
                          <div class="flex-1 min-w-0">
                            <div class="font-bold text-sm truncate">{place.name}</div>
                            <%= if place.description do %>
                              <div class="text-xs opacity-60 truncate">{place.description}</div>
                            <% end %>
                            <div class="text-[10px] opacity-40 flex items-center gap-1 mt-1">
                              <div class="w-2 h-2 rounded-full" style={"background: #{place.user_color}"}></div>
                              {place.user_name || "Anonymous"}
                            </div>
                          </div>
                          <%= if place.user_id == @user_id do %>
                            <button
                              type="button"
                              phx-click="delete-place"
                              phx-value-id={place.id}
                              data-confirm="Delete this place?"
                              class="opacity-0 group-hover:opacity-100 text-error text-xs cursor-pointer"
                            >✕</button>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% else %>
              <!-- Feed View (Photos + Notes) -->
              <%= cond do %>
                <% @loading -> %>
                  <%!-- Loading skeleton grid --%>
                  <div class="columns-2 sm:columns-3 gap-3 space-y-3">
                    <%= for i <- 1..6 do %>
                      <div class="border-4 border-base-content/30 bg-base-200 overflow-hidden break-inside-avoid animate-pulse">
                        <div class={"aspect-square bg-base-300 #{if rem(i, 3) == 0, do: "aspect-[3/4]", else: if(rem(i, 2) == 0, do: "aspect-[4/3]", else: "aspect-square")}"}></div>
                        <div class="p-2 border-t-2 border-base-content/30 bg-base-100 flex items-center gap-2">
                          <div class="w-3 h-3 rounded-full bg-base-300"></div>
                          <div class="h-2 bg-base-300 rounded w-16"></div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% @item_count == 0 -> %>
                  <div class="flex flex-col items-center justify-center py-16 text-center border-4 border-dashed border-base-content/20">
                    <div class="text-5xl mb-4">{@room.emoji}</div>
                    <h3 class="text-xl font-black uppercase mb-2 opacity-50">Nothing Here Yet</h3>
                    <p class="text-sm opacity-40 mb-4">Share the first photo or note in this room!</p>
                    <p class="text-xs font-mono opacity-30">kruk.live/friends/{@room.code}</p>
                  </div>
                <% true -> %>
                <div class="columns-2 sm:columns-3 gap-3 space-y-3" id="items-grid" phx-update="stream" phx-hook="PhotoGrid">
                  <%= for {dom_id, item} <- @streams.items do %>
                    <%= if item.type == :photo do %>
                      <div
                        id={dom_id}
                        class="photo-card group relative border-4 border-base-content bg-base-100 overflow-hidden hover:translate-x-0.5 hover:translate-y-0.5 transition-transform break-inside-avoid"
                      >
                        <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                        
                        <%= if item.user_id == @user_id do %>
                          <button
                            type="button"
                            phx-click="delete-photo"
                            phx-value-id={item.id}
                            data-confirm="Delete?"
                            class="absolute top-1 right-1 z-10 p-1.5 bg-error/90 text-error-content text-xs opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
                          >✕</button>
                        <% end %>
                        
                        <button
                          type="button"
                          phx-click="open-lightbox"
                          phx-value-id={item.id}
                          phx-value-type="photo"
                          class="overflow-hidden bg-base-200 w-full cursor-zoom-in block relative"
                        >
                          <%= if item.thumbnail_url do %>
                            <div class="photo-skeleton absolute inset-0 bg-base-300"></div>
                            <img src={item.thumbnail_url} alt="" class="photo-image w-full h-auto relative" loading="lazy" decoding="async" />
                          <% else %>
                            <%!-- Placeholder for photos without thumbnail --%>
                            <div class="aspect-square bg-base-300 flex items-center justify-center">
                              <div class="text-center opacity-50">
                                <div class="text-3xl mb-1">📷</div>
                                <div class="text-[10px]">Click to view</div>
                              </div>
                            </div>
                          <% end %>
                          <%= if item.description do %>
                            <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent p-2 pt-4">
                              <p class="text-white text-[10px] leading-tight line-clamp-2">{item.description}</p>
                            </div>
                          <% end %>
                        </button>
                        
                        <div class="p-2 border-t-2 border-base-content bg-base-100 flex items-center gap-2">
                          <div class="w-3 h-3 rounded-full border border-base-content flex-shrink-0" style={"background-color: #{item.user_color}"}></div>
                          <span class="text-[10px] font-bold truncate flex-1">
                            {item.user_name || String.slice(item.user_id, 0, 6)}
                          </span>
                          <span class="text-[10px] opacity-50 flex-shrink-0">{format_time(item.uploaded_at)}</span>
                        </div>
                      </div>
                    <% else %>
                      <%!-- Note card --%>
                      <div
                        id={dom_id}
                        class="note-card group relative border-4 border-base-content bg-base-200 overflow-hidden hover:translate-x-0.5 hover:translate-y-0.5 transition-transform break-inside-avoid"
                      >
                        <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
                        
                        <%= if item.user_id == @user_id do %>
                          <button
                            type="button"
                            phx-click="delete-note"
                            phx-value-id={item.id}
                            data-confirm="Delete?"
                            class="absolute top-1 right-1 z-10 p-1.5 bg-error/90 text-error-content text-xs opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer"
                          >✕</button>
                        <% end %>
                        
                        <button
                          type="button"
                          phx-click={if item.user_id == @user_id, do: "edit-note", else: "open-lightbox"}
                          phx-value-id={item.id}
                          phx-value-type="note"
                          class="w-full p-4 min-h-[120px] flex items-center justify-center cursor-pointer bg-base-200 hover:bg-base-300 text-base-content"
                        >
                          <p class="text-sm leading-relaxed text-center break-words line-clamp-6 text-base-content">{item.content}</p>
                        </button>
                        
                        <div class="p-2 border-t-2 border-base-content bg-base-100 flex items-center gap-2">
                          <div class="w-3 h-3 rounded-full border border-base-content flex-shrink-0" style={"background-color: #{item.user_color}"}></div>
                          <span class="text-[10px] font-bold truncate flex-1">
                            {item.user_name || String.slice(item.user_id, 0, 6)}
                          </span>
                          <span class="text-[10px] opacity-50 flex-shrink-0">{format_time(item.created_at)}</span>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
              <% end %>
            </div>

            <!-- Chat Panel (1/3) -->
            <div class="lg:col-span-1">
              <div class="border-4 border-base-content bg-base-100 h-[500px] flex flex-col">
                <!-- Chat Header -->
                <div class="p-3 border-b-2 border-base-content bg-base-200/50">
                  <h3 class="font-black uppercase text-sm">💬 Chat</h3>
                </div>

                <!-- Messages Wrapper -->
                <div class="flex-1 overflow-y-auto p-3 space-y-3 relative" id="messages-wrapper" phx-hook="ScrollToBottom">
                  
                  <!-- Empty State (absolute positioned) -->
                  <%= if !@chat_loading && @message_count == 0 do %>
                    <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
                      <div class="text-center text-sm opacity-40">
                        No messages yet.<br/>Say hi! 👋
                      </div>
                    </div>
                  <% end %>

                  <!-- Messages Stream -->
                  <div id="messages-container" phx-update="stream" class="space-y-3">
                    <%= if @chat_loading do %>
                      <%!-- Loading skeleton for messages --%>
                      <%= for i <- 1..3 do %>
                        <div class="flex gap-2 animate-pulse">
                          <div class="w-6 h-6 rounded-full bg-base-300 flex-shrink-0"></div>
                          <div class="flex-1">
                            <div class="h-2 bg-base-300 rounded w-20 mb-2"></div>
                            <div class={"h-4 bg-base-300 rounded #{if rem(i, 2) == 0, do: "w-32", else: "w-48"}"}></div>
                          </div>
                        </div>
                      <% end %>
                    <% else %>
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
                    <% end %>
                  </div>
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

        <!-- Lightbox Modal for Photos -->
        <%= if @show_lightbox && @lightbox_item && @lightbox_item.type == :photo do %>
          <div 
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 cursor-zoom-out"
            phx-click="close-lightbox"
          >
            <button 
              type="button" 
              phx-click="close-lightbox"
              class="absolute top-4 right-4 text-white text-3xl hover:opacity-60 z-10 cursor-pointer"
            >×</button>
            
            <%= if @lightbox_item.user_id == @user_id do %>
              <button
                type="button"
                phx-click="edit-photo-description"
                phx-value-id={@lightbox_item.id}
                class="absolute top-4 left-4 text-white text-sm px-3 py-2 bg-white/10 hover:bg-white/20 transition-colors z-10 flex items-center gap-2 cursor-pointer"
              >
                ✎ Edit
              </button>
            <% end %>
            
            <img 
              src={@lightbox_item.data_url} 
              alt={@lightbox_item.description || ""} 
              class="max-w-[95vw] max-h-[80vh] object-contain"
              phx-click="close-lightbox"
            />
            <div class="absolute bottom-4 left-1/2 -translate-x-1/2 bg-black/70 text-white px-4 py-2 rounded text-center max-w-md">
              <div class="flex items-center justify-center gap-3 mb-1">
                <div class="w-4 h-4 rounded-full" style={"background-color: #{@lightbox_item.user_color}"}></div>
                <span class="font-bold">{@lightbox_item.user_name || String.slice(@lightbox_item.user_id, 0, 6)}</span>
                <span class="opacity-60">{format_time(@lightbox_item.uploaded_at)}</span>
              </div>
              <%= if @lightbox_item.description do %>
                <p class="text-sm opacity-80 mt-1">{@lightbox_item.description}</p>
              <% end %>
            </div>
          </div>
        <% end %>
        
        <!-- Lightbox Modal for Notes -->
        <%= if @show_lightbox && @lightbox_item && @lightbox_item.type == :note do %>
          <div 
            class="fixed inset-0 z-50 flex items-center justify-center bg-black/90"
            phx-click="close-lightbox"
          >
            <button 
              type="button" 
              phx-click="close-lightbox"
              class="absolute top-4 right-4 text-white text-3xl hover:opacity-60 z-10 cursor-pointer"
            >×</button>
            
            <div class="bg-base-200 border-4 border-base-content p-8 max-w-lg mx-4">
              <p class="text-lg leading-relaxed text-center">{@lightbox_item.content}</p>
              <div class="mt-6 flex items-center justify-center gap-3 text-sm opacity-60">
                <div class="w-4 h-4 rounded-full" style={"background-color: #{@lightbox_item.user_color}"}></div>
                <span class="font-bold">{@lightbox_item.user_name || String.slice(@lightbox_item.user_id, 0, 6)}</span>
                <span>•</span>
                <span>{format_time(@lightbox_item.created_at)}</span>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Note Modal -->
        <%= if @show_note_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 overflow-y-auto" phx-hook="ModalScrollLock" id="note-modal-backdrop">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-md w-full shadow-2xl my-8" phx-click-away="close-note-modal">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-black uppercase">Add Note</h2>
                <button type="button" phx-click="close-note-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>
              
              <form phx-submit="save-note" phx-change="update-note-form" id="note-form">
                <div class="mb-4">
                  <textarea
                    name="content"
                    id="note-content"
                    value={@note_input}
                    placeholder="Write your note here..."
                    maxlength="500"
                    rows="6"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 resize-none focus:outline-none focus:ring-2 focus:ring-primary"
                    autofocus
                  >{@note_input}</textarea>
                  <p class="text-xs opacity-40 mt-1 text-right">{String.length(@note_input)}/500</p>
                </div>
                
                <button
                  type="submit"
                  disabled={String.trim(@note_input) == ""}
                  class="w-full px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                >
                  Share Note
                </button>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Note Edit Modal -->
        <%= if @show_note_edit_modal && @editing_note do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 overflow-y-auto" phx-hook="ModalScrollLock" id="note-edit-modal-backdrop">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-md w-full shadow-2xl my-8" phx-click-away="close-note-edit-modal">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-black uppercase">Edit Note</h2>
                <button type="button" phx-click="close-note-edit-modal" class="text-2xl leading-none hover:opacity-60 cursor-pointer">×</button>
              </div>
              
              <form phx-submit="save-note-edit" phx-change="update-note-edit-input" id="note-edit-form">
                <div class="mb-4">
                  <textarea
                    name="content"
                    value={@note_edit_input}
                    maxlength="500"
                    rows="6"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 resize-none focus:outline-none focus:ring-2 focus:ring-primary"
                    autofocus
                  >{@note_edit_input}</textarea>
                  <p class="text-xs opacity-40 mt-1 text-right">{String.length(@note_edit_input)}/500</p>
                </div>
                
                <div class="flex gap-2">
                  <button
                    type="submit"
                    disabled={String.trim(@note_edit_input) == ""}
                    class="flex-1 px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="delete-note"
                    phx-value-id={@editing_note.id}
                    data-confirm="Delete this note?"
                    class="px-4 py-3 border-2 border-error text-error font-bold uppercase cursor-pointer hover:bg-error hover:text-error-content transition-colors"
                  >
                    🗑
                  </button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Photo Edit Modal -->
        <%= if @show_photo_edit_modal && @editing_photo do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 overflow-y-auto" phx-hook="ModalScrollLock" id="photo-edit-modal-backdrop">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-lg w-full shadow-2xl my-8" phx-click-away="close-photo-edit-modal">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-black uppercase">Edit Photo</h2>
                <button type="button" phx-click="close-photo-edit-modal" class="text-2xl leading-none hover:opacity-60 cursor-pointer">×</button>
              </div>
              
              <!-- Photo Preview -->
              <div class="mb-4 border-2 border-base-content overflow-hidden">
                <img src={@editing_photo.thumbnail_url || @editing_photo.data_url} alt="" class="w-full h-48 object-cover" />
              </div>
              
              <!-- Description Input -->
              <form phx-submit="save-photo-description" phx-change="update-photo-description-form" id="photo-description-form">
                <div class="mb-4">
                  <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Description</label>
                  <textarea
                    name="description"
                    value={@photo_description_input}
                    placeholder="Add a short description (max 200 chars)"
                    maxlength="200"
                    rows="3"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 resize-none focus:outline-none focus:ring-2 focus:ring-primary"
                    autofocus
                  >{@photo_description_input}</textarea>
                  <p class="text-xs opacity-40 mt-1 text-right">{String.length(@photo_description_input)}/200</p>
                </div>
                
                <div class="flex gap-2">
                  <button
                    type="submit"
                    class="flex-1 px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase cursor-pointer"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="delete-photo"
                    phx-value-id={@editing_photo.id}
                    data-confirm="Are you sure you want to delete this photo?"
                    class="px-4 py-3 border-2 border-error text-error font-bold uppercase cursor-pointer hover:bg-error hover:text-error-content transition-colors"
                  >
                    🗑 Delete
                  </button>
                </div>
              </form>
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
                  <div class="font-bold">{@user_name || if(is_nil(@device_fingerprint), do: "...", else: String.slice(@user_id, 0, 6))}</div>
                  <div class="text-xs opacity-40 flex items-center gap-1">
                    ID: {String.slice(@user_id, 0, 8)}
                    <%= if @is_linked_device do %>
                      <span class="text-success">🔗</span>
                    <% end %>
                  </div>
                </div>
              </div>

              <!-- Change Name -->
              <form phx-submit="save-name" class="mb-6">
                <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Display Name</label>
                <div class="flex gap-2">
                  <input
                    type="text"
                    name="name"
                    value={@name_input}
                    phx-change="update-name-input"
                    placeholder="Enter name (max 20 chars)"
                    maxlength="20"
                    class={["flex-1 px-3 py-2 border-2 text-sm bg-base-100", if(@name_error, do: "border-error", else: "border-base-content")]}
                  />
                  <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold text-sm">
                    Save
                  </button>
                </div>
                <%= if @name_error do %>
                  <p class="text-xs text-error mt-2">{@name_error}</p>
                <% else %>
                  <p class="text-xs opacity-40 mt-2">Your name is linked to this device and reserved for you.</p>
                <% end %>
              </form>

              <!-- Link Devices -->
              <div class="pt-4 border-t-2 border-base-content/20">
                <button
                  type="button"
                  phx-click="open-link-modal"
                  class="w-full px-4 py-3 border-2 border-base-content font-bold uppercase text-sm hover:bg-base-content hover:text-base-100 transition-colors flex items-center justify-center gap-2"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
                  </svg>
                  <%= if @is_linked_device do %>
                    Manage Linked Devices
                  <% else %>
                    Link Another Device
                  <% end %>
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Link Device Modal -->
        <%= if @show_link_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-sm w-full shadow-2xl" phx-click-away="close-link-modal">
              <div class="flex justify-between items-center mb-6">
                <h2 class="text-xl font-black uppercase">Link Devices</h2>
                <button type="button" phx-click="close-link-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>

              <p class="text-sm opacity-60 mb-6">
                Use the same account on multiple devices (phone, tablet, computer). Your messages and photos will be shared across all linked devices.
              </p>

              <%= if @is_linked_device do %>
                <!-- Already Linked State -->
                <div class="mb-6 p-4 border-2 border-success/30 bg-success/10">
                  <div class="flex items-center gap-2 text-success font-bold mb-2">
                    <span class="text-xl">🔗</span>
                    <span>Device Linked</span>
                  </div>
                  <p class="text-sm opacity-60">This device is linked to account {String.slice(@user_id, 0, 8)}...</p>
                </div>
                
                <button
                  type="button"
                  phx-click="unlink-device"
                  data-confirm="Unlink this device? You'll get a new identity."
                  class="w-full px-4 py-3 border-2 border-error text-error font-bold uppercase text-sm hover:bg-error hover:text-error-content transition-colors"
                >
                  Unlink This Device
                </button>
              <% else %>
                <!-- Option 1: Generate Code (to link FROM this device) -->
                <div class="mb-6">
                  <h3 class="font-bold uppercase text-sm mb-3">📱 On your main device:</h3>
                  <%= if @link_code do %>
                    <div class="p-4 border-2 border-base-content bg-base-200 text-center">
                      <div class="text-3xl font-mono font-black tracking-widest mb-2">{@link_code}</div>
                      <p class="text-xs opacity-50">Enter this code on your other device. Valid for 5 minutes.</p>
                    </div>
                  <% else %>
                    <button
                      type="button"
                      phx-click="generate-link-code"
                      class="w-full px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase text-sm hover:bg-primary hover:border-primary transition-colors"
                    >
                      Generate Link Code
                    </button>
                  <% end %>
                </div>

                <div class="flex items-center gap-4 mb-6">
                  <div class="flex-1 border-t border-base-content/20"></div>
                  <span class="text-xs opacity-40 uppercase font-bold">or</span>
                  <div class="flex-1 border-t border-base-content/20"></div>
                </div>

                <!-- Option 2: Enter Code (to link TO another device) -->
                <div>
                  <h3 class="font-bold uppercase text-sm mb-3">📲 On your new device:</h3>
                  <form phx-submit="submit-link-code">
                    <div class="flex gap-2">
                      <input
                        type="text"
                        name="code"
                        value={@link_code_input}
                        phx-change="update-link-code-input"
                        placeholder="ABCD12"
                        maxlength="6"
                        class="flex-1 px-3 py-2 border-2 border-base-content text-sm bg-base-100 font-mono uppercase tracking-widest text-center"
                      />
                      <button type="submit" class="px-4 py-2 border-2 border-base-content bg-base-content text-base-100 font-bold text-sm">
                        Link
                      </button>
                    </div>
                    <%= if @link_error do %>
                      <p class="text-xs text-error mt-2">{@link_error}</p>
                    <% end %>
                  </form>
                </div>
              <% end %>
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

        <!-- Add Place Modal -->
        <%= if @show_place_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 overflow-y-auto" phx-hook="ModalScrollLock" id="place-modal-backdrop">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-md w-full shadow-2xl my-8" phx-click-away="close-place-modal">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-black uppercase">📍 Add Place</h2>
                <button type="button" phx-click="close-place-modal" class="text-2xl leading-none hover:opacity-60 cursor-pointer">×</button>
              </div>
              
              <form phx-submit="save-place" phx-change="update-place-form" id="place-form">
                <!-- Emoji Selector -->
                <div class="mb-4">
                  <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Icon</label>
                  <div class="flex flex-wrap gap-2">
                    <%= for emoji <- ["📍", "🍕", "🍺", "☕", "🏠", "🏢", "🎯", "⭐", "❤️", "🎉"] do %>
                      <button
                        type="button"
                        phx-click="update-place-form"
                        phx-value-emoji={emoji}
                        phx-value-name={@new_place_name}
                        phx-value-description={@new_place_description}
                        class={["w-10 h-10 text-xl border-2 cursor-pointer transition-colors", if(@new_place_emoji == emoji, do: "border-primary bg-primary/20", else: "border-base-content/30 hover:border-base-content")]}
                      >{emoji}</button>
                    <% end %>
                  </div>
                </div>
                
                <!-- Name -->
                <div class="mb-4">
                  <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Place Name</label>
                  <input
                    type="text"
                    name="name"
                    value={@new_place_name}
                    placeholder="e.g., Best Pizza in Town"
                    maxlength="100"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 focus:outline-none focus:ring-2 focus:ring-primary"
                    autofocus
                  />
                </div>
                
                <!-- Description -->
                <div class="mb-4">
                  <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Description (optional)</label>
                  <textarea
                    name="description"
                    value={@new_place_description}
                    placeholder="Add a note about this place..."
                    maxlength="500"
                    rows="3"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 resize-none focus:outline-none focus:ring-2 focus:ring-primary"
                  >{@new_place_description}</textarea>
                </div>
                
                <!-- Location Info -->
                <div class="mb-4 p-3 bg-base-200 border-2 border-base-content/20 text-xs font-mono">
                  📍 {Float.round(@new_place_lat || 0, 5)}, {Float.round(@new_place_lng || 0, 5)}
                </div>
                
                <button
                  type="submit"
                  disabled={String.trim(@new_place_name) == ""}
                  class="w-full px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                >
                  Save Place
                </button>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </.app>
    """
  end

  # --- Events ---

  def handle_event("set_user_id", %{"user_id" => device_fingerprint} = params, socket) do
    # Client sends device-specific user_id (fingerprint based on hardware)
    old_user_id = socket.assigns.user_id
    room = socket.assigns.room
    client_user_name = params["user_name"]
    client_linked_id = params["linked_user_id"]

    # Get device info from server (includes linked user_id and stored username)
    {server_user_id, server_user_name} = Friends.get_device_info(device_fingerprint)
    
    # Use server link first, then client stored link, then fingerprint
    {actual_user_id, is_linked} = cond do
      server_user_id != device_fingerprint -> {server_user_id, true}
      client_linked_id != nil && client_linked_id != "" -> {client_linked_id, true}
      true -> {device_fingerprint, false}
    end

    # Prefer server-stored username, fall back to client-stored
    user_name = server_user_name || client_user_name
    
    # Check if name is taken by another device (database) or user in room (presence)
    user_name = make_name_unique(device_fingerprint, room.code, user_name, actual_user_id)

    # Subscribe to username updates for this device
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, "friends:user:#{device_fingerprint}")

    # Generate color based on the actual user_id (consistent across linked devices)
    new_user_color = generate_user_color(actual_user_id)

    # Only untrack old presence if it was a different user_id (from initial mount)
    # and if we were already tracked (device_fingerprint was set)
    if socket.assigns.device_fingerprint != nil && old_user_id != actual_user_id do
      Presence.untrack(self(), room.code, old_user_id)
    end

    # Track presence with the real user info
    Presence.track_user(self(), room.code, actual_user_id, new_user_color, user_name)

    {:noreply,
     socket
     |> assign(:user_id, actual_user_id)
     |> assign(:user_color, new_user_color)
     |> assign(:user_name, user_name)
     |> assign(:device_fingerprint, device_fingerprint)
     |> assign(:is_linked_device, is_linked)
     |> assign(:chat_loading, false)
     |> push_event("linked_user_id", %{user_id: actual_user_id, is_linked: is_linked})
     |> push_event("save_user_name", %{name: user_name})}
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
              key = "photo-#{photo_id}"
              {:noreply,
               socket
               |> assign(:item_count, max(0, socket.assigns.item_count - 1))
               |> assign(:items_map, Map.delete(socket.assigns.items_map, key))
               |> stream_delete(:items, %{id: "photo-#{photo_id}"})
               |> put_flash(:info, "Deleted")}
            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed")}
          end
        else
          {:noreply, put_flash(socket, :error, "Not yours")}
        end
    end
  end

  def handle_event("open-lightbox", %{"id" => id, "type" => type}, socket) do
    key = "#{type}-#{id}"
    # Get basic item info from map
    item = Map.get(socket.assigns.items_map, key)
    
    # If it's a photo, we need to fetch the full data (image_data)
    full_item = if type == "photo" && item do
      case Friends.get_photo(item.id) do
        nil -> item
        photo -> 
          # Merge full photo data into the item map
          Map.merge(item, %{
            data_url: photo.image_data,
            thumbnail_url: photo.thumbnail_data || photo.image_data
          })
      end
    else
      item
    end

    {:noreply, socket |> assign(:show_lightbox, true) |> assign(:lightbox_item, full_item)}
  end

  def handle_event("open-lightbox", %{"id" => id}, socket) do
    # Fallback for photo-only calls
    handle_event("open-lightbox", %{"id" => id, "type" => "photo"}, socket)
  end

  def handle_event("close-lightbox", _params, socket) do
    {:noreply, socket |> assign(:show_lightbox, false) |> assign(:lightbox_item, nil)}
  end

  # --- Photo Edit Events ---

  def handle_event("edit-photo-description", %{"id" => id}, socket) do
    key = "photo-#{id}"
    photo = Map.get(socket.assigns.items_map, key)
    
    if photo && photo.user_id == socket.assigns.user_id do
      {:noreply,
       socket
       |> assign(:show_lightbox, false)
       |> assign(:lightbox_item, nil)
       |> assign(:show_photo_edit_modal, true)
       |> assign(:editing_photo, photo)
       |> assign(:photo_description_input, photo.description || "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-photo-edit-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_photo_edit_modal, false)
     |> assign(:editing_photo, nil)
     |> assign(:photo_description_input, "")}
  end

  def handle_event("update-photo-description-form", %{"description" => description}, socket) do
    {:noreply, assign(socket, :photo_description_input, description)}
  end

  def handle_event("save-photo-description", %{"description" => description}, socket) do
    user_id = socket.assigns.user_id
    photo = socket.assigns.editing_photo
    description = String.trim(description)
    description = if description == "", do: nil, else: description

    if user_id && photo do
      case Friends.update_photo_description(photo.id, description, user_id, with_room: false) do
        {:ok, updated_photo} ->
          updated_with_type = Map.put(updated_photo, :type, :photo)
          key = "photo-#{photo.id}"
          {:noreply,
           socket
           |> stream_insert(:items, updated_with_type)
           |> assign(:items_map, Map.put(socket.assigns.items_map, key, updated_with_type))
           |> assign(:show_photo_edit_modal, false)
           |> assign(:editing_photo, nil)
           |> assign(:photo_description_input, "")
           |> put_flash(:info, "Photo updated!")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update")}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle thumbnail from JS (sent after upload completes)
  def handle_event("set_thumbnail", %{"photo_id" => photo_id, "thumbnail" => thumbnail}, socket) do
    if socket.assigns.user_id && thumbnail do
      Friends.set_photo_thumbnail(photo_id, thumbnail, socket.assigns.user_id)
    end
    {:noreply, socket}
  end

  # Delete photo
  def handle_event("delete-photo", %{"id" => id}, socket) do
    photo_id = String.to_integer(id)
    user_id = socket.assigns.user_id
    key = "photo-#{photo_id}"

    case Friends.delete_photo(photo_id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:items, %{id: "items-#{key}"})
         |> assign(:items_map, Map.delete(socket.assigns.items_map, key))
         |> assign(:item_count, max(0, socket.assigns.item_count - 1))
         |> assign(:show_photo_edit_modal, false)
         |> assign(:editing_photo, nil)
         |> put_flash(:info, "Photo deleted")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete")}
    end
  end

  # --- Note Events ---

  def handle_event("open-note-modal", _params, socket) do
    {:noreply, socket |> assign(:show_note_modal, true) |> assign(:note_input, "")}
  end

  def handle_event("close-note-modal", _params, socket) do
    {:noreply, socket |> assign(:show_note_modal, false) |> assign(:note_input, "")}
  end

  def handle_event("update-note-form", %{"content" => content}, socket) do
    {:noreply, assign(socket, :note_input, content)}
  end

  def handle_event("save-note", %{"content" => content}, socket) do
    user_id = socket.assigns.user_id
    room = socket.assigns.room
    text = String.trim(content)

    if user_id && text != "" do
      case Friends.create_text_card(%{
        user_id: user_id,
        user_color: socket.assigns.user_color,
        user_name: socket.assigns.user_name,
        content: text,
        room_id: room.id
      }, room.code) do
        {:ok, card} ->
          card_with_type = Map.put(card, :type, :note)
          key = "note-#{card.id}"
          {:noreply,
           socket
           |> assign(:show_note_modal, false)
           |> assign(:note_input, "")
           |> assign(:items_map, Map.put(socket.assigns.items_map, key, card_with_type))
           |> assign(:item_count, socket.assigns.item_count + 1)
           |> stream_insert(:items, card_with_type, at: 0)
           |> put_flash(:info, "📝 Note shared!")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save note")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-note", %{"id" => id}, socket) do
    note_id = String.to_integer(id)
    user_id = socket.assigns.user_id
    key = "note-#{note_id}"

    case Friends.delete_text_card(note_id, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:items, %{id: "items-#{key}"})
         |> assign(:items_map, Map.delete(socket.assigns.items_map, key))
         |> assign(:item_count, max(0, socket.assigns.item_count - 1))
         |> assign(:show_note_edit_modal, false)
         |> assign(:editing_note, nil)
         |> put_flash(:info, "Note deleted")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete")}
    end
  end

  def handle_event("edit-note", %{"id" => id}, socket) do
    key = "note-#{id}"
    note = Map.get(socket.assigns.items_map, key)
    
    if note && note.user_id == socket.assigns.user_id do
      {:noreply,
       socket
       |> assign(:show_lightbox, false)
       |> assign(:lightbox_item, nil)
       |> assign(:show_note_edit_modal, true)
       |> assign(:editing_note, note)
       |> assign(:note_edit_input, note.content)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-note-edit-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_note_edit_modal, false)
     |> assign(:editing_note, nil)
     |> assign(:note_edit_input, "")}
  end

  def handle_event("update-note-edit-input", %{"content" => content}, socket) do
    {:noreply, assign(socket, :note_edit_input, content)}
  end

  def handle_event("save-note-edit", %{"content" => content}, socket) do
    user_id = socket.assigns.user_id
    note = socket.assigns.editing_note
    text = String.trim(content)

    if user_id && note && text != "" do
      case Friends.update_text_card(note.id, %{content: text}, user_id) do
        {:ok, updated} ->
          updated_with_type = Map.put(updated, :type, :note)
          key = "note-#{note.id}"
          {:noreply,
           socket
           |> stream_insert(:items, updated_with_type)
           |> assign(:items_map, Map.put(socket.assigns.items_map, key, updated_with_type))
           |> assign(:show_note_edit_modal, false)
           |> assign(:editing_note, nil)
           |> assign(:note_edit_input, "")
           |> put_flash(:info, "Note updated!")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update")}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Map/Location Events ---
  
  def handle_event("switch-view", %{"mode" => mode}, socket) do
    socket = assign(socket, :view_mode, mode)
    
    # Load places and live locations when switching to map
    socket = if mode == "map" do
      places = Friends.list_places(socket.assigns.room.id)
      live_locs = Presence.list_live_locations(socket.assigns.room.code)
      socket
      |> assign(:places, places)
      |> assign(:live_locations, live_locs)
    else
      socket
    end
    
    {:noreply, socket}
  end

  def handle_event("toggle-add-place", _params, socket) do
    {:noreply, assign(socket, :adding_place, !socket.assigns.adding_place)}
  end

  def handle_event("map_clicked", %{"lat" => lat, "lng" => lng}, socket) do
    if socket.assigns.adding_place do
      {:noreply,
       socket
       |> assign(:new_place_lat, lat)
       |> assign(:new_place_lng, lng)
       |> assign(:show_place_modal, true)
       |> assign(:adding_place, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-place-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_place_modal, false)
     |> assign(:new_place_lat, nil)
     |> assign(:new_place_lng, nil)
     |> assign(:new_place_name, "")
     |> assign(:new_place_description, "")
     |> assign(:new_place_emoji, "📍")}
  end

  def handle_event("update-place-form", params, socket) do
    {:noreply,
     socket
     |> assign(:new_place_name, params["name"] || "")
     |> assign(:new_place_description, params["description"] || "")
     |> assign(:new_place_emoji, params["emoji"] || "📍")}
  end

  def handle_event("save-place", _params, socket) do
    room = socket.assigns.room
    
    attrs = %{
      user_id: socket.assigns.user_id,
      user_name: socket.assigns.user_name,
      user_color: socket.assigns.user_color,
      name: String.trim(socket.assigns.new_place_name),
      description: String.trim(socket.assigns.new_place_description),
      emoji: socket.assigns.new_place_emoji,
      lat: socket.assigns.new_place_lat,
      lng: socket.assigns.new_place_lng
    }
    
    case Friends.create_place(attrs, room.code) do
      {:ok, place} ->
        {:noreply,
         socket
         |> assign(:places, [place | socket.assigns.places])
         |> assign(:show_place_modal, false)
         |> assign(:new_place_lat, nil)
         |> assign(:new_place_lng, nil)
         |> assign(:new_place_name, "")
         |> assign(:new_place_description, "")
         |> assign(:new_place_emoji, "📍")
         |> push_event("add_place_marker", place)}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save place")}
    end
  end

  def handle_event("delete-place", %{"id" => id}, socket) do
    place_id = String.to_integer(id)
    
    case Friends.delete_place(place_id, socket.assigns.user_id, socket.assigns.room.code) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:places, Enum.reject(socket.assigns.places, &(&1.id == place_id)))
         |> push_event("remove_place_marker", %{id: place_id})}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Cannot delete")}
    end
  end

  def handle_event("toggle-location-sharing", _params, socket) do
    room = socket.assigns.room
    user_id = socket.assigns.user_id
    
    if socket.assigns.sharing_location do
      # Stop sharing
      Presence.stop_sharing_location(self(), room.code, user_id)
      {:noreply,
       socket
       |> assign(:sharing_location, false)
       |> assign(:location_expires_at, nil)}
    else
      # Start sharing - request location from browser
      {:noreply, push_event(socket, "request_location", %{})}
    end
  end

  def handle_event("location_update", %{"lat" => lat, "lng" => lng}, socket) do
    room = socket.assigns.room
    user_id = socket.assigns.user_id
    
    # Set expiration to 2 hours from now
    expires_at = System.system_time(:second) + (2 * 60 * 60)
    
    Presence.update_location(self(), room.code, user_id, lat, lng, expires_at)
    
    {:noreply,
     socket
     |> assign(:sharing_location, true)
     |> assign(:location_expires_at, expires_at)}
  end

  def handle_event("location_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Could not get your location")}
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
              {:noreply,
               socket
               |> assign(:message_count, max(0, socket.assigns.message_count - 1))
               |> stream_delete(:messages, %{id: message_id})}
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
           |> assign(:message_count, socket.assigns.message_count + 1)
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
    {:noreply, socket |> assign(:show_name_modal, true) |> assign(:name_input, socket.assigns.user_name || "") |> assign(:name_error, nil)}
  end

  def handle_event("close-name-modal", _params, socket) do
    {:noreply, assign(socket, :show_name_modal, false)}
  end

  def handle_event("update-name-input", %{"name" => name}, socket) do
    {:noreply, socket |> assign(:name_input, name) |> assign(:name_error, nil)}
  end

  def handle_event("save-name", %{"name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: nil, else: String.slice(name, 0, 20)
    device_fingerprint = socket.assigns.device_fingerprint
    
    # Check if name is taken - both in database (permanent) and presence (current room)
    name_taken = name != nil && name_is_taken?(name, device_fingerprint, socket.assigns.room.code, socket.assigns.user_id)
    
    if name_taken do
      {:noreply, assign(socket, :name_error, "Name already taken")}
    else
      # Save username to server (linked to device fingerprint)
      # This also updates all historical content (messages, photos, text cards)
      if device_fingerprint do
        Friends.save_username(device_fingerprint, name)
        # Broadcast to all sessions of this device
        Phoenix.PubSub.broadcast(
          Rzeczywiscie.PubSub,
          "friends:user:#{device_fingerprint}",
          {:username_changed, name}
        )
        # Broadcast to room so all clients update their view of this user's content
        Friends.broadcast(socket.assigns.room.code, :user_renamed, %{
          user_id: socket.assigns.user_id,
          new_name: name
        })
      end
      
      # Update presence with the new name
      Presence.update_user(self(), socket.assigns.room.code, socket.assigns.user_id, socket.assigns.user_color, name)
      
      {:noreply,
       socket
       |> assign(:user_name, name)
       |> assign(:name_error, nil)
       |> assign(:show_name_modal, false)
       |> push_event("save_user_name", %{name: name})}
    end
  end

  # --- Device Linking Events ---

  def handle_event("open-link-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_name_modal, false)
     |> assign(:show_link_modal, true)
     |> assign(:link_code, nil)
     |> assign(:link_code_input, "")
     |> assign(:link_error, nil)}
  end

  def handle_event("close-link-modal", _params, socket) do
    {:noreply, assign(socket, :show_link_modal, false)}
  end

  def handle_event("generate-link-code", _params, socket) do
    case Friends.generate_link_code(socket.assigns.user_id) do
      {:ok, code} ->
        {:noreply, socket |> assign(:link_code, code) |> assign(:link_error, nil)}
      {:error, _} ->
        {:noreply, assign(socket, :link_error, "Failed to generate code")}
    end
  end

  def handle_event("update-link-code-input", %{"code" => code}, socket) do
    {:noreply, assign(socket, :link_code_input, String.upcase(code))}
  end

  def handle_event("submit-link-code", %{"code" => code}, socket) do
    device_fingerprint = socket.assigns.device_fingerprint
    
    if device_fingerprint == nil do
      {:noreply, assign(socket, :link_error, "Device not identified yet")}
    else
      case Friends.link_device(code, device_fingerprint) do
        {:ok, master_user_id} ->
          old_user_id = socket.assigns.user_id
          room = socket.assigns.room
          
          # Update presence if user_id changed
          if old_user_id != master_user_id do
            Presence.untrack(self(), room.code, old_user_id)
            new_user_color = generate_user_color(master_user_id)
            Presence.track_user(self(), room.code, master_user_id, new_user_color, socket.assigns.user_name)
            
            {:noreply,
             socket
             |> assign(:user_id, master_user_id)
             |> assign(:user_color, new_user_color)
             |> assign(:is_linked_device, true)
             |> assign(:show_link_modal, false)
             |> assign(:link_error, nil)
             |> push_event("linked_user_id", %{user_id: master_user_id, is_linked: true})
             |> put_flash(:info, "✅ Device linked successfully!")}
          else
            {:noreply,
             socket
             |> assign(:is_linked_device, true)
             |> assign(:show_link_modal, false)
             |> put_flash(:info, "✅ Already using this account!")}
          end
          
        {:error, :invalid_code} ->
          {:noreply, assign(socket, :link_error, "Invalid code")}
          
        {:error, :expired_code} ->
          {:noreply, assign(socket, :link_error, "Code expired")}
          
        {:error, _} ->
          {:noreply, assign(socket, :link_error, "Failed to link")}
      end
    end
  end

  def handle_event("unlink-device", _params, socket) do
    device_fingerprint = socket.assigns.device_fingerprint
    
    if device_fingerprint do
      Friends.unlink_device(device_fingerprint)
      
      # Revert to device fingerprint as user_id
      old_user_id = socket.assigns.user_id
      room = socket.assigns.room
      
      if old_user_id != device_fingerprint do
        Presence.untrack(self(), room.code, old_user_id)
        new_user_color = generate_user_color(device_fingerprint)
        Presence.track_user(self(), room.code, device_fingerprint, new_user_color, socket.assigns.user_name)
        
        {:noreply,
         socket
         |> assign(:user_id, device_fingerprint)
         |> assign(:user_color, new_user_color)
         |> assign(:is_linked_device, false)
         |> assign(:show_link_modal, false)
         |> push_event("linked_user_id", %{user_id: nil, is_linked: false})
         |> put_flash(:info, "Device unlinked")}
      else
        {:noreply,
         socket
         |> assign(:is_linked_device, false)
         |> assign(:show_link_modal, false)}
      end
    else
      {:noreply, socket}
    end
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
        photo_with_type = Map.put(photo, :type, :photo)
        key = "photo-#{photo.id}"
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:items_map, Map.put(socket.assigns.items_map, key, photo_with_type))
         |> assign(:item_count, socket.assigns.item_count + 1)
         |> stream_insert(:items, photo_with_type, at: 0)
         |> push_event("photo_uploaded", %{photo_id: photo.id})
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
      photo_with_type = Map.put(photo, :type, :photo)
      key = "photo-#{photo.id}"
      {:noreply,
       socket
       |> assign(:items_map, Map.put(socket.assigns.items_map, key, photo_with_type))
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, photo_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_note, note}, socket) do
    # Note was added by another user in this room
    if note.user_id != socket.assigns.user_id do
      note_with_type = Map.put(note, :type, :note)
      key = "note-#{note.id}"
      {:noreply,
       socket
       |> assign(:items_map, Map.put(socket.assigns.items_map, key, note_with_type))
       |> assign(:item_count, socket.assigns.item_count + 1)
       |> stream_insert(:items, note_with_type, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_photo, _}, socket), do: {:noreply, socket}

  def handle_info({:photo_deleted_from_session, %{id: id}, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      key = "photo-#{id}"
      {:noreply,
       socket
       |> assign(:item_count, max(0, socket.assigns.item_count - 1))
       |> assign(:items_map, Map.delete(socket.assigns.items_map, key))
       |> stream_delete(:items, %{id: key})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:photo_deleted, _}, socket), do: {:noreply, socket}

  # Handle user rename - update all their content in our local view
  def handle_info({:user_renamed, %{user_id: user_id, new_name: new_name}}, socket) do
    # Reload items and messages from database (they've been updated server-side)
    room = socket.assigns.room
    photos = Friends.list_photos(room.id, 50)
    notes = Friends.list_room_text_cards(room.id)
    messages = Friends.list_messages(room.id, 100)
    
    # Rebuild items
    items = build_room_items(photos, notes)
    items_map = Map.new(items, fn item ->
      key = if item.type == :photo, do: "photo-#{item.id}", else: "note-#{item.id}"
      {key, Map.put(item, :id, key)}
    end)
    
    {:noreply,
     socket
     |> assign(:items_map, items_map)
     |> stream(:items, Map.values(items_map), reset: true)
     |> stream(:messages, messages, reset: true)}
  end

  def handle_info({:new_message_from_session, message, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:message_count, socket.assigns.message_count + 1)
       |> stream_insert(:messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:new_message, _}, socket), do: {:noreply, socket}

  def handle_info({:message_deleted_from_session, %{id: id}, from_session_id}, socket) do
    if from_session_id != socket.assigns.session_id do
      {:noreply,
       socket
       |> assign(:message_count, max(0, socket.assigns.message_count - 1))
       |> stream_delete(:messages, %{id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:message_deleted, _}, socket), do: {:noreply, socket}

  def handle_info(%{event: "presence_diff", payload: _}, socket) do
    viewers = Presence.list_users(socket.assigns.room.code)
    # Also update live locations if we're on the map view
    socket = if socket.assigns.view_mode == "map" do
      live_locs = Presence.list_live_locations(socket.assigns.room.code)
      socket
      |> assign(:live_locations, live_locs)
      |> push_event("update_live_locations", %{locations: live_locs})
    else
      socket
    end
    {:noreply, assign(socket, :viewers, viewers)}
  end

  # Handle new place added by another user
  def handle_info({:new_place, place}, socket) do
    {:noreply,
     socket
     |> assign(:places, [place | socket.assigns.places])
     |> push_event("add_place_marker", place)}
  end

  # Handle place deleted by another user
  def handle_info({:place_deleted, %{id: place_id}}, socket) do
    {:noreply,
     socket
     |> assign(:places, Enum.reject(socket.assigns.places, &(&1.id == place_id)))
     |> push_event("remove_place_marker", %{id: place_id})}
  end

  # Handle username changes from other sessions of the same device
  def handle_info({:username_changed, new_name}, socket) do
    room = socket.assigns.room
    user_id = socket.assigns.user_id
    user_color = socket.assigns.user_color

    # Update presence with the new name
    Presence.update_user(self(), room.code, user_id, user_color, new_name)

    {:noreply,
     socket
     |> assign(:user_name, new_name)
     |> push_event("save_user_name", %{name: new_name})}
  end

  # --- Helpers ---

  defp get_or_create_user_id(_socket) do
    # Generate a random temporary ID - will be replaced by device fingerprint from client
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_user_color(user_id) do
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  defp generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  
  # Check if name is taken (globally in database OR in current room presence)
  defp name_is_taken?(name, device_fingerprint, room_code, user_id) do
    # Check database for permanent reservations
    db_taken = Friends.username_taken?(name, device_fingerprint || "")
    # Check presence for users currently in room (belt and suspenders)
    presence_taken = Presence.name_taken?(room_code, name, user_id)
    db_taken || presence_taken
  end
  
  # Make username unique by adding suffix if needed
  defp make_name_unique(_device_fingerprint, _room_code, nil, _user_id), do: nil
  defp make_name_unique(_device_fingerprint, _room_code, "", _user_id), do: nil
  defp make_name_unique(device_fingerprint, room_code, name, user_id) do
    if name_is_taken?(name, device_fingerprint, room_code, user_id) do
      # Name is taken, find a unique variant
      find_unique_name(device_fingerprint, room_code, name, user_id, 2)
    else
      name
    end
  end
  
  defp find_unique_name(device_fingerprint, room_code, base_name, user_id, counter) when counter < 100 do
    candidate = "#{base_name}#{counter}"
    if name_is_taken?(candidate, device_fingerprint, room_code, user_id) do
      find_unique_name(device_fingerprint, room_code, base_name, user_id, counter + 1)
    else
      candidate
    end
  end
  defp find_unique_name(_device_fingerprint, _room_code, base_name, _user_id, _counter), do: base_name

  # Build combined items list from photos and notes
  defp build_room_items(photos, notes) do
    photo_items = Enum.map(photos, &Map.put(&1, :type, :photo))
    note_items = Enum.map(notes, &Map.put(&1, :type, :note))
    
    (photo_items ++ note_items)
    |> Enum.sort_by(fn item ->
      timestamp = Map.get(item, :uploaded_at) || Map.get(item, :created_at)
      case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp)
        %NaiveDateTime{} -> NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
    end, :desc)
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
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end
end
