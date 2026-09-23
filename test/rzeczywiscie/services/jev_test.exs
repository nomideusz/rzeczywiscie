defmodule Rzeczywiscie.Services.JevTest do
  use ExUnit.Case, async: true
  alias Rzeczywiscie.Services.Jev

  test "a yes/no answer counts as yes from 0.7" do
    signals = %{"answers" => %{"swap" => %{"noul" => 0.7}, "lift" => %{"noul" => 0.69}}}

    assert Jev.yes?(signals, "swap")
    refute Jev.yes?(signals, "lift")
    refute Jev.yes?(signals, "balcony")
    # not analyzed yet
    refute Jev.yes?(nil, "swap")
  end
end
