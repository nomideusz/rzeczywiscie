defmodule Rzeczywiscie.Workers.LLMAnalysisWorkerTest do
  use Rzeczywiscie.DataCase, async: false
  use Oban.Testing, repo: Rzeczywiscie.Repo

  alias Rzeczywiscie.RealEstate.Property
  alias Rzeczywiscie.Services.Jev
  alias Rzeczywiscie.Workers.LLMAnalysisWorker

  # No OpenAI key, so the GPT steps skip and only the Jev pass runs
  setup do
    for {key, value} <- [openai_api_key: "", typesafe_api_key: "test-key"] do
      previous = Application.get_env(:rzeczywiscie, key)
      Application.put_env(:rzeczywiscie, key, value)
      on_exit(fn -> Application.put_env(:rzeczywiscie, key, previous) end)
    end

    :ok
  end

  defp property(attrs) do
    n = System.unique_integer([:positive])

    %Property{}
    |> Property.changeset(
      Map.merge(
        %{
          source: "olx",
          external_id: "ext-#{n}",
          title: "Mieszkanie z balkonem",
          description: "Sprzedam mieszkanie 2-pokojowe z balkonem, bez prowizji.",
          url: "https://olx.pl/oferta/#{n}"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp gpt_analyzed,
    do: property(%{llm_condition: "good", llm_analyzed_at: ~U[2026-09-01 00:00:00Z]})

  test "Jev answers every listing with a description and writes the judgment columns" do
    judged =
      property(%{
        llm_condition: "good",
        llm_analyzed_at: ~U[2026-09-01 00:00:00Z],
        llm_red_flags: ["Dom prefabrykowany - produkt, nie nieruchomość", "Brak zdjęć"],
        llm_investment_score: 7
      })

    fresh = property(%{})
    no_text = property(%{description: "krótko"})

    answers = %{
      "condition" => %{"choice" => "renovated"},
      "seller_pressure" => %{"score" => 2.0},
      "product" => %{"noul" => 0.9},
      "fractional_share" => %{"noul" => 0.1}
    }

    Req.Test.stub(Jev, fn conn ->
      Req.Test.json(conn, %{
        "model" => "jev-1.13.0",
        "answers" => answers,
        "usage" => %{"input_tokens" => 900}
      })
    end)

    assert :ok = perform_job(LLMAnalysisWorker, %{})

    assert %{
             jev_signals: %{"model" => "jev-1.13.0", "answers" => ^answers, "usage" => %{"input_tokens" => 900}},
             jev_analyzed_at: %DateTime{},
             llm_condition: "renovated",
             llm_motivation: "very_motivated",
             llm_urgency: 10,
             llm_red_flags: ["Brak zdjęć", "Produkt, nie nieruchomość"],
             llm_investment_score: 2,
             # urgency 10 + renovated 3 + very motivated 5 - 2 red flags × 3
             llm_score: 12
           } = Repo.reload!(judged)

    assert %{jev_analyzed_at: %DateTime{}, llm_condition: "renovated"} = Repo.reload!(fresh)
    assert %{jev_analyzed_at: nil} = Repo.reload!(no_text)
  end

  test "a failed call leaves the listing for the next run" do
    analyzed = gpt_analyzed()

    Req.Test.stub(Jev, fn conn -> Plug.Conn.send_resp(conn, 529, ~s({"error":"overloaded"})) end)

    assert :ok = perform_job(LLMAnalysisWorker, %{})
    assert %{jev_signals: nil, jev_analyzed_at: nil} = Repo.reload!(analyzed)
  end

  test "a Jev-only run takes jev_limit listings, newest first" do
    older = property(%{}) |> Ecto.Changeset.change(inserted_at: ~U[2026-09-01 00:00:00Z]) |> Repo.update!()
    newer = property(%{}) |> Ecto.Changeset.change(inserted_at: ~U[2026-09-02 00:00:00Z]) |> Repo.update!()

    Req.Test.stub(Jev, fn conn ->
      Req.Test.json(conn, %{"model" => "jev-1.13.0", "answers" => %{}})
    end)

    assert {:ok, %{args: args}} = LLMAnalysisWorker.trigger(jev_only: true, jev_limit: 1)
    assert :ok = perform_job(LLMAnalysisWorker, args)

    assert %{jev_analyzed_at: %DateTime{}} = Repo.reload!(newer)
    assert %{jev_analyzed_at: nil} = Repo.reload!(older)
  end
end
