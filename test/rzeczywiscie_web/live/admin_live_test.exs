defmodule RzeczywiscieWeb.AdminLiveTest do
  use RzeczywiscieWeb.ConnCase

  import Phoenix.LiveViewTest

  test "admin is basic-auth protected", %{conn: conn} do
    assert get(conn, "/admin").status == 401
  end

  test "job queue panel shows executing jobs and runtime advances on tick", %{conn: conn} do
    Ecto.Adapters.SQL.query!(Rzeczywiscie.Repo, """
    INSERT INTO oban_jobs
      (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, attempted_at)
    VALUES
      ('executing', 'scraper', 'Rzeczywiscie.Workers.LLMAnalysisWorker', '{"limit": 30}',
       1, 2, now(), now(), now() - interval '42 seconds')
    """)

    {:ok, view, html} =
      conn
      |> Plug.Test.init_test_session(%{admin_authed: true})
      |> live("/admin")

    assert html =~ "LLMAnalysis"
    assert html =~ "limit=30"
    assert html =~ "42s"

    # running_for is recomputed inside the snapshot, so a tick re-renders the
    # duration even though the job row itself is unchanged
    send(view.pid, :tick_jobs)
    assert render(view) =~ ~r/4[23]s/
  end
end
