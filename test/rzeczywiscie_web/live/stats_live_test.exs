defmodule RzeczywiscieWeb.StatsLiveTest do
  use RzeczywiscieWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Rzeczywiscie.RealEstate.Property
  alias Rzeczywiscie.Repo

  defp insert(voivodeship, city, price) do
    Repo.insert!(%Property{
      title: "Mieszkanie #{city}",
      url: "https://example.com/#{System.unique_integer([:positive])}",
      source: "olx",
      external_id: "#{System.unique_integer([:positive])}",
      voivodeship: voivodeship,
      city: city,
      transaction_type: "sprzedaż",
      property_type: "mieszkanie",
      price: Decimal.new(price),
      area_sqm: Decimal.new(50),
      active: true
    })
  end

  test "region picker scopes the page and the all-regions view compares regions", %{conn: conn} do
    insert("śląskie", "Katowice", 400_000)
    insert("śląskie", "Katowice", 500_000)
    insert("opolskie", "Opole", 300_000)

    {:ok, view, html} = live(conn, "/stats")
    assert html =~ "region-comparison"
    # Śląskie median 450k / 50 m² = 9000 zł/m², Opolskie 300k / 50 m² = 6000
    table = view |> element("#region-comparison") |> render()
    assert table =~ "9.0k"
    assert table =~ "6.0k"

    {:ok, _view, html} = live(conn, "/stats?region=opolskie")
    refute html =~ "region-comparison"
    assert html =~ "Opole"
    refute html =~ "Katowice"
  end
end
