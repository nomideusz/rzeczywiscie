defmodule Rzeczywiscie.DrawingState do
  @moduledoc """
  Maintains server-side state for the Drawing Board.
  Uses an Agent for simple in-memory storage of all drawing strokes.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{strokes: []} end, name: __MODULE__)
  end

  def get_strokes do
    Agent.get(__MODULE__, & &1.strokes)
  end

  def add_stroke(stroke) do
    Agent.update(__MODULE__, fn state ->
      %{state | strokes: [stroke | state.strokes]}
    end)

    get_strokes()
  end

  def clear_strokes do
    Agent.update(__MODULE__, fn _state ->
      %{strokes: []}
    end)

    []
  end
end
