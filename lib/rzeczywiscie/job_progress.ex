defmodule Rzeczywiscie.JobProgress do
  @moduledoc """
  Writes a one-line progress message into the running job's `oban_jobs.meta`
  ("page 2/5 — 40 found", "geocoded 23/50"). The admin Job Queue panel polls
  the table every 5s and shows it live; the final message survives completion
  and is shown in the "recently finished" list.
  """

  import Ecto.Query
  alias Rzeczywiscie.Repo

  def report(%Oban.Job{id: id}, message) when is_integer(id) and is_binary(message) do
    from(j in "oban_jobs",
      where: j.id == ^id,
      update: [set: [meta: fragment("meta || ?", type(^%{progress: message}, :map))]]
    )
    |> Repo.update_all([])

    :ok
  end

  # workers called inline (tests, iex) have no persisted job — just skip
  def report(_job, _message), do: :ok
end
