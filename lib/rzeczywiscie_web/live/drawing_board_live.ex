defmodule RzeczywiscieWeb.DrawingBoardLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Drawings

  @topic "drawing_board"

  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
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
      # Subscribe to the drawing board topic
      Drawings.subscribe()

      # Get or create the main drawing board
      {:ok, board} = Drawings.get_or_create_board("main")

      # Subscribe to cursor updates
      RzeczywiscieWeb.Endpoint.subscribe(@topic)

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

  def handle_event("draw_stroke", stroke_data, socket) do
    # Save stroke to database and broadcast
    Drawings.add_stroke(socket.assigns.board_id, stroke_data)
    {:noreply, socket}
  end

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
  def handle_info({:draw_stroke, stroke_data}, socket) do
    {:noreply, push_event(socket, "draw_stroke", stroke_data)}
  end

  def handle_info({:clear_canvas, _}, socket) do
    {:noreply, push_event(socket, "clear_canvas", %{})}
  end

  # Handle cursor updates (still using Endpoint.broadcast)
  def handle_info(%{event: "draw_stroke", payload: stroke_data}, socket) do
    {:noreply, push_event(socket, "draw_stroke", stroke_data)}
  end

  def handle_info(%{event: "clear_canvas"}, socket) do
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
