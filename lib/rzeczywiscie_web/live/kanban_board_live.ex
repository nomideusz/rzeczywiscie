defmodule RzeczywiscieWeb.KanbanBoardLive do
  use RzeczywiscieWeb, :live_view
  alias Phoenix.PubSub

  @topic "kanban_board"
  @presence_topic "kanban_presence"

  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <.svelte
        name="KanbanBoard"
        props={%{
          columns: @columns,
          cards: @cards,
          users: @users
        }}
        socket={@socket}
      />
    </.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to board updates
      RzeczywiscieWeb.Endpoint.subscribe(@topic)

      # Track user presence
      {:ok, _} = RzeczywiscieWeb.Presence.track(
        self(),
        @presence_topic,
        socket.id,
        %{
          name: generate_username(),
          color: generate_user_color(),
          joined_at: System.system_time(:second)
        }
      )

      # Subscribe to presence updates
      RzeczywiscieWeb.Endpoint.subscribe(@presence_topic)

      {:ok,
       socket
       |> assign(:columns, initial_columns())
       |> assign(:cards, Rzeczywiscie.KanbanState.get_cards())
       |> assign(:users, get_present_users())
       |> assign(:username, generate_username())}
    else
      {:ok,
       socket
       |> assign(:columns, initial_columns())
       |> assign(:cards, [])
       |> assign(:users, [])
       |> assign(:username, "Guest")}
    end
  end

  def handle_event("add_card", %{"text" => text, "column" => column}, socket) do
    new_card = %{
      id: generate_id(),
      text: text,
      column: column,
      created_by: socket.assigns.username,
      created_at: System.system_time(:second)
    }

    # Update server-side state
    cards = Rzeczywiscie.KanbanState.add_card(new_card)

    # Broadcast to all clients
    broadcast_cards_update(cards)

    {:noreply, assign(socket, :cards, cards)}
  end

  def handle_event("update_card", %{"card_id" => card_id, "text" => text}, socket) do
    # Update server-side state
    cards = Rzeczywiscie.KanbanState.update_card(card_id, %{text: text})

    broadcast_cards_update(cards)

    {:noreply, assign(socket, :cards, cards)}
  end

  def handle_event("delete_card", %{"card_id" => card_id}, socket) do
    # Update server-side state
    cards = Rzeczywiscie.KanbanState.delete_card(card_id)

    broadcast_cards_update(cards)

    {:noreply, assign(socket, :cards, cards)}
  end

  def handle_event("move_card", %{"card_id" => card_id, "to_column" => to_column}, socket) do
    # Update server-side state
    cards = Rzeczywiscie.KanbanState.move_card(card_id, to_column)

    broadcast_cards_update(cards)

    {:noreply, assign(socket, :cards, cards)}
  end

  # Handle incoming PubSub messages
  def handle_info(%{event: "cards_updated", payload: payload}, socket) do
    {:noreply,
     socket
     |> assign(:cards, payload.cards)
     |> push_event("cards_updated", %{cards: payload.cards})}
  end

  def handle_info(
        %{event: "presence_diff", payload: _payload},
        socket
      ) do
    users = get_present_users()

    {:noreply,
     socket
     |> assign(:users, users)
     |> push_event("presence_update", %{users: users})}
  end

  defp broadcast_cards_update(cards) do
    PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      %{event: "cards_updated", payload: %{cards: cards}}
    )
  end

  defp get_present_users do
    RzeczywiscieWeb.Presence.list(@presence_topic)
    |> Enum.map(fn {_id, %{metas: [meta | _]}} ->
      %{
        name: meta.name,
        color: meta.color
      }
    end)
  end

  defp initial_columns do
    [
      %{id: "todo", name: "To Do"},
      %{id: "in_progress", name: "In Progress"},
      %{id: "done", name: "Done"}
    ]
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  defp generate_username do
    adjectives = [
      "Swift",
      "Bright",
      "Clever",
      "Bold",
      "Happy",
      "Lucky",
      "Mighty",
      "Noble",
      "Quick",
      "Wise"
    ]

    nouns = [
      "Panda",
      "Tiger",
      "Eagle",
      "Fox",
      "Wolf",
      "Bear",
      "Lion",
      "Hawk",
      "Owl",
      "Dragon"
    ]

    "#{Enum.random(adjectives)} #{Enum.random(nouns)}"
  end

  defp generate_user_color do
    colors = [
      "#3B82F6",
      "#8B5CF6",
      "#EC4899",
      "#F59E0B",
      "#10B981",
      "#06B6D4",
      "#6366F1",
      "#EF4444",
      "#14B8A6",
      "#F97316"
    ]

    Enum.random(colors)
  end
end
