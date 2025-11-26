defmodule RzeczywiscieWeb.ExampleLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts

  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <.svelte name="Example" props={%{number: @number}} socket={@socket} />
    </.app>
    """
  end

  def handle_event("set_number", %{"number" => number}, socket) do
    {:noreply, assign(socket, :number, number)}
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :number, 5)}
  end
end
