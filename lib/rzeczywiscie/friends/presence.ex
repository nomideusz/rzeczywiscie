defmodule Rzeczywiscie.Friends.Presence do
  @moduledoc """
  Presence tracking for Friends rooms.
  Tracks who's viewing which room in real-time.
  """
  use Phoenix.Presence,
    otp_app: :rzeczywiscie,
    pubsub_server: Rzeczywiscie.PubSub

  @doc """
  Track a user joining a room.
  """
  def track_user(socket, room_code, user_id, user_color, user_name \\ nil) do
    track(socket, room_code, user_id, %{
      user_id: user_id,
      user_color: user_color,
      user_name: user_name,
      joined_at: System.system_time(:second)
    })
  end

  @doc """
  Update a user's presence metadata (e.g., when name changes).
  """
  def update_user(socket, room_code, user_id, user_color, user_name) do
    update(socket, room_code, user_id, fn meta ->
      %{
        user_id: user_id,
        user_color: user_color,
        user_name: user_name,
        joined_at: Map.get(meta, :joined_at, System.system_time(:second)),
        location: Map.get(meta, :location),
        sharing_location: Map.get(meta, :sharing_location, false),
        location_expires_at: Map.get(meta, :location_expires_at)
      }
    end)
  end

  @doc """
  Update a user's live location.
  """
  def update_location(socket, room_code, user_id, lat, lng, expires_at) do
    update(socket, room_code, user_id, fn meta ->
      Map.merge(meta, %{
        location: %{lat: lat, lng: lng, updated_at: System.system_time(:second)},
        sharing_location: true,
        location_expires_at: expires_at
      })
    end)
  end

  @doc """
  Stop sharing location.
  """
  def stop_sharing_location(socket, room_code, user_id) do
    update(socket, room_code, user_id, fn meta ->
      Map.merge(meta, %{
        location: nil,
        sharing_location: false,
        location_expires_at: nil
      })
    end)
  end

  @doc """
  Get list of users in a room.
  """
  def list_users(room_code) do
    list(room_code)
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} ->
      %{
        user_id: meta.user_id,
        user_color: meta.user_color,
        user_name: Map.get(meta, :user_name)
      }
    end)
  end

  @doc """
  Get list of users currently sharing their location.
  """
  def list_live_locations(room_code) do
    now = System.system_time(:second)
    
    list(room_code)
    |> Enum.filter(fn {_user_id, %{metas: [meta | _]}} ->
      Map.get(meta, :sharing_location) == true &&
        Map.get(meta, :location) != nil &&
        (Map.get(meta, :location_expires_at) == nil || Map.get(meta, :location_expires_at) > now)
    end)
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} ->
      location = Map.get(meta, :location)
      %{
        user_id: meta.user_id,
        user_color: meta.user_color,
        user_name: Map.get(meta, :user_name),
        lat: location.lat,
        lng: location.lng,
        updated_at: location.updated_at
      }
    end)
  end

  @doc """
  Check if a name is already taken by another user in the room.
  """
  def name_taken?(room_code, name, current_user_id) do
    normalized_name = name && String.downcase(String.trim(name))
    
    list(room_code)
    |> Enum.any?(fn {user_id, %{metas: [meta | _]}} ->
      other_name = Map.get(meta, :user_name)
      user_id != current_user_id && 
        other_name != nil && 
        String.downcase(String.trim(other_name)) == normalized_name
    end)
  end

  @doc """
  Count users in a room.
  """
  def count_users(room_code) do
    list(room_code) |> map_size()
  end
end

