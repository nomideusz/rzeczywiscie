defmodule Rzeczywiscie.RealEstate.DealScorerTest do
  use ExUnit.Case, async: true

  alias Rzeczywiscie.RealEstate.{DealScorer, Property}

  defp flat(title) do
    %Property{
      title: title,
      property_type: "mieszkanie",
      transaction_type: "sprzedaż",
      price: Decimal.new(450_000),
      area_sqm: Decimal.new(50)
    }
  end

  test "a title mentioning a garage, plot or location doesn't knock a home out" do
    for title <- [
          "Nowe 2-pokojowe mieszkanie z balkonem i garażem",
          "Bochnia/Mikluszowice przy Puszczy+ działka altana",
          "Komfortowe mieszkanie - super lokalizacja",
          "Nowoczesne mieszkanie na Osiedlu Podhalanin w Wadowicach"
        ] do
      assert DealScorer.valid_for_scoring?(flat(title)), title
    end
  end

  test "containers and pavilions filed as flats stay out" do
    refute DealScorer.valid_for_scoring?(
             flat("Gotowy od ręki Pawilon/Kontener Handlowy/Biurowy 7x3")
           )
  end
end
