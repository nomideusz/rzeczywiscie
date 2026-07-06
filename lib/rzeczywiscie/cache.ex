defmodule Rzeczywiscie.Cache do
  @moduledoc """
  Tiny TTL cache on :persistent_term for expensive reads whose source data
  only changes when scrapers run (stats, hot deals). Pass ttl_ms: 0 to force
  a recompute (refresh buttons).
  """

  def fetch(key, ttl_ms, fun) do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {ts, val} when ttl_ms > 0 and now - ts < ttl_ms -> val
      _ -> put(key, fun.())
    end
  end

  def put(key, val) do
    :persistent_term.put({__MODULE__, key}, {System.monotonic_time(:millisecond), val})
    val
  end
end
