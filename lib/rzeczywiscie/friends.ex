defmodule Rzeczywiscie.Friends do
  @moduledoc """
  The Friends context - manages photo sharing with rooms and real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Friends.{Photo, Room}

  @max_photos 100

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
      data_url: photo.image_data,
      content_type: photo.content_type,
      file_size: photo.file_size,
      uploaded_at: photo.inserted_at
    }
  end
end
