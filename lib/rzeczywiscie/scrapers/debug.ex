defmodule Rzeczywiscie.Scrapers.Debug do
  @moduledoc """
  Debug helper for testing scrapers.
  """

  require Logger

  def fetch_and_inspect_olx do
    url = "https://www.olx.pl/nieruchomosci/malopolskie/"

    case Req.get(url,
           headers: [
             {"user-agent",
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
             {"accept",
              "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
             {"accept-language", "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7"}
           ],
           max_redirects: 3,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("Successfully fetched page, body length: #{String.length(body)}")

        # Save to file for inspection
        File.write!("/tmp/olx_debug.html", body)
        Logger.info("Saved HTML to /tmp/olx_debug.html")

        # Try to parse and find common elements
        case Floki.parse_document(body) do
          {:ok, document} ->
            inspect_structure(document)
          {:error, reason} ->
            Logger.error("Failed to parse: #{inspect(reason)}")
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("HTTP #{status}")
        Logger.info("Response body: #{String.slice(body, 0, 500)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp inspect_structure(document) do
    # Try various common selectors
    selectors = [
      "[data-cy='l-card']",
      "div[data-cy='l-card']",
      ".css-1sw7q4x",
      "article",
      "[data-testid='listing-grid']",
      "[data-testid='listing-card']",
      "div[data-cy]"
    ]

    Enum.each(selectors, fn selector ->
      elements = Floki.find(document, selector)
      count = length(elements)
      Logger.info("Selector '#{selector}': found #{count} elements")

      if count > 0 do
        # Show first element structure
        first = List.first(elements)
        Logger.info("First element: #{inspect(first, limit: 500)}")
      end
    end)

    # Check for any divs with data-cy attribute
    all_data_cy = Floki.find(document, "[data-cy]")
    data_cy_attrs =
      all_data_cy
      |> Enum.map(fn {_tag, attrs, _children} ->
        Enum.find_value(attrs, fn
          {"data-cy", value} -> value
          _ -> nil
        end)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.take(20)

    Logger.info("Found data-cy attributes: #{inspect(data_cy_attrs)}")
  end
end
