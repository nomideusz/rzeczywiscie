defmodule RzeczywiscieWeb.DrawingBoardLive do
  use RzeczywiscieWeb, :live_view

  @topic "drawing_board"

  def render(assigns) do
    ~H"""
    <.svelte
      name="DrawingBoard"
      props={%{canvasWidth: 1200, canvasHeight: 800}}
      socket={@socket}
    />
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to the drawing board topic
      RzeczywiscieWeb.Endpoint.subscribe(@topic)

      # Generate a unique user ID for this session
      user_id = generate_user_id()

      # Get existing strokes from server state
      strokes = Rzeczywiscie.DrawingState.get_strokes()

      {:ok,
       socket
       |> assign(:user_id, user_id)
       |> assign(:cursor_color, generate_random_color())
       |> push_event("load_strokes", %{strokes: strokes})}
    else
      {:ok, socket}
    end
  end

  def handle_event("draw_stroke", stroke_data, socket) do
    # Save stroke to server-side state
    Rzeczywiscie.DrawingState.add_stroke(stroke_data)

    # Broadcast the stroke to all other users
    RzeczywiscieWeb.Endpoint.broadcast_from(
      self(),
      @topic,
      "draw_stroke",
      stroke_data
    )

    {:noreply, socket}
  end

  def handle_event("clear_canvas", _params, socket) do
    # Clear server-side state
    Rzeczywiscie.DrawingState.clear_strokes()

    # Broadcast clear canvas to all users
    RzeczywiscieWeb.Endpoint.broadcast_from(
      self(),
      @topic,
      "clear_canvas",
      %{}
    )

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

  # Handle incoming PubSub messages and push them to the client
  def handle_info(%{event: "draw_stroke", payload: stroke_data}, socket) do
    {:noreply, push_event(socket, "draw_stroke", stroke_data)}
  end

  def handle_info(%{event: "clear_canvas"}, socket) do
    {:noreply, push_event(socket, "clear_canvas", %{})}
  end

  def handle_info(%{event: "cursor_move", payload: cursor_data}, socket) do
    {:noreply, push_event(socket, "cursor_move", cursor_data)}
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

  def handle_info(%{event: "cursor_remove", payload: payload}, socket) do
    {:noreply, push_event(socket, "cursor_remove", payload)}
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
