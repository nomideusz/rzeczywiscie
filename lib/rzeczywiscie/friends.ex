defmodule Rzeczywiscie.Friends do
  @moduledoc """
  The Friends context - manages photo sharing with rooms and real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Friends.{Photo, Room, Message, DeviceLink, LinkCode}

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
    Photo
    |> where([p], p.room_id == ^room_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&photo_to_map/1)
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

  # Convert Photo struct to map for LiveView
  defp photo_to_map(photo) do
    %{
      id: photo.id,
      user_id: photo.user_id,
      user_color: photo.user_color,
      user_name: photo.user_name,
      data_url: photo.image_data,
      content_type: photo.content_type,
      file_size: photo.file_size,
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
end
