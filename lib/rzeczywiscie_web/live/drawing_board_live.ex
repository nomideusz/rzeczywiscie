defmodule RzeczywiscieWeb.DrawingBoardLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Drawings

  @topic "drawing_board"

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <.svelte
        name="DrawingBoard"
        props={%{canvasWidth: 1200, canvasHeight: 800}}
        socket={@socket}
      />
    </.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # One subscription covers both stroke tuples and cursor broadcasts —
      # subscribing twice to the same topic delivers every message twice.
      Drawings.subscribe()

      # Get or create the main drawing board
      {:ok, board} = Drawings.get_or_create_board("main")

      # Generate a unique user ID for this session
      user_id = generate_user_id()

      {:ok,
       socket
       |> assign(:board_id, board.id)
       |> assign(:user_id, user_id)
       |> assign(:cursor_color, generate_random_color())}
    else
      {:ok, socket}
    end
  end

  def handle_event("request_strokes", _params, socket) do
    # Client is ready, send existing strokes from database
    strokes = Drawings.get_strokes(socket.assigns.board_id)
    {:noreply, push_event(socket, "load_strokes", %{strokes: strokes})}
  end

  def handle_event("draw_segment", segment, socket) do
    # Live relay to everyone else; the sender already drew it locally.
    Drawings.broadcast_segment(segment)
    {:noreply, socket}
  end

  def handle_event("stroke_end", %{"points" => points} = stroke, socket)
      when is_list(points) and points != [] do
    # Persist the whole stroke as one row (segments were broadcast live).
    Drawings.add_stroke(socket.assigns.board_id, Map.take(stroke, ["color", "size", "points"]))
    {:noreply, socket}
  end

  def handle_event("stroke_end", _params, socket), do: {:noreply, socket}

  def handle_event("clear_canvas", _params, socket) do
    # Clear database and broadcast
    Drawings.clear_strokes(socket.assigns.board_id)
    {:noreply, socket}
  end

  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    # Broadcast cursor position to all other users
    RzeczywiscieWeb.Endpoint.broadcast_from(
      self(),
      @topic,
      "cursor_move",
      %{
        user_id: socket.assigns.user_id,
        x: x,
        y: y,
        color: socket.assigns.cursor_color
      }
    )

    {:noreply, socket}
  end

  # Handle incoming PubSub messages from Drawings context
  def handle_info({:draw_segment, segment}, socket) do
    {:noreply, push_event(socket, "draw_segment", segment)}
  end

  def handle_info({:clear_canvas, _}, socket) do
    {:noreply, push_event(socket, "clear_canvas", %{})}
  end

  def handle_info(%{event: "cursor_move", payload: cursor_data}, socket) do
    {:noreply, push_event(socket, "cursor_move", cursor_data)}
  end

  def handle_info(%{event: "cursor_remove", payload: payload}, socket) do
    {:noreply, push_event(socket, "cursor_remove", payload)}
  end

  def terminate(_reason, socket) do
    # Broadcast cursor removal when user disconnects
    if Map.has_key?(socket.assigns, :user_id) do
      RzeczywiscieWeb.Endpoint.broadcast_from(
        self(),
        @topic,
        "cursor_remove",
        %{user_id: socket.assigns.user_id}
      )
    end

    :ok
  end

  defp generate_user_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp generate_random_color do
    colors = [
      "#FF6B6B",
      "#4ECDC4",
      "#45B7D1",
      "#FFA07A",
      "#98D8C8",
      "#F7DC6F",
      "#BB8FCE",
      "#85C1E2",
      "#F8B500",
      "#52B788"
    ]

    Enum.random(colors)
  end
end
