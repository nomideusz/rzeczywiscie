defmodule RzeczywiscieWeb.PersistentCounterLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.Counters

  def mount(_params, _session, socket) do
    # Subscribe to counter updates when the LiveView connects
    if connected?(socket) do
      Counters.subscribe()
    end

    # Get or create the main counter
    {:ok, counter} = Counters.get_or_create_counter("main")

    {:ok, assign(socket, counter: counter)}
  end

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <.svelte
        name="PersistentCounter"
        props={%{
          counter_id: @counter.id,
          value: @counter.value,
          name: @counter.name
        }}
        socket={@socket}
      />
    </.app>
    """
  end

  def handle_event("increment", _params, socket) do
    Counters.increment_counter(socket.assigns.counter.id)
    {:noreply, socket}
  end

  def handle_event("decrement", _params, socket) do
    Counters.decrement_counter(socket.assigns.counter.id)
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    Counters.reset_counter(socket.assigns.counter.id)
    {:noreply, socket}
  end

  # This receives broadcasts from other clients!
  def handle_info({:counter_updated, counter}, socket) do
    {:noreply, assign(socket, counter: counter)}
  end
end
