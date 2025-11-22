defmodule Rzeczywiscie.Services.Geocoding do
  @moduledoc """
  Google Geocoding API integration to convert addresses to coordinates.
  """

  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"

  @doc """
  Geocode an address to get latitude and longitude.

  ## Examples

      iex> geocode("Kraków, Małopolskie, Poland")
      {:ok, %{lat: 50.0646, lng: 19.9450}}

      iex> geocode("")
      {:error, :invalid_address}
  """
  def geocode(address) when is_binary(address) and address != "" do
    api_key = Application.get_env(:rzeczywiscie, :google_maps_api_key, "")

    if api_key == "" do
      Logger.warning("Google Maps API key not configured")
      {:error, :api_key_not_configured}
    else
      params = %{
        address: address,
        key: api_key,
        region: "pl"  # Prefer Polish results
      }

      url = "#{@base_url}?#{URI.encode_query(params)}"

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          parse_geocoding_response(body)

        {:ok, %{status: status}} ->
          Logger.error("Geocoding API returned status #{status}")
          {:error, :api_error}

        {:error, reason} ->
          Logger.error("Geocoding request failed: #{inspect(reason)}")
          {:error, :request_failed}
      end
    end
  end

  def geocode(_), do: {:error, :invalid_address}

  @doc """
  Geocode a property using city, district, and street information.
  """
  def geocode_property(property) do
    address = build_address_string(property)

    if address && address != "" do
      geocode(address)
    else
      {:error, :insufficient_location_data}
    end
  end

  defp build_address_string(property) do
    parts = [
      property.street,
      property.district,
      property.city,
      property.voivodeship || "małopolskie",
      "Poland"
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp parse_geocoding_response(%{"status" => "OK", "results" => [result | _]}) do
    location = get_in(result, ["geometry", "location"])

    if location && location["lat"] && location["lng"] do
      {:ok,
       %{
         lat: Decimal.from_float(location["lat"]),
         lng: Decimal.from_float(location["lng"]),
         formatted_address: result["formatted_address"]
       }}
    else
      {:error, :invalid_response}
    end
  end

  defp parse_geocoding_response(%{"status" => "ZERO_RESULTS"}) do
    {:error, :not_found}
  end

  defp parse_geocoding_response(%{"status" => "OVER_QUERY_LIMIT"}) do
    Logger.warning("Geocoding API quota exceeded")
    {:error, :quota_exceeded}
  end

  defp parse_geocoding_response(%{"status" => status}) do
    Logger.error("Geocoding API returned unexpected status: #{status}")
    {:error, :api_error}
  end

  defp parse_geocoding_response(_) do
    {:error, :invalid_response}
  end
end
