defmodule Rzeczywiscie.KanbanState do
  @moduledoc """
  Maintains server-side state for the Kanban board.
  Uses an Agent for simple in-memory storage.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  def get_cards do
    Agent.get(__MODULE__, & &1.cards)
  end

  def add_card(card) do
    Agent.update(__MODULE__, fn state ->
      %{state | cards: [card | state.cards]}
    end)

    get_cards()
  end

  def update_card(card_id, updates) do
    Agent.update(__MODULE__, fn state ->
      cards =
        Enum.map(state.cards, fn card ->
          if card.id == card_id do
            Map.merge(card, updates)
          else
            card
          end
        end)

      %{state | cards: cards}
    end)

    get_cards()
  end

  def delete_card(card_id) do
    Agent.update(__MODULE__, fn state ->
      cards = Enum.reject(state.cards, &(&1.id == card_id))
      %{state | cards: cards}
    end)

    get_cards()
  end

  def move_card(card_id, to_column) do
    update_card(card_id, %{column: to_column})
  end

  defp initial_state do
    %{
      cards: [
        %{
          id: "1",
          text: "Welcome to the Kanban Board! Try dragging this card to another column.",
          column: "todo",
          created_by: "System",
          created_at: System.system_time(:second)
        },
        %{
          id: "2",
          text: "You can add new cards using the '+ Add Card' button in each column.",
          column: "todo",
          created_by: "System",
          created_at: System.system_time(:second)
        },
        %{
          id: "3",
          text: "Click the pencil icon to edit a card, or the trash icon to delete it.",
          column: "in_progress",
          created_by: "System",
          created_at: System.system_time(:second)
        },
        %{
          id: "4",
          text: "Open this page in multiple browser windows to see real-time collaboration!",
          column: "done",
          created_by: "System",
          created_at: System.system_time(:second)
        }
      ]
    }
  end
end
