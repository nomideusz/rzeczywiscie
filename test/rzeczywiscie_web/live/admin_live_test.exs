defmodule RzeczywiscieWeb.AdminLiveTest do
  use RzeczywiscieWeb.ConnCase

  import Phoenix.LiveViewTest

  test "admin is basic-auth protected", %{conn: conn} do
    assert get(conn, "/admin").status == 401
  end

  describe "email alerts panel" do
    setup %{conn: conn} do
      %{conn: Plug.Test.init_test_session(conn, %{admin_authed: true})}
    end

    test "creates an alert from the form and lists it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> form("form[phx-submit='alert_create']", %{
          "name" => "Rzeszów flats",
          "voivodeship" => "podkarpackie",
          "max_price" => "450000",
          "city" => "",
          "transaction_type" => "sprzedaż",
          "property_type" => "",
          "min_area" => ""
        })
        |> render_submit()

      assert html =~ "Rzeszów flats"
      assert html =~ "voivodeship: podkarpackie"
      assert html =~ "max price: 450000"
      # blank fields must not become criteria that match nothing
      refute html =~ "city:"

      assert [alert] = Rzeczywiscie.Alerts.list_alerts()
      assert alert.name == "Rzeszów flats"
      assert alert.enabled
    end

    test "creates a Jev alert that starts N days back", %{conn: conn} do
      # first seen just now, so a 30-day backfill starts below it
      listing =
        Rzeczywiscie.Repo.insert!(%Rzeczywiscie.RealEstate.Property{
          title: "Pokój",
          url: "https://olx.pl/oferta/1",
          source: "olx",
          external_id: "1"
        })

      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> form("form[phx-submit='alert_create']", %{
          "name" => "Room, cats OK",
          "transaction_type" => "wynajem",
          "jev_yes" => ["pets_allowed", "long_term"],
          "jev_no" => ["bed_space"],
          "backfill_days" => "30"
        })
        |> render_submit()

      assert html =~ "jev yes: long_term, pets_allowed"

      assert [%{since_property_id: since, criteria: %{"jev_no" => ["bed_space"]}}] =
               Rzeczywiscie.Alerts.list_alerts()

      assert since < listing.id
    end

    test "surfaces a validation error instead of silently dropping the alert", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin")

      html =
        view
        |> form("form[phx-submit='alert_create']", %{"name" => "", "voivodeship" => ""})
        |> render_submit()

      assert html =~ "name can&#39;t be blank"
      assert Rzeczywiscie.Alerts.list_alerts() == []
    end

    test "pauses and deletes an alert", %{conn: conn} do
      # created before the mount so the row is on the page the test clicks
      {:ok, alert} = Rzeczywiscie.Alerts.create_alert(%{name: "Temporary", criteria: %{}})
      {:ok, view, html} = live(conn, "/admin")
      assert html =~ "Temporary"

      html =
        view
        |> element("button[phx-click='alert_toggle'][phx-value-id='#{alert.id}']")
        |> render_click()

      assert html =~ "paused"
      refute Rzeczywiscie.Alerts.get_alert(alert.id).enabled

      view
      |> element("button[phx-click='alert_delete'][phx-value-id='#{alert.id}']")
      |> render_click()

      assert Rzeczywiscie.Alerts.get_alert(alert.id) == nil
    end
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
