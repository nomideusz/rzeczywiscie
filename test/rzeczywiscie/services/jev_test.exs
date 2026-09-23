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

  describe "overlay/2" do
    @gpt %{
      urgency: 5,
      condition: :good,
      seller_motivation: :motivated,
      red_flags: ["Brak zdjęć"],
      positive_signals: [],
      investment_score: 6
    }

    test "keeps GPT's condition when Jev can't tell, and is idempotent" do
      jev = %{
        "answers" => %{
          "condition" => %{"choice" => "unknown"},
          "seller_pressure" => %{"score" => 0.2},
          "fractional_share" => %{"noul" => 0.95}
        }
      }

      once = Jev.overlay(@gpt, jev)

      assert %{
               condition: :good,
               seller_motivation: :standard,
               urgency: 6,
               red_flags: ["Brak zdjęć", "Tylko udział w nieruchomości"],
               investment_score: 6
             } = once

      assert Jev.overlay(once, jev) == once
    end

    test "leaves signals alone without Jev answers" do
      assert Jev.overlay(@gpt, nil) == @gpt
    end
  end
end
