defmodule Rzeczywiscie.Boards do
  @moduledoc """
  The Boards context - manages persistent Kanban boards with real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Boards.{KanbanBoard, KanbanCard}

  @topic "kanban_board"

  @doc """
  Subscribe to kanban board updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast cards update to all subscribed clients.
  """
  def broadcast_cards_update(cards) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {:cards_updated, cards}
    )
  end

  @doc """
  Get or create a kanban board by name.
  """
  def get_or_create_board(name) do
    case Repo.get_by(KanbanBoard, name: name) do
      nil ->
        {:ok, board} =
          %KanbanBoard{}
          |> KanbanBoard.changeset(%{name: name})
          |> Repo.insert()

        # Add initial demo cards
        initial_cards = [
          %{
            card_id: "1",
            text: "Welcome to the Kanban Board! Try dragging this card to another column.",
            column: "todo",
            created_by: "System",
            position: 0
          },
          %{
            card_id: "2",
            text: "You can add new cards using the '+ Add Card' button in each column.",
            column: "todo",
            created_by: "System",
            position: 1
          },
          %{
            card_id: "3",
            text: "Click the pencil icon to edit a card, or the trash icon to delete it.",
            column: "in_progress",
            created_by: "System",
            position: 0
          },
          %{
            card_id: "4",
            text: "Open this page in multiple browser windows to see real-time collaboration!",
            column: "done",
            created_by: "System",
            position: 0
          }
        ]

        Enum.each(initial_cards, fn card ->
          create_card(board.id, card)
        end)

        {:ok, board}

      board ->
        {:ok, board}
    end
  end

  @doc """
  Get all cards for a board as a list of maps (for compatibility with existing Svelte component).
  """
  def get_cards(board_id) do
    KanbanCard
    |> where([c], c.kanban_board_id == ^board_id)
    |> order_by([c], [asc: c.position, asc: c.inserted_at])
    |> Repo.all()
    |> Enum.map(&card_to_map/1)
  end

  @doc """
  Add a new card to the board.
  """
  def add_card(board_id, card_attrs) do
    create_card(board_id, card_attrs)
    cards = get_cards(board_id)
    broadcast_cards_update(cards)
    cards
  end

  @doc """
  Update a card's text and/or image.
  """
  def update_card(board_id, card_id, attrs) do
    card = Repo.get_by!(KanbanCard, kanban_board_id: board_id, card_id: card_id)

    card
    |> KanbanCard.changeset(attrs)
    |> Repo.update()

    cards = get_cards(board_id)
    broadcast_cards_update(cards)
    cards
  end

  @doc """
  Delete a card from the board.
  """
  def delete_card(board_id, card_id) do
    card = Repo.get_by!(KanbanCard, kanban_board_id: board_id, card_id: card_id)
    Repo.delete(card)

    cards = get_cards(board_id)
    broadcast_cards_update(cards)
    cards
  end

  @doc """
  Move a card to a different column.
  """
  def move_card(board_id, card_id, to_column) do
    card = Repo.get_by!(KanbanCard, kanban_board_id: board_id, card_id: card_id)

    card
    |> KanbanCard.changeset(%{column: to_column})
    |> Repo.update()

    cards = get_cards(board_id)
    broadcast_cards_update(cards)
    cards
  end

  # Private functions

  defp create_card(board_id, card_attrs) do
    attrs = Map.put(card_attrs, :kanban_board_id, board_id)

    %KanbanCard{}
    |> KanbanCard.changeset(attrs)
    |> Repo.insert()
  end

  defp card_to_map(card) do
    %{
      id: card.card_id,
      text: card.text,
      column: card.column,
      created_by: card.created_by,
      image_data: card.image_data,
      created_at: card.inserted_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    }
  end
end
