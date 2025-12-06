defmodule Rzeczywiscie.Friends do
  @moduledoc """
  The Friends context - manages photo sharing with rooms and real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Friends.{Photo, Room, Message, DeviceLink, LinkCode, TextCard, Place}

  @max_photos 100
  @max_messages 50

  # --- PubSub ---

  defp topic(room_code), do: "friends:room:#{room_code}"

  @doc """
  Subscribe to a room's updates.
  """
  def subscribe(room_code) do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, topic(room_code))
  end

  @doc """
  Unsubscribe from a room.
  """
  def unsubscribe(room_code) do
    Phoenix.PubSub.unsubscribe(Rzeczywiscie.PubSub, topic(room_code))
  end

  @doc """
  Broadcast event to a room.
  """
  def broadcast(room_code, event, payload) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, topic(room_code), {event, payload})
  end

  @doc """
  Broadcast event to a room with session_id for filtering.
  """
  def broadcast(room_code, event, payload, session_id) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, topic(room_code), {event, payload, session_id})
  end

  # --- Rooms ---

  @doc """
  Get or create the default lobby room.
  """
  def get_or_create_lobby do
    case Repo.get_by(Room, code: "lobby") do
      nil ->
        {:ok, room} = create_room(%{code: "lobby", name: "Lobby", emoji: "🏠"})
        room
      room ->
        room
    end
  end

  @doc """
  Get a room by code.
  """
  def get_room_by_code(code) do
    Repo.get_by(Room, code: code)
  end

  @doc """
  Get a room by ID.
  """
  def get_room(id), do: Repo.get(Room, id)

  @doc """
  Create a new room.
  """
  def create_room(attrs) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List recent rooms (for discovery).
  """
  def list_recent_rooms(limit \\ 10) do
    Room
    |> order_by([r], desc: r.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Generate a unique room code.
  """
  def generate_room_code do
    code = Room.generate_code()
    # Check if it exists, regenerate if so
    if get_room_by_code(code) do
      generate_room_code()
    else
      code
    end
  end

  # --- Photos ---

  @doc """
  List photos in a room.
  """
  def list_photos(room_id, limit \\ @max_photos) do
    # IMPORTANT: Do NOT load image_data - it's huge (megabytes per photo)
    # Only load thumbnail_data which is small
    Photo
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      inserted_at: p.inserted_at
    })
    |> Repo.all()
    |> Enum.map(&photo_to_map_light/1)
  end

  defp photo_to_map_light(photo) do
    %{
      id: photo.id,
      user_id: photo.user_id,
      user_color: photo.user_color,
      user_name: photo.user_name,
      # Only thumbnail - no fallback to image_data (we didn't load it)
      thumbnail_url: photo.thumbnail_data,
      data_url: nil,
      content_type: photo.content_type,
      file_size: photo.file_size,
      description: photo.description,
      uploaded_at: photo.inserted_at
    }
  end

  @doc """
  Get a single photo by ID.
  """
  def get_photo(id), do: Repo.get(Photo, id)

  @doc """
  Create a new photo in a room and broadcast it.
  """
  def create_photo(attrs, room_code) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, photo} ->
        photo_map = photo_to_map(photo)
        broadcast(room_code, :new_photo, photo_map)
        {:ok, photo_map}

      error ->
        error
    end
  end

  @doc """
  Create a personal photo (no room association, for My Board).
  """
  def create_personal_photo(attrs) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, photo} -> {:ok, photo_to_map_with_room(photo)}
      error -> error
    end
  end

  @doc """
  Delete a photo and broadcast the deletion.
  """
  def delete_photo(id, room_code) do
    case Repo.get(Photo, id) do
      nil ->
        {:error, :not_found}

      photo ->
        case Repo.delete(photo) do
          {:ok, _} ->
            broadcast(room_code, :photo_deleted, %{id: id})
            {:ok, id}

          error ->
            error
        end
    end
  end

  @doc """
  Count photos in a room.
  """
  def count_photos(room_id) do
    Photo
    |> where([p], p.room_id == ^room_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  List all photos by a user across all rooms, ordered by position then date.
  """
  def list_user_photos(user_id) do
    # IMPORTANT: Do NOT load image_data - it's huge (megabytes per photo)
    # We need room info, so we'll do a join instead of preload
    from(p in Photo,
      where: p.user_id == ^user_id,
      left_join: r in assoc(p, :room),
      order_by: [asc_nulls_last: p.position, desc: p.inserted_at],
      select: %{
        id: p.id,
        user_id: p.user_id,
        user_color: p.user_color,
        user_name: p.user_name,
        thumbnail_data: p.thumbnail_data,
        content_type: p.content_type,
        file_size: p.file_size,
        position: p.position,
        description: p.description,
        inserted_at: p.inserted_at,
        room_code: r.code,
        room_name: r.name,
        room_emoji: r.emoji
      }
    )
    |> Repo.all()
    |> Enum.map(&photo_to_map_with_room_light/1)
  end

  defp photo_to_map_with_room_light(photo) do
    %{
      id: photo.id,
      user_id: photo.user_id,
      user_color: photo.user_color,
      user_name: photo.user_name,
      data_url: nil,
      thumbnail_url: photo.thumbnail_data,
      content_type: photo.content_type,
      file_size: photo.file_size,
      position: photo.position,
      description: photo.description,
      uploaded_at: photo.inserted_at,
      room_code: photo.room_code,
      room_name: photo.room_name || photo.room_code,
      room_emoji: photo.room_emoji
    }
  end

  @doc """
  Count photos by a user.
  """
  def count_user_photos(user_id) do
    Photo
    |> where([p], p.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Update the position/order of a user's photos.
  Accepts a list of photo IDs in the desired order.
  """
  def reorder_user_photos(user_id, photo_ids) when is_list(photo_ids) do
    Repo.transaction(fn ->
      photo_ids
      |> Enum.with_index()
      |> Enum.each(fn {photo_id, index} ->
        Photo
        |> where([p], p.id == ^photo_id and p.user_id == ^user_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  @doc """
  Update a photo's description.
  """
  def update_photo_description(photo_id, description, user_id, opts \\ []) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        if photo.user_id == user_id do
          photo
          |> Photo.changeset(%{description: description})
          |> Repo.update()
          |> case do
            {:ok, updated} -> 
              if Keyword.get(opts, :with_room, true) do
                {:ok, photo_to_map_with_room(updated)}
              else
                {:ok, photo_to_map(updated)}
              end
            error -> error
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Set the thumbnail for a photo. Only the photo owner can set it.
  """
  def set_photo_thumbnail(photo_id, thumbnail_data, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        if photo.user_id == user_id do
          photo
          |> Photo.changeset(%{thumbnail_data: thumbnail_data})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Delete a photo. Only the photo owner can delete it.
  """
  def delete_photo(photo_id, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        if photo.user_id == user_id do
          Repo.delete(photo)
        else
          {:error, :unauthorized}
        end
    end
  end

  # Convert Photo struct to map for LiveView (with room info)
  defp photo_to_map_with_room(photo) do
    room = Repo.get(Room, photo.room_id)
    %{
      id: photo.id,
      user_id: photo.user_id,
      user_color: photo.user_color,
      user_name: photo.user_name,
      data_url: photo.image_data,
      thumbnail_url: photo.thumbnail_data || photo.image_data,
      content_type: photo.content_type,
      file_size: photo.file_size,
      position: photo.position,
      description: photo.description,
      uploaded_at: photo.inserted_at,
      room_code: room && room.code,
      room_name: room && (room.name || room.code),
      room_emoji: room && room.emoji
    }
  end

  # Convert Photo struct to map for LiveView (full data for lightbox/updates)
  defp photo_to_map(photo) do
    %{
      id: photo.id,
      user_id: photo.user_id,
      user_color: photo.user_color,
      user_name: photo.user_name,
      data_url: photo.image_data,
      thumbnail_url: photo.thumbnail_data || photo.image_data,
      content_type: photo.content_type,
      file_size: photo.file_size,
      description: photo.description,
      uploaded_at: photo.inserted_at
    }
  end

  # --- Messages ---

  @doc """
  List messages in a room.
  """
  def list_messages(room_id, limit \\ @max_messages) do
    Message
    |> where([m], m.room_id == ^room_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&message_to_map/1)
  end

  @doc """
  Create a new message in a room and broadcast it.
  """
  def create_message(attrs, room_code) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message_map = message_to_map(message)
        broadcast(room_code, :new_message, message_map)
        {:ok, message_map}

      error ->
        error
    end
  end

  @doc """
  Get a single message by ID.
  """
  def get_message(id), do: Repo.get(Message, id)

  @doc """
  Delete a message and broadcast the deletion.
  """
  def delete_message(id, room_code) do
    case Repo.get(Message, id) do
      nil ->
        {:error, :not_found}

      message ->
        case Repo.delete(message) do
          {:ok, _} ->
            broadcast(room_code, :message_deleted, %{id: id})
            {:ok, id}

          error ->
            error
        end
    end
  end

  # Convert Message struct to map for LiveView
  defp message_to_map(message) do
    %{
      id: message.id,
      user_id: message.user_id,
      user_color: message.user_color,
      user_name: message.user_name,
      content: message.content,
      sent_at: message.inserted_at
    }
  end

  # --- Device Linking ---

  @doc """
  Get the master user_id for a device fingerprint.
  Returns the linked master_user_id if one exists, otherwise nil.
  """
  def get_linked_user_id(device_fingerprint) do
    case Repo.get_by(DeviceLink, device_fingerprint: device_fingerprint) do
      nil -> nil
      link -> link.master_user_id
    end
  end

  @doc """
  Generate a link code for a user.
  Deletes any existing codes for this user first.
  """
  def generate_link_code(user_id) do
    # Delete existing codes for this user
    LinkCode
    |> where([c], c.user_id == ^user_id)
    |> Repo.delete_all()

    # Generate new code
    code = LinkCode.generate_code()
    expires_at = LinkCode.expiration_time()

    %LinkCode{}
    |> LinkCode.changeset(%{code: code, user_id: user_id, expires_at: expires_at})
    |> Repo.insert()
    |> case do
      {:ok, link_code} -> {:ok, link_code.code}
      error -> error
    end
  end

  @doc """
  Validate a link code and create a device link.
  Returns {:ok, master_user_id} on success, {:error, reason} on failure.
  """
  def link_device(code, device_fingerprint) do
    code = String.upcase(String.trim(code))
    now = DateTime.utc_now()

    case Repo.get_by(LinkCode, code: code) do
      nil ->
        {:error, :invalid_code}

      link_code ->
        if DateTime.compare(link_code.expires_at, now) == :lt do
          # Code expired, delete it
          Repo.delete(link_code)
          {:error, :expired_code}
        else
          master_user_id = link_code.user_id

          # Check if this device is already linked to a different user
          case Repo.get_by(DeviceLink, device_fingerprint: device_fingerprint) do
            nil ->
              # Create new link
              create_device_link(device_fingerprint, master_user_id, link_code)

            existing_link ->
              if existing_link.master_user_id == master_user_id do
                # Already linked to the same user
                Repo.delete(link_code)
                {:ok, master_user_id}
              else
                # Update existing link to new master
                existing_link
                |> DeviceLink.changeset(%{master_user_id: master_user_id})
                |> Repo.update()
                |> case do
                  {:ok, _} ->
                    Repo.delete(link_code)
                    {:ok, master_user_id}
                  error ->
                    error
                end
              end
          end
        end
    end
  end

  defp create_device_link(device_fingerprint, master_user_id, link_code) do
    %DeviceLink{}
    |> DeviceLink.changeset(%{device_fingerprint: device_fingerprint, master_user_id: master_user_id})
    |> Repo.insert()
    |> case do
      {:ok, _} ->
        Repo.delete(link_code)
        {:ok, master_user_id}
      error ->
        error
    end
  end

  # --- Username Management ---

  @doc """
  Get the stored username for a device fingerprint.
  Returns nil if no username is stored.
  """
  def get_username(device_fingerprint) when is_binary(device_fingerprint) do
    case Repo.get_by(DeviceLink, device_fingerprint: device_fingerprint) do
      nil -> nil
      link -> link.user_name
    end
  end
  def get_username(_), do: nil

  @doc """
  Save/update username for a device fingerprint.
  Creates a DeviceLink record if one doesn't exist.
  Returns {:ok, username} on success.
  """
  def save_username(device_fingerprint, user_name) when is_binary(device_fingerprint) do
    require Logger
    user_name = if user_name, do: String.trim(user_name), else: nil
    user_name = if user_name == "", do: nil, else: user_name

    Logger.info("save_username: fingerprint=#{device_fingerprint}, name=#{inspect(user_name)}")

    case Repo.get_by(DeviceLink, device_fingerprint: device_fingerprint) do
      nil ->
        # Create new device link with username
        # Set master_user_id to fingerprint (device is its own master until linked)
        result = %DeviceLink{}
        |> DeviceLink.changeset(%{
          device_fingerprint: device_fingerprint,
          master_user_id: device_fingerprint,
          user_name: user_name
        })
        |> Repo.insert()
        
        case result do
          {:ok, _} -> 
            Logger.info("save_username: created new DeviceLink")
            {:ok, user_name}
          {:error, changeset} -> 
            Logger.error("save_username: insert failed: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      existing ->
        # Update existing device link
        result = existing
        |> DeviceLink.name_changeset(%{user_name: user_name})
        |> Repo.update()
        
        case result do
          {:ok, _} -> 
            Logger.info("save_username: updated existing DeviceLink")
            # Update all historical content with new username (retroactive)
            user_id = existing.master_user_id || device_fingerprint
            update_all_content_username(user_id, user_name)
            {:ok, user_name}
          {:error, changeset} -> 
            Logger.error("save_username: update failed: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end
  def save_username(_, _), do: {:error, :invalid_fingerprint}

  @doc """
  Update username on all historical content (messages, photos, text cards).
  Called when a user changes their display name.
  """
  def update_all_content_username(user_id, new_name) do
    require Logger
    Logger.info("Updating all content for user_id=#{user_id} to name=#{inspect(new_name)}")
    
    # Update messages
    {msg_count, _} = from(m in Message, where: m.user_id == ^user_id)
    |> Repo.update_all(set: [user_name: new_name])
    
    # Update photos
    {photo_count, _} = from(p in Photo, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_name: new_name])
    
    # Update text cards
    {card_count, _} = from(t in TextCard, where: t.user_id == ^user_id)
    |> Repo.update_all(set: [user_name: new_name])
    
    # Update places
    {place_count, _} = from(p in Place, where: p.user_id == ^user_id)
    |> Repo.update_all(set: [user_name: new_name])
    
    Logger.info("Updated #{msg_count} messages, #{photo_count} photos, #{card_count} text cards, #{place_count} places")
    
    :ok
  end

  @doc """
  Check if a username is taken by another device (globally reserved).
  Returns true if the name is taken by a different device.
  """
  def username_taken?(name, current_device_fingerprint) when is_binary(name) do
    normalized = String.downcase(String.trim(name))
    
    query = from(d in DeviceLink,
      where: d.device_fingerprint != ^current_device_fingerprint,
      where: not is_nil(d.user_name),
      where: fragment("lower(trim(?)) = ?", d.user_name, ^normalized),
      select: count(d.id)
    )
    
    Repo.one(query) > 0
  end
  def username_taken?(nil, _), do: false
  def username_taken?("", _), do: false

  @doc """
  Get device info (user_id and username) for a device fingerprint.
  Returns {user_id, username} where user_id may be master_user_id if linked.
  """
  def get_device_info(device_fingerprint) when is_binary(device_fingerprint) do
    result = Repo.get_by(DeviceLink, device_fingerprint: device_fingerprint)
    
    case result do
      nil -> 
        # No device link found - this is a new device
        require Logger
        Logger.debug("DeviceLink not found for fingerprint: #{device_fingerprint}")
        {device_fingerprint, nil}
      link -> 
        user_id = link.master_user_id || device_fingerprint
        require Logger
        Logger.debug("DeviceLink found: fingerprint=#{device_fingerprint}, user_name=#{inspect(link.user_name)}")
        {user_id, link.user_name}
    end
  end
  def get_device_info(_), do: {nil, nil}

  @doc """
  Unlink a device (remove the device link).
  """
  def unlink_device(device_fingerprint) do
    DeviceLink
    |> where([d], d.device_fingerprint == ^device_fingerprint)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Get all devices linked to a user.
  """
  def get_linked_devices(master_user_id) do
    DeviceLink
    |> where([d], d.master_user_id == ^master_user_id)
    |> Repo.all()
  end

  @doc """
  Clean up expired link codes.
  """
  def cleanup_expired_codes do
    now = DateTime.utc_now()

    LinkCode
    |> where([c], c.expires_at < ^now)
    |> Repo.delete_all()
  end

  # --- Text Cards ---

  @doc """
  List all text cards by a user, ordered by position.
  """
  def list_user_text_cards(user_id) do
    TextCard
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], [asc_nulls_last: t.position, desc: t.inserted_at])
    |> Repo.all()
    |> Enum.map(&text_card_to_map_with_room/1)
  end

  @doc """
  List all text cards for a room.
  """
  def list_room_text_cards(room_id) do
    TextCard
    |> where([t], t.room_id == ^room_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
    |> Enum.map(&text_card_to_map/1)
  end

  @doc """
  Get a text card by ID.
  """
  def get_text_card(id), do: Repo.get(TextCard, id)

  @doc """
  Create a new text card.
  """
  def create_text_card(attrs, room_code \\ nil) do
    %TextCard{}
    |> TextCard.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, card} -> 
        # Broadcast to room if it's a room note
        if room_code do
          broadcast(room_code, :new_note, text_card_to_map(card))
        end
        {:ok, text_card_to_map(card)}
      error -> error
    end
  end

  @doc """
  Update a text card.
  """
  def update_text_card(id, attrs, user_id) do
    case Repo.get(TextCard, id) do
      nil ->
        {:error, :not_found}

      card ->
        if card.user_id == user_id do
          card
          |> TextCard.changeset(attrs)
          |> Repo.update()
          |> case do
            {:ok, updated} -> {:ok, text_card_to_map(updated)}
            error -> error
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Delete a text card.
  """
  def delete_text_card(id, user_id) do
    case Repo.get(TextCard, id) do
      nil ->
        {:error, :not_found}

      card ->
        if card.user_id == user_id do
          Repo.delete(card)
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Update the position/order of a user's text cards.
  """
  def reorder_user_text_cards(user_id, card_ids) when is_list(card_ids) do
    Repo.transaction(fn ->
      card_ids
      |> Enum.with_index()
      |> Enum.each(fn {card_id, index} ->
        TextCard
        |> where([t], t.id == ^card_id and t.user_id == ^user_id)
        |> Repo.update_all(set: [position: index])
      end)
    end)
  end

  @doc """
  List all user items (photos and text cards) combined and sorted.
  """
  def list_user_items(user_id) do
    photos = list_user_photos(user_id) |> Enum.map(&Map.put(&1, :type, :photo))
    text_cards = list_user_text_cards(user_id) |> Enum.map(&Map.put(&1, :type, :text_card))

    (photos ++ text_cards)
    |> Enum.sort_by(fn item ->
      # Sort by position (nulls last), then by date descending
      # Photos have :uploaded_at, text_cards have :created_at
      timestamp = Map.get(item, :uploaded_at) || Map.get(item, :created_at)
      unix_time = case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp)
        %NaiveDateTime{} -> NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
      {item.position || 999_999, -unix_time}
    end)
  end

  @doc """
  Reorder all user items (both photos and text cards).
  """
  def reorder_user_items(user_id, item_ids) when is_list(item_ids) do
    Repo.transaction(fn ->
      item_ids
      |> Enum.with_index()
      |> Enum.each(fn {item_id, index} ->
        # Item ID format: "photo-123" or "text-456"
        case String.split(item_id, "-", parts: 2) do
          ["photo", id] ->
            Photo
            |> where([p], p.id == ^String.to_integer(id) and p.user_id == ^user_id)
            |> Repo.update_all(set: [position: index])

          ["text", id] ->
            TextCard
            |> where([t], t.id == ^String.to_integer(id) and t.user_id == ^user_id)
            |> Repo.update_all(set: [position: index])

          _ ->
            :ok
        end
      end)
    end)
  end

  defp text_card_to_map(card) do
    %{
      id: card.id,
      user_id: card.user_id,
      user_color: card.user_color,
      user_name: card.user_name,
      content: card.content,
      position: card.position,
      created_at: card.inserted_at
    }
  end

  defp text_card_to_map_with_room(card) do
    room = if card.room_id, do: Repo.get(Room, card.room_id), else: nil
    %{
      id: card.id,
      user_id: card.user_id,
      user_color: card.user_color,
      user_name: card.user_name,
      content: card.content,
      position: card.position,
      created_at: card.inserted_at,
      room_code: room && room.code,
      room_name: room && (room.name || room.code),
      room_emoji: room && room.emoji
    }
  end

  # ============================================================================
  # Places (Map Pins)
  # ============================================================================

  @doc """
  List all places in a room.
  """
  def list_places(room_id) do
    Place
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
    |> Enum.map(&place_to_map/1)
  end

  @doc """
  Create a new place pin.
  """
  def create_place(attrs, room_code \\ nil) do
    room_id = if room_code do
      case get_or_create_room(room_code) do
        {:ok, room} -> room.id
        _ -> nil
      end
    else
      nil
    end

    result = %Place{}
    |> Place.changeset(Map.put(attrs, :room_id, room_id))
    |> Repo.insert()

    case result do
      {:ok, place} ->
        place_map = place_to_map(place)
        if room_code do
          broadcast(room_code, :new_place, place_map)
        end
        {:ok, place_map}
      error ->
        error
    end
  end

  @doc """
  Delete a place pin.
  """
  def delete_place(place_id, user_id, room_code \\ nil) do
    case Repo.get(Place, place_id) do
      nil ->
        {:error, :not_found}
      place ->
        if place.user_id == user_id do
          case Repo.delete(place) do
            {:ok, _} ->
              if room_code do
                broadcast(room_code, :place_deleted, %{id: place_id})
              end
              {:ok, place_id}
            error ->
              error
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Get a single place by ID.
  """
  def get_place(place_id) do
    case Repo.get(Place, place_id) do
      nil -> nil
      place -> place_to_map(place)
    end
  end

  defp place_to_map(place) do
    %{
      id: place.id,
      user_id: place.user_id,
      user_name: place.user_name,
      user_color: place.user_color,
      name: place.name,
      description: place.description,
      lat: place.lat,
      lng: place.lng,
      emoji: place.emoji || "📍",
      room_id: place.room_id,
      created_at: place.inserted_at
    }
  end

  # ============================================================================
  # Admin Functions
  # ============================================================================

  def admin_list_photos(offset, limit, filter \\ "all") do
    query = from(p in Photo,
      order_by: [desc: p.inserted_at],
      offset: ^offset,
      limit: ^limit,
      select: %{
        id: p.id,
        user_id: p.user_id,
        user_name: p.user_name,
        file_size: p.file_size,
        inserted_at: p.inserted_at,
        has_thumbnail: not is_nil(p.thumbnail_data)
      }
    )

    query = case filter do
      "no_thumbnail" -> where(query, [p], is_nil(p.thumbnail_data))
      _ -> query
    end

    Repo.all(query)
  end

  def admin_get_photo_stats do
    total = Repo.aggregate(Photo, :count, :id) || 0
    with_thumbnails = Repo.one(from p in Photo, where: not is_nil(p.thumbnail_data), select: count(p.id)) || 0
    without_thumbnails = total - with_thumbnails
    total_size = Repo.one(from p in Photo, select: sum(p.file_size)) || 0

    %{
      total_photos: total,
      with_thumbnails: with_thumbnails,
      without_thumbnails: without_thumbnails,
      total_size: total_size
    }
  end

  def admin_delete_photo(photo_id) do
    case Repo.get(Photo, photo_id) do
      nil -> {:error, :not_found}
      photo -> Repo.delete(photo)
    end
  end

  def admin_delete_photos_without_thumbnails do
    {count, _} = Repo.delete_all(from p in Photo, where: is_nil(p.thumbnail_data))
    count
  end
end
