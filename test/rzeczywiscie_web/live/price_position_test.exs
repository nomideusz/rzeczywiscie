defmodule RzeczywiscieWeb.PricePositionTest do
  use RzeczywiscieWeb.ConnCase

  import Phoenix.LiveViewTest
  alias Rzeczywiscie.RealEstate

  defp insert_property(attrs) do
    defaults = %{
      source: "olx",
      title: "Test property",
      transaction_type: "sprzedaż",
      property_type: "mieszkanie",
      city: "Kraków",
      district: "Podgórze",
      price: Decimal.new("600000"),
      area_sqm: Decimal.new("50"),
      active: true
    }

    attrs = Map.merge(defaults, Map.new(attrs))
    {:ok, property} = RealEstate.create_property(attrs)
    property
  end

  test "update_price_positions computes percent vs comparable median" do
    # 10 comparables at 10k zł/m² + one listing 20% below
    for i <- 1..10 do
      insert_property(%{
        external_id: "cmp-#{i}",
        url: "https://example.com/cmp-#{i}",
        price: Decimal.new("500000"),
        area_sqm: Decimal.new("50")
      })
    end

    cheap =
      insert_property(%{
        external_id: "cheap",
        url: "https://example.com/cheap",
        price: Decimal.new("400000"),
        area_sqm: Decimal.new("50")
      })

    %{by_district: n, by_city: _} = RealEstate.update_price_positions()
    assert n > 0

    cheap = Rzeczywiscie.Repo.reload!(cheap)
    assert cheap.price_vs_median == -20
    assert cheap.price_median_n == 11
  end

  test "price position reaches the property table props", %{conn: conn} do
    insert_property(%{external_id: "x1", url: "https://example.com/x1"})

    for i <- 1..10 do
      insert_property(%{
        external_id: "cmp-#{i}",
        url: "https://example.com/cmp-#{i}"
      })
    end

    RealEstate.update_price_positions()

    {:ok, view, _html} = live(conn, "/real-estate")
    assert render(view) =~ "price_vs_median"
  end
end
