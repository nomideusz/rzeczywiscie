defmodule RzeczywiscieWeb.UserPhotosLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Friends

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:user_id, nil)
      |> assign(:user_name, nil)
      |> assign(:user_color, nil)
      |> assign(:items, [])
      |> assign(:item_count, 0)
      |> assign(:page_title, "My Board")
      |> assign(:show_lightbox, false)
      |> assign(:lightbox_item, nil)
      |> assign(:reordering, false)
      |> assign(:show_text_modal, false)
      |> assign(:editing_card, nil)
      |> assign(:text_input, "")
      # Photo editing
      |> assign(:show_photo_modal, false)
      |> assign(:editing_photo, nil)
      |> assign(:photo_description_input, "")

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="min-h-screen bg-base-200" id="user-photos-app" phx-hook="UserPhotosApp">
        <!-- Header -->
        <div class="border-b-4 border-base-content bg-base-100">
          <div class="container mx-auto px-4 py-4">
            <div class="flex items-center justify-between flex-wrap gap-3">
              <div class="flex items-center gap-4">
                <.link navigate="/friends" class="text-2xl hover:opacity-60 transition-opacity">←</.link>
                <div class="flex items-center gap-3">
                  <%= if @user_color do %>
                    <div class="w-10 h-10 rounded-full border-2 border-base-content" style={"background-color: #{@user_color}"}></div>
                  <% end %>
                  <div>
                    <h1 class="text-2xl font-black uppercase tracking-tight">
                      <%= if @user_name do %>
                        {@user_name}'s Board
                      <% else %>
                        My Board
                      <% end %>
                    </h1>
                    <p class="text-xs opacity-50">{@item_count} items</p>
                  </div>
                </div>
              </div>
              
              <div class="flex items-center gap-2">
                <!-- Add Note Button -->
                <button
                  type="button"
                  phx-click="open-text-modal"
                  class="px-4 py-2 border-2 border-base-content font-bold text-sm uppercase hover:bg-base-content hover:text-base-100 transition-colors flex items-center gap-2"
                >
                  <span class="text-lg">📝</span>
                  <span class="hidden sm:inline">Add Note</span>
                </button>
                
                <%= if @item_count > 1 do %>
                  <button
                    type="button"
                    phx-click="toggle-reorder"
                    class={[
                      "px-4 py-2 border-2 border-base-content font-bold text-sm uppercase transition-colors",
                      if(@reordering, do: "bg-primary text-primary-content", else: "hover:bg-base-content hover:text-base-100")
                    ]}
                  >
                    <%= if @reordering do %>
                      ✓ Done
                    <% else %>
                      ↕ Reorder
                    <% end %>
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <!-- Items Grid -->
        <div class="container mx-auto px-4 py-6">
          <%= if @items == [] do %>
            <div class="flex flex-col items-center justify-center py-16 text-center border-4 border-dashed border-base-content/20 bg-base-100">
              <div class="text-5xl mb-4">🎨</div>
              <h3 class="text-xl font-black uppercase mb-2 opacity-50">Your Board is Empty</h3>
              <p class="text-sm opacity-40 mb-6">Share photos in rooms or add text cards!</p>
              <div class="flex gap-3">
                <.link navigate="/friends" class="px-6 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase hover:opacity-80 transition-opacity">
                  Go to Friends
                </.link>
                <button
                  type="button"
                  phx-click="open-text-modal"
                  class="px-6 py-3 border-2 border-base-content font-bold uppercase hover:bg-base-content hover:text-base-100 transition-colors"
                >
                  Add Note
                </button>
              </div>
            </div>
          <% else %>
            <div
              id="user-items-grid"
              class={[
                "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4",
                if(@reordering, do: "reorder-mode", else: "")
              ]}
              phx-hook="SortablePhotos"
              data-reordering={to_string(@reordering)}
            >
              <%= for item <- @items do %>
                <%= if item.type == :photo do %>
                  {render_photo_card(assigns, item)}
                <% else %>
                  {render_text_card(assigns, item)}
                <% end %>
              <% end %>
            </div>
            
            <%= if @reordering do %>
              <p class="text-center text-sm opacity-50 mt-6">
                Drag items to rearrange • Changes save automatically
              </p>
            <% end %>
          <% end %>
        </div>

        <!-- Photo Lightbox -->
        <%= if @show_lightbox && @lightbox_item && @lightbox_item.type == :photo do %>
          <div
            class="fixed inset-0 z-50 bg-black/95 flex items-center justify-center"
            phx-click="close-lightbox"
            phx-window-keydown="close-lightbox"
            phx-key="Escape"
          >
            <button
              type="button"
              class="absolute top-4 right-4 text-white text-3xl hover:opacity-60 z-10"
              phx-click="close-lightbox"
            >×</button>
            
            <!-- Edit button -->
            <button
              type="button"
              class="absolute top-4 left-4 text-white text-sm px-3 py-2 bg-white/10 hover:bg-white/20 transition-colors z-10 flex items-center gap-2"
              phx-click="edit-photo"
              phx-value-id={@lightbox_item.id}
            >
              ✎ Edit
            </button>
            
            <div class="max-w-4xl max-h-[90vh] p-4" phx-click="close-lightbox">
              <img
                src={@lightbox_item.data_url}
                alt={@lightbox_item.description || ""}
                class="max-w-full max-h-[70vh] object-contain border-4 border-white/20"
              />
              <div class="mt-4 text-white/80 text-center">
                <div>
                  <span class="text-lg">{@lightbox_item.room_emoji} {@lightbox_item.room_name}</span>
                  <span class="mx-2 opacity-40">•</span>
                  <span class="opacity-60">{format_time(@lightbox_item.uploaded_at)}</span>
                </div>
                <%= if @lightbox_item.description do %>
                  <p class="mt-3 text-white/90 text-base max-w-lg mx-auto">{@lightbox_item.description}</p>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Photo Edit Modal -->
        <%= if @show_photo_modal && @editing_photo do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-lg w-full shadow-2xl" phx-click-away="close-photo-modal">
              <div class="flex justify-between items-center mb-6">
                <h2 class="text-xl font-black uppercase">Edit Photo</h2>
                <button type="button" phx-click="close-photo-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>
              
              <!-- Photo Preview -->
              <div class="mb-6 border-4 border-base-content overflow-hidden">
                <img
                  src={@editing_photo.data_url}
                  alt=""
                  class="w-full h-48 object-cover"
                />
              </div>
              
              <!-- Description Input -->
              <div class="mb-6">
                <label class="text-xs font-bold uppercase opacity-60 mb-2 block">Description</label>
                <textarea
                  phx-change="update-photo-description-input"
                  name="description"
                  value={@photo_description_input}
                  placeholder="Add a short description (max 200 chars)"
                  maxlength="200"
                  rows="3"
                  class="w-full px-3 py-2 border-2 border-base-content text-sm bg-base-100 resize-none"
                >{@photo_description_input}</textarea>
                <p class="text-xs opacity-40 mt-1">{String.length(@photo_description_input || "")}/200</p>
              </div>
              
              <!-- Photo Info -->
              <div class="mb-6 p-3 bg-base-200 text-sm">
                <div class="flex items-center gap-2 mb-1">
                  <span>{@editing_photo.room_emoji}</span>
                  <span class="font-bold">{@editing_photo.room_name}</span>
                </div>
                <div class="text-xs opacity-50">{format_time(@editing_photo.uploaded_at)}</div>
              </div>
              
              <!-- Actions -->
              <div class="flex gap-3">
                <button
                  type="button"
                  phx-click="save-photo-description"
                  class="flex-1 px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase"
                >
                  Save
                </button>
                <button
                  type="button"
                  phx-click="close-photo-modal"
                  class="px-4 py-3 border-2 border-base-content font-bold uppercase hover:bg-base-200 transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Text Card Modal -->
        <%= if @show_text_modal do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 overflow-y-auto" phx-hook="ModalScrollLock" id="text-card-modal-backdrop">
            <div class="bg-base-100 border-4 border-base-content p-6 max-w-md w-full shadow-2xl my-8" phx-click-away="close-text-modal">
              <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-black uppercase">
                  <%= if @editing_card, do: "Edit Note", else: "New Note" %>
                </h2>
                <button type="button" phx-click="close-text-modal" class="text-2xl leading-none hover:opacity-60">×</button>
              </div>
              
              <!-- Text Input Form -->
              <form phx-submit="save-text-card" phx-change="update-text-form" id="text-card-form">
                <div class="mb-4">
                  <textarea
                    name="content"
                    id="text-card-content"
                    value={@text_input}
                    placeholder="Write your note here..."
                    maxlength="500"
                    rows="6"
                    class="w-full px-4 py-3 border-2 border-base-content text-base bg-base-100 resize-none focus:outline-none focus:ring-2 focus:ring-primary"
                    autofocus
                  >{@text_input}</textarea>
                  <p class="text-xs opacity-40 mt-1 text-right">{String.length(@text_input)}/500</p>
                </div>
                
                <!-- Actions -->
                <div class="flex gap-3">
                  <button
                    type="submit"
                    disabled={String.trim(@text_input) == ""}
                    class="flex-1 px-4 py-3 border-2 border-base-content bg-base-content text-base-100 font-bold uppercase disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    <%= if @editing_card, do: "Save", else: "Add Note" %>
                  </button>
                  <%= if @editing_card do %>
                    <button
                      type="button"
                      phx-click="delete-text-card"
                      phx-value-id={@editing_card.id}
                      data-confirm="Delete this note?"
                      class="px-4 py-3 border-2 border-error text-error font-bold uppercase hover:bg-error hover:text-error-content transition-colors"
                    >
                      Delete
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </.app>
    """
  end

  defp render_photo_card(assigns, photo) do
    assigns = assign(assigns, :photo, photo)

    ~H"""
    <div
      id={"photo-#{@photo.id}"}
      data-id={"photo-#{@photo.id}"}
      class={[
        "photo-item group relative border-4 border-base-content bg-base-100 overflow-hidden",
        if(@reordering, do: "cursor-grab active:cursor-grabbing", else: "cursor-zoom-in hover:translate-x-0.5 hover:translate-y-0.5"),
        "transition-transform"
      ]}
    >
      <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
      
      <%= if @reordering do %>
        <div class="absolute inset-0 z-10 flex items-center justify-center bg-base-content/20 opacity-0 group-hover:opacity-100 transition-opacity">
          <div class="text-4xl text-base-content/60">⋮⋮</div>
        </div>
      <% end %>
      
      <button
        type="button"
        phx-click={unless @reordering, do: "open-lightbox"}
        phx-value-id={@photo.id}
        phx-value-type="photo"
        class="w-full aspect-square overflow-hidden bg-base-200 block relative"
        disabled={@reordering}
      >
        <img
          src={@photo.data_url}
          alt={@photo.description || ""}
          class="w-full h-full object-cover"
          loading="lazy"
          draggable="false"
        />
        <%= if @photo.description do %>
          <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent p-2 pt-6">
            <p class="text-white text-[10px] leading-tight line-clamp-2">{@photo.description}</p>
          </div>
        <% end %>
      </button>
      
      <div class="p-2 border-t-2 border-base-content bg-base-100">
        <div class="flex items-center gap-1 text-[10px]">
          <span class="opacity-40">{@photo.room_emoji}</span>
          <span class="font-bold truncate">{@photo.room_name}</span>
        </div>
        <div class="text-[9px] opacity-40">{format_time(@photo.uploaded_at)}</div>
      </div>
    </div>
    """
  end

  defp render_text_card(assigns, card) do
    assigns = assign(assigns, :card, card)

    ~H"""
    <div
      id={"text-#{@card.id}"}
      data-id={"text-#{@card.id}"}
      class={[
        "photo-item group relative border-4 border-base-content overflow-hidden bg-base-100",
        if(@reordering, do: "cursor-grab active:cursor-grabbing", else: "cursor-pointer hover:translate-x-0.5 hover:translate-y-0.5"),
        "transition-transform"
      ]}
    >
      <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
      
      <%= if @reordering do %>
        <div class="absolute inset-0 z-10 flex items-center justify-center bg-base-content/20 opacity-0 group-hover:opacity-100 transition-opacity">
          <div class="text-4xl text-base-content/60">⋮⋮</div>
        </div>
      <% end %>
      
      <button
        type="button"
        phx-click={unless @reordering, do: "edit-text-card"}
        phx-value-id={@card.id}
        class="w-full aspect-square flex items-center justify-center p-4 bg-base-200"
        disabled={@reordering}
      >
        <p class="text-center text-sm leading-relaxed break-words max-w-full line-clamp-6">
          {@card.content}
        </p>
      </button>
      
      <div class="p-2 border-t-2 border-base-content bg-base-100">
        <div class="flex items-center gap-1 text-[10px]">
          <span class="opacity-40">📝</span>
          <span class="font-bold">Note</span>
        </div>
        <div class="text-[9px] opacity-40">{format_time(@card.created_at)}</div>
      </div>
    </div>
    """
  end

  # Handle device fingerprint from JS hook
  def handle_event("set_user_id", %{"user_id" => device_fingerprint, "user_name" => user_name}, socket) do
    linked_id = Friends.get_linked_user_id(device_fingerprint)
    user_id = linked_id || device_fingerprint
    user_color = generate_user_color(user_id)
    
    items = Friends.list_user_items(user_id)
    
    {:noreply,
     socket
     |> assign(:user_id, user_id)
     |> assign(:user_name, user_name)
     |> assign(:user_color, user_color)
     |> assign(:items, items)
     |> assign(:item_count, length(items))}
  end

  def handle_event("toggle-reorder", _params, socket) do
    {:noreply, assign(socket, :reordering, !socket.assigns.reordering)}
  end

  def handle_event("reorder-photos", %{"order" => item_ids}, socket) do
    user_id = socket.assigns.user_id
    
    if user_id do
      Friends.reorder_user_items(user_id, item_ids)
      items = Friends.list_user_items(user_id)
      {:noreply, assign(socket, :items, items)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-lightbox", %{"id" => id, "type" => "photo"}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.type == :photo && &1.id == String.to_integer(id)))
    {:noreply, socket |> assign(:show_lightbox, true) |> assign(:lightbox_item, item)}
  end

  def handle_event("close-lightbox", _params, socket) do
    {:noreply, socket |> assign(:show_lightbox, false) |> assign(:lightbox_item, nil)}
  end

  # Photo Edit Events
  def handle_event("edit-photo", %{"id" => id}, socket) do
    photo = Enum.find(socket.assigns.items, &(&1.type == :photo && &1.id == String.to_integer(id)))
    
    if photo do
      {:noreply,
       socket
       |> assign(:show_lightbox, false)
       |> assign(:lightbox_item, nil)
       |> assign(:show_photo_modal, true)
       |> assign(:editing_photo, photo)
       |> assign(:photo_description_input, photo.description || "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close-photo-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_photo_modal, false)
     |> assign(:editing_photo, nil)
     |> assign(:photo_description_input, "")}
  end

  def handle_event("update-photo-description-input", %{"description" => description}, socket) do
    {:noreply, assign(socket, :photo_description_input, description)}
  end

  def handle_event("save-photo-description", _params, socket) do
    user_id = socket.assigns.user_id
    photo = socket.assigns.editing_photo
    description = String.trim(socket.assigns.photo_description_input)
    description = if description == "", do: nil, else: description
    
    if user_id && photo do
      case Friends.update_photo_description(photo.id, description, user_id) do
        {:ok, _updated} ->
          items = Friends.list_user_items(user_id)
          {:noreply,
           socket
           |> assign(:items, items)
           |> assign(:show_photo_modal, false)
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

  # Text Card Events
  def handle_event("open-text-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_text_modal, true)
     |> assign(:editing_card, nil)
     |> assign(:text_input, "")}
  end

  def handle_event("close-text-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_text_modal, false)
     |> assign(:editing_card, nil)
     |> assign(:text_input, "")}
  end

  def handle_event("edit-text-card", %{"id" => id}, socket) do
    card = Enum.find(socket.assigns.items, &(&1.type == :text_card && &1.id == String.to_integer(id)))
    
    if card do
      {:noreply,
       socket
       |> assign(:show_text_modal, true)
       |> assign(:editing_card, card)
       |> assign(:text_input, card.content)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update-text-form", %{"content" => content}, socket) do
    {:noreply, assign(socket, :text_input, content)}
  end

  def handle_event("save-text-card", %{"content" => content}, socket) do
    user_id = socket.assigns.user_id
    text = String.trim(content)
    
    if user_id && text != "" do
      attrs = %{
        user_id: user_id,
        user_color: socket.assigns.user_color,
        content: text
      }
      
      result = if socket.assigns.editing_card do
        Friends.update_text_card(socket.assigns.editing_card.id, attrs, user_id)
      else
        Friends.create_text_card(attrs)
      end
      
      case result do
        {:ok, _card} ->
          items = Friends.list_user_items(user_id)
          {:noreply,
           socket
           |> assign(:items, items)
           |> assign(:item_count, length(items))
           |> assign(:show_text_modal, false)
           |> assign(:editing_card, nil)
           |> assign(:text_input, "")
           |> put_flash(:info, if(socket.assigns.editing_card, do: "Note updated!", else: "Note added!"))}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save note")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-text-card", %{"id" => id}, socket) do
    user_id = socket.assigns.user_id
    
    if user_id do
      case Friends.delete_text_card(String.to_integer(id), user_id) do
        {:ok, _} ->
          items = Friends.list_user_items(user_id)
          {:noreply,
           socket
           |> assign(:items, items)
           |> assign(:item_count, length(items))
           |> assign(:show_text_modal, false)
           |> put_flash(:info, "Card deleted")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete")}
      end
    else
      {:noreply, socket}
    end
  end

  defp generate_user_color(user_id) do
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  defp format_time(nil), do: ""
  defp format_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      diff < 604_800 -> "#{div(diff, 86400)}d"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
