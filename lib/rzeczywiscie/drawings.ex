defmodule Rzeczywiscie.Drawings do
  @moduledoc """
  The Drawings context - manages persistent drawing boards with real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Drawings.{DrawingBoard, Stroke}

  @topic "drawing_board"

  @doc """
  Subscribe to drawing board updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast drawing updates to all subscribed clients.
  """
  def broadcast(message, event) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {event, message})
  end

  @doc """
  Get or create a drawing board by name.
  """
  def get_or_create_board(name, attrs \\ %{}) do
    case Repo.get_by(DrawingBoard, name: name) do
      nil ->
        default_attrs = %{name: name, width: 1200, height: 800}
        attrs = Map.merge(default_attrs, attrs)

        %DrawingBoard{}
        |> DrawingBoard.changeset(attrs)
        |> Repo.insert()

      board ->
        {:ok, board}
    end
  end

  @doc """
  Get all strokes for a drawing board.
  """
  def get_strokes(board_id) do
    Stroke
    |> where([s], s.drawing_board_id == ^board_id)
    |> order_by([s], asc: s.inserted_at)
    |> Repo.all()
    |> Enum.map(& &1.stroke_data)
  end

  @doc """
  Add a stroke to a drawing board and broadcast it.
  """
  def add_stroke(board_id, stroke_data) do
    %Stroke{}
    |> Stroke.changeset(%{drawing_board_id: board_id, stroke_data: stroke_data})
    |> Repo.insert()
    |> case do
      {:ok, _stroke} ->
        broadcast(stroke_data, :draw_stroke)
        {:ok, stroke_data}

      error ->
        error
    end
  end

  @doc """
  Clear all strokes from a drawing board and broadcast the clear event.
  """
  def clear_strokes(board_id) do
    Stroke
    |> where([s], s.drawing_board_id == ^board_id)
    |> Repo.delete_all()

    broadcast(%{}, :clear_canvas)
    {:ok, []}
  end

  @doc """
  Delete a drawing board and all its strokes.
  """
  def delete_board(board_id) do
    board = Repo.get!(DrawingBoard, board_id)
    Repo.delete(board)
  end
end
