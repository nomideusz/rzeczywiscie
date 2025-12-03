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
  def track_user(socket, room_code, user_id, user_color) do
    track(socket, room_code, user_id, %{
      user_id: user_id,
      user_color: user_color,
      joined_at: System.system_time(:second)
    })
  end

  @doc """
  Get list of users in a room.
  """
  def list_users(room_code) do
    list(room_code)
    |> Enum.map(fn {_user_id, %{metas: [meta | _]}} ->
      %{
        user_id: meta.user_id,
        user_color: meta.user_color
      }
    end)
  end

  @doc """
  Count users in a room.
  """
  def count_users(room_code) do
    list(room_code) |> map_size()
  end
end

