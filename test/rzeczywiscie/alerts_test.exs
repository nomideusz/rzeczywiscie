defmodule Rzeczywiscie.AlertsTest do
  use Rzeczywiscie.DataCase, async: false

  import Swoosh.TestAssertions

  alias Rzeczywiscie.Alerts
  alias Rzeczywiscie.Alerts.AlertMatch
  alias Rzeczywiscie.RealEstate.Property

  # Alerts only report listings first seen *after* the alert was created, so
  # tests that expect a match have to insert the property afterwards. Where an
  # explicit inserted_at is needed, pass it.
  defp property(attrs \\ %{}) do
    defaults = %{
      source: "olx",
      external_id: "ext-#{System.unique_integer([:positive])}",
      title: "Mieszkanie 50m2",
      url: "https://olx.pl/oferta/#{System.unique_integer([:positive])}",
      price: Decimal.new("400000"),
      currency: "PLN",
      area_sqm: Decimal.new("50"),
      rooms: 2,
      city: "Rzeszów",
      voivodeship: "podkarpackie",
      transaction_type: "sprzedaż",
      property_type: "mieszkanie",
      active: true
    }

    %Property{}
    |> Property.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp alert(attrs \\ %{}) do
    {:ok, alert} =
      Alerts.create_alert(Map.merge(%{name: "Test alert", criteria: %{}}, attrs))

    alert
  end

  describe "criteria handling" do
    test "keeps only known filter keys" do
      alert = alert(%{criteria: %{"city" => "Rzeszów", "drop_table" => "x", "rooms" => "3"}})

      assert alert.criteria == %{"city" => "Rzeszów", "rooms" => 3}
    end

    test "drops blank values instead of filtering on them" do
      alert = alert(%{criteria: %{"city" => "", "max_price" => nil, "source" => "olx"}})

      assert alert.criteria == %{"source" => "olx"}
    end

    test "casts numbers arriving as strings from the admin form" do
      alert = alert(%{criteria: %{"max_price" => "450000", "min_area" => "40,5"}})

      assert alert.criteria == %{"max_price" => 450_000.0, "min_area" => 40.5}
    end

    test "rejects a region we do not cover" do
      assert {:error, changeset} =
               Alerts.create_alert(%{name: "Bad", criteria: %{"voivodeship" => "mazowieckie"}})

      assert "unknown region: mazowieckie" in errors_on(changeset).criteria
    end

    test "accepts a covered region by slug or stored name" do
      assert %{criteria: %{"voivodeship" => "podkarpackie"}} =
               alert(%{criteria: %{"voivodeship" => "podkarpackie"}})

      assert %{criteria: %{"voivodeship" => "malopolskie"}} =
               alert(%{criteria: %{"voivodeship" => "malopolskie"}})
    end

    test "keeps Jev questions as sorted lists and rejects unknown ones" do
      alert =
        alert(%{
          criteria: %{"jev_yes" => ["pets_allowed", "long_term", "long_term"], "jev_no" => []}
        })

      assert alert.criteria == %{"jev_yes" => ["long_term", "pets_allowed"]}

      assert {:error, changeset} =
               Alerts.create_alert(%{name: "Typo", criteria: %{"jev_no" => ["pets_alowed"]}})

      assert "unknown Jev question: pets_alowed" in errors_on(changeset).criteria
    end

    test "to_filters only emits whitelisted keys" do
      filters = Alerts.to_filters(%{"city" => "Rzeszów", "bogus" => 1, "max_price" => 100})

      assert Enum.sort(filters) == [{:city, "Rzeszów"}, {:max_price, 100}]
    end
  end

  describe "pending_matches/2" do
    test "ignores listings that predate the alert" do
      property(%{title: "Old listing"})
      alert = alert()

      assert Alerts.pending_matches(alert) == []

      property(%{title: "New listing"})

      assert [match] = Alerts.pending_matches(alert)
      assert match.title == "New listing"
    end

    test "applies the alert criteria" do
      alert = alert(%{criteria: %{"voivodeship" => "podkarpackie", "max_price" => 300_000}})

      property(%{title: "Too expensive", price: Decimal.new("900000")})
      property(%{title: "Wrong region", voivodeship: "małopolskie", price: Decimal.new("100000")})
      property(%{title: "Match", price: Decimal.new("250000")})

      assert [match] = Alerts.pending_matches(alert)
      assert match.title == "Match"
    end

    test "skips inactive listings" do
      alert = alert()
      property(%{title: "Delisted", active: false})

      assert Alerts.pending_matches(alert) == []
    end

    test "honours the limit" do
      alert = alert()
      for i <- 1..3, do: property(%{title: "Listing #{i}"})

      assert length(Alerts.pending_matches(alert, limit: 2)) == 2
      assert Alerts.count_pending_matches(alert) == 3
    end
  end

  describe "run_alert/1" do
    test "emails the matches and records them" do
      alert = alert(%{name: "Rzeszów flats"})
      property(%{title: "Nowe mieszkanie"})

      assert {:ok, {:sent, 1}} = Alerts.run_alert(alert)

      assert_email_sent(fn email ->
        assert email.subject == "Rzeszów flats: 1 new listing"
        assert email.to == [{"", "owner@example.test"}]
        assert email.from == {"Kruk.live", "alerts@example.test"}
        assert email.text_body =~ "Nowe mieszkanie"
        assert email.html_body =~ "Nowe mieszkanie"
      end)

      assert Repo.aggregate(AlertMatch, :count) == 1

      reloaded = Alerts.get_alert(alert.id)
      assert reloaded.notified_count == 1
      assert reloaded.last_notified_at
    end

    test "never reports the same listing twice" do
      alert = alert()
      property()

      assert {:ok, {:sent, 1}} = Alerts.run_alert(alert)

      reloaded = Alerts.get_alert(alert.id)
      assert {:ok, :no_matches} = Alerts.run_alert(reloaded)
      assert Repo.aggregate(AlertMatch, :count) == 1
    end

    test "sends nothing when there is nothing new" do
      alert = alert()

      assert {:ok, :no_matches} = Alerts.run_alert(alert)
      assert_no_email_sent()
      assert Alerts.get_alert(alert.id).last_run_at
    end

    test "reports how many matches are still waiting" do
      alert = alert()
      for i <- 1..3, do: property(%{title: "Listing #{i}"})

      # Deliver a single match so the rest stay queued
      [property] = Alerts.pending_matches(alert, limit: 1)
      remaining = Alerts.count_pending_matches(alert) - 1

      Rzeczywiscie.Alerts.AlertEmail.new_listings(alert, [property],
        to: "owner@example.test",
        remaining: remaining
      )
      |> Rzeczywiscie.Mailer.deliver()

      assert_email_sent(fn email ->
        assert email.text_body =~ "2 more matches waiting"
      end)
    end

    test "records nothing when delivery is not configured" do
      mail_config = Application.get_env(:rzeczywiscie, :mail)
      Application.put_env(:rzeczywiscie, :mail, from: nil, alert_to: nil)
      on_exit(fn -> Application.put_env(:rzeczywiscie, :mail, mail_config) end)

      alert = alert()
      property()

      refute Alerts.configured?()
      assert {:error, :not_configured} = Alerts.run_alert(alert)
      assert_no_email_sent()

      # The listing stays pending, so it goes out once mail is configured
      assert Repo.aggregate(AlertMatch, :count) == 0
      assert length(Alerts.pending_matches(Alerts.get_alert(alert.id))) == 1
    end
  end

  describe "Jev criteria" do
    setup do
      previous = Application.get_env(:rzeczywiscie, :typesafe_api_key)
      Application.put_env(:rzeczywiscie, :typesafe_api_key, "test-key")
      on_exit(fn -> Application.put_env(:rzeczywiscie, :typesafe_api_key, previous) end)
    end

    test "asks Jev about the candidates it has no answers for, then matches on them" do
      alert =
        alert(%{
          criteria: %{
            "transaction_type" => "wynajem",
            "jev_yes" => ["pets_allowed"],
            "jev_no" => ["bed_space"]
          }
        })

      rental = %{transaction_type: "wynajem", property_type: "pokój"}

      cats =
        property(
          Map.merge(rental, %{title: "Pokój z kotami", description: "Koty mile widziane."})
        )

      no_pets =
        property(Map.merge(rental, %{title: "Pokój bez zwierząt", description: "Bez zwierząt."}))

      # Asked before bed_space existed, so it is asked again
      stale =
        property(
          Map.merge(rental, %{
            title: "Pokój dla kociarzy",
            description: "Koty mile widziane.",
            jev_signals: %{"answers" => %{"pets_allowed" => %{"noul" => 0.9}}}
          })
        )

      # No text to judge yet: waits, and fails the "no" check meanwhile
      no_text = property(Map.put(rental, :title, "Pokój"))
      sale = property(%{title: "Mieszkanie", description: "Koty mile widziane."})

      Req.Test.stub(Rzeczywiscie.Services.Jev, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        pets = if body =~ "Koty mile widziane", do: 0.95, else: 0.05

        Req.Test.json(conn, %{
          "model" => "jev-1.13.0",
          "answers" => %{"pets_allowed" => %{"noul" => pets}, "bed_space" => %{"noul" => 0.02}}
        })
      end)

      assert {:ok, {:sent, 2}} = Alerts.run_alert(alert)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Pokój bez zwierząt"
        assert email.text_body =~ "Pokój z kotami"
        assert email.text_body =~ "Pokój dla kociarzy"
      end)

      for asked <- [cats, no_pets, stale], do: assert(Repo.reload!(asked).jev_analyzed_at)
      for skipped <- [no_text, sale], do: refute(Repo.reload!(skipped).jev_signals)

      # Answers are stored, so the next run asks nothing
      Req.Test.stub(Rzeczywiscie.Services.Jev, fn _conn -> flunk("asked Jev again") end)
      assert {:ok, :no_matches} = Alerts.run_alert(Alerts.get_alert(alert.id))
    end

    test "stops asking after three failures in a row" do
      alert = alert(%{criteria: %{"jev_yes" => ["pets_allowed"]}})
      for i <- 1..4, do: property(%{title: "Pokój #{i}", description: "Opis."})
      test = self()

      Req.Test.stub(Rzeczywiscie.Services.Jev, fn conn ->
        send(test, :asked)
        Plug.Conn.send_resp(conn, 529, ~s({"error":"overloaded"}))
      end)

      assert {:ok, :no_matches} = Alerts.run_alert(alert)
      for _ <- 1..3, do: assert_received(:asked)
      refute_received :asked
    end
  end

  describe "alert emails" do
    test "escapes scraped titles in the HTML part" do
      alert = alert()
      property(%{title: "Dom <script>alert('xss')</script> 120m2"})

      assert {:ok, {:sent, 1}} = Alerts.run_alert(alert)

      assert_email_sent(fn email ->
        refute email.html_body =~ "<script>"
        assert email.html_body =~ "&lt;script&gt;"
      end)
    end

    test "survives listings with missing price and area" do
      alert = alert()
      property(%{title: "Brak ceny", price: nil, area_sqm: nil, rooms: nil, city: nil})

      assert {:ok, {:sent, 1}} = Alerts.run_alert(alert)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Price not given"
        assert email.text_body =~ "Area not given"
        assert email.text_body =~ "Location unknown"
      end)
    end

    test "summarises the criteria in the digest header" do
      alert =
        alert(%{
          name: "Cheap",
          criteria: %{"voivodeship" => "podkarpackie", "max_price" => 300_000}
        })

      property(%{price: Decimal.new("100000")})

      assert {:ok, {:sent, 1}} = Alerts.run_alert(alert)

      assert_email_sent(fn email ->
        assert email.text_body =~ "Podkarpackie"
        assert email.text_body =~ "up to 300 000 zł"
      end)
    end
  end

  describe "run_all/1" do
    test "summarises what went out" do
      enabled = alert(%{name: "Enabled"})
      paused = alert(%{name: "Paused"})
      {:ok, _} = Alerts.update_alert(paused, %{enabled: false})

      property()

      summary = Alerts.run_all()

      assert summary.alerts == 1
      assert summary.emails_sent == 1
      assert summary.listings_notified == 1
      assert summary.failed == 0

      # The paused alert reported nothing and holds its match for later
      assert Alerts.count_pending_matches(Alerts.get_alert(paused.id)) == 1
      assert Alerts.count_pending_matches(Alerts.get_alert(enabled.id)) == 0
    end
  end
end
