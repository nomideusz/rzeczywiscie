defmodule Rzeczywiscie.Services.LLMAnalyzerTest do
  use ExUnit.Case, async: true

  alias Rzeczywiscie.Services.LLMAnalyzer

  defp score_with_flags(red_flags) do
    LLMAnalyzer.calculate_signal_score(%{
      urgency: 0,
      condition: :good,
      seller_motivation: :standard,
      red_flags: red_flags,
      positive_signals: []
    })
  end

  test "red flags cost 3 points each, capped at -9" do
    assert score_with_flags([]) == 0
    assert score_with_flags(["zadłużone"]) == -3
    assert score_with_flags(~w(a b c d e)) == -9
  end
end
