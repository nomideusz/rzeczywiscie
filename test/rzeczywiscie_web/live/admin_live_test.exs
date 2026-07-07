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

  test "progress reported by a worker and finished jobs appear in the panel", %{conn: conn} do
    %{rows: [[id]]} =
      Ecto.Adapters.SQL.query!(Rzeczywiscie.Repo, """
      INSERT INTO oban_jobs
        (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, attempted_at)
      VALUES
        ('executing', 'scraper', 'Rzeczywiscie.Workers.OlxScraperWorker', '{"pages": 3}',
         1, 3, now(), now(), now())
      RETURNING id
      """)

    Rzeczywiscie.JobProgress.report(%Oban.Job{id: id}, "page 2/3 — 40 found")

    Ecto.Adapters.SQL.query!(Rzeczywiscie.Repo, """
    INSERT INTO oban_jobs
      (state, queue, worker, args, meta, attempt, max_attempts, inserted_at, scheduled_at, attempted_at, completed_at)
    VALUES
      ('completed', 'default', 'Rzeczywiscie.Workers.GeocodingWorker', '{}',
       '{"progress": "done - 48/50 geocoded (30 from cache)"}',
       1, 3, now(), now(), now() - interval '3 minutes', now() - interval '1 minute')
    """)

    {:ok, _view, html} =
      conn
      |> Plug.Test.init_test_session(%{admin_authed: true})
      |> live("/admin")

    assert html =~ "page 2/3 — 40 found"
    assert html =~ "Recently finished"
    assert html =~ "done - 48/50 geocoded (30 from cache)"
    assert html =~ "took 2m 0s"
  end

  test "failing jobs show why: retryable list and discard reasons", %{conn: conn} do
    Ecto.Adapters.SQL.query!(Rzeczywiscie.Repo, """
    INSERT INTO oban_jobs
      (state, queue, worker, args, errors, attempt, max_attempts, inserted_at, scheduled_at, attempted_at)
    VALUES
      ('retryable', 'scraper', 'Rzeczywiscie.Workers.OtodomScraperWorker', '{"pages": 5}',
       ARRAY['{"attempt": 1, "at": "2026-07-07T00:00:00Z", "error": "** (HTTPoison.Error) :timeout\\nstacktrace line"}'::jsonb],
       1, 3, now(), now() + interval '90 seconds', now() - interval '1 minute'),
      ('discarded', 'default', 'Rzeczywiscie.Workers.GeocodingWorker', '{}',
       ARRAY['{"attempt": 3, "at": "2026-07-07T00:00:00Z", "error": "** (RuntimeError) API quota exceeded\\nstacktrace"}'::jsonb],
       3, 3, now(), now(), now() - interval '5 minutes')
    """)

    {:ok, _view, html} =
      conn
      |> Plug.Test.init_test_session(%{admin_authed: true})
      |> live("/admin")

    # retryable: shown with attempt count, next retry, and the exception line
    assert html =~ "Failing — waiting to retry"
    assert html =~ "attempt 1/3"
    assert html =~ ":timeout"
    refute html =~ "stacktrace line"

    # discarded: shows up in recently finished with its final error
    assert html =~ "API quota exceeded"
  end
end
