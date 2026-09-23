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

  test "Jev answers the listings GPT analyzed and stores the answers verbatim" do
    analyzed = gpt_analyzed()
    not_analyzed = property(%{})
    answers = %{"balcony" => %{"type" => "noul", "noul" => 0.97}}

    Req.Test.stub(Jev, fn conn ->
      Req.Test.json(conn, %{
        "model" => "jev-1.13.0",
        "answers" => answers,
        "usage" => %{"input_tokens" => 900}
      })
    end)

    assert :ok = perform_job(LLMAnalysisWorker, %{})

    assert %{
             jev_signals: %{
               "model" => "jev-1.13.0",
               "answers" => ^answers,
               "usage" => %{"input_tokens" => 900}
             },
             jev_analyzed_at: %DateTime{}
           } = Repo.reload!(analyzed)

    assert %{jev_signals: nil, jev_analyzed_at: nil} = Repo.reload!(not_analyzed)
  end

  test "a failed call leaves the listing for the next run" do
    analyzed = gpt_analyzed()

    Req.Test.stub(Jev, fn conn -> Plug.Conn.send_resp(conn, 529, ~s({"error":"overloaded"})) end)

    assert :ok = perform_job(LLMAnalysisWorker, %{})
    assert %{jev_signals: nil, jev_analyzed_at: nil} = Repo.reload!(analyzed)
  end

  test "a Jev-only run takes jev_limit listings, newest GPT analysis first" do
    older = property(%{llm_condition: "good", llm_analyzed_at: ~U[2026-09-01 00:00:00Z]})
    newer = property(%{llm_condition: "good", llm_analyzed_at: ~U[2026-09-02 00:00:00Z]})

    Req.Test.stub(Jev, fn conn ->
      Req.Test.json(conn, %{"model" => "jev-1.13.0", "answers" => %{}})
    end)

    assert {:ok, %{args: args}} = LLMAnalysisWorker.trigger(jev_only: true, jev_limit: 1)
    assert :ok = perform_job(LLMAnalysisWorker, args)

    assert %{jev_analyzed_at: %DateTime{}} = Repo.reload!(newer)
    assert %{jev_analyzed_at: nil} = Repo.reload!(older)
  end
end
