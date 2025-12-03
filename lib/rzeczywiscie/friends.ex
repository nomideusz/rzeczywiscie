defmodule Rzeczywiscie.Friends do
  @moduledoc """
  The Friends context - manages photo sharing with real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Friends.Photo

  @topic "friends:photos"
  @max_photos 100

  @doc """
  Subscribe to photo updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast photo events to all subscribed clients.
  """
  def broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {event, payload})
  end

  @doc """
  Broadcast photo events with session_id to filter out sender.
  """
  def broadcast(event, payload, session_id) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {event, payload, session_id})
  end

  @doc """
  List all photos, most recent first.
  Limited to the most recent photos for performance.
  """
  def list_photos(limit \\ @max_photos) do
    Photo
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
  Create a new photo and broadcast it to all connected users.
  """
  def create_photo(attrs) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, photo} ->
        photo_map = photo_to_map(photo)
        broadcast(:new_photo, photo_map)
        {:ok, photo_map}

      error ->
        error
    end
  end

  @doc """
  Delete a photo and broadcast the deletion.
  """
  def delete_photo(id) do
    case Repo.get(Photo, id) do
      nil ->
        {:error, :not_found}

      photo ->
        case Repo.delete(photo) do
          {:ok, _} ->
            broadcast(:photo_deleted, %{id: id})
            {:ok, id}

          error ->
            error
        end
    end
  end

  @doc """
  Delete all photos from a specific user.
  """
  def delete_user_photos(user_id) do
    {count, _} =
      Photo
      |> where([p], p.user_id == ^user_id)
      |> Repo.delete_all()

    broadcast(:user_photos_deleted, %{user_id: user_id})
    {:ok, count}
  end

  @doc """
  Get photo count.
  """
  def count_photos do
    Repo.aggregate(Photo, :count, :id)
  end

  @doc """
  Get photo count for a specific user.
  """
  def count_user_photos(user_id) do
    Photo
    |> where([p], p.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Cleanup old photos, keeping only the most recent ones.
  """
  def cleanup_old_photos(keep_count \\ @max_photos) do
    # Get IDs of photos to keep
    keep_ids =
      Photo
      |> order_by([p], desc: p.inserted_at)
      |> limit(^keep_count)
      |> select([p], p.id)
      |> Repo.all()

    # Delete all photos not in the keep list
    {deleted_count, _} =
      Photo
      |> where([p], p.id not in ^keep_ids)
      |> Repo.delete_all()

    {:ok, deleted_count}
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

