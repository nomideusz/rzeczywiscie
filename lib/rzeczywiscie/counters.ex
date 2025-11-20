defmodule Rzeczywiscie.Counters do
  @moduledoc """
  The Counters context - manages persistent counters with real-time broadcasting.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.Counters.Counter

  @topic "counters"

  @doc """
  Subscribe to counter updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast counter updates to all subscribed clients.
  """
  def broadcast({:ok, counter}, event) do
    Phoenix.PubSub.broadcast(Rzeczywiscie.PubSub, @topic, {event, counter})
    {:ok, counter}
  end

  def broadcast({:error, _reason} = error, _event), do: error

  @doc """
  Get or create a counter by name.
  """
  def get_or_create_counter(name) do
    case Repo.get_by(Counter, name: name) do
      nil ->
        %Counter{}
        |> Counter.changeset(%{name: name, value: 0})
        |> Repo.insert()

      counter ->
        {:ok, counter}
    end
  end

  @doc """
  Get a counter by ID.
  """
  def get_counter!(id), do: Repo.get!(Counter, id)

  @doc """
  Increment a counter and broadcast the update.
  """
  def increment_counter(id) do
    counter = Repo.get!(Counter, id)

    counter
    |> Counter.changeset(%{value: counter.value + 1})
    |> Repo.update()
    |> broadcast(:counter_updated)
  end

  @doc """
  Decrement a counter and broadcast the update.
  """
  def decrement_counter(id) do
    counter = Repo.get!(Counter, id)

    counter
    |> Counter.changeset(%{value: counter.value - 1})
    |> Repo.update()
    |> broadcast(:counter_updated)
  end

  @doc """
  Reset a counter to zero and broadcast the update.
  """
  def reset_counter(id) do
    counter = Repo.get!(Counter, id)

    counter
    |> Counter.changeset(%{value: 0})
    |> Repo.update()
    |> broadcast(:counter_updated)
  end

  @doc """
  List all counters.
  """
  def list_counters do
    Repo.all(Counter)
  end
end
