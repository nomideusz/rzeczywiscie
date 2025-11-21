defmodule Rzeczywiscie.Scrapers.OlxScraper do
  @moduledoc """
  Scraper for OLX.pl real estate listings in Malopolskie region.
  """

  require Logger
  alias Rzeczywiscie.RealEstate

  @base_url "https://www.olx.pl"
  @malopolskie_url "#{@base_url}/nieruchomosci/malopolskie/"

  @doc """
  Scrape properties from OLX for Malopolskie region.

  ## Options
    * `:pages` - Number of pages to scrape (default: 1)
    * `:delay` - Delay between requests in milliseconds (default: 2000)
  """
  def scrape(opts \\ []) do
    pages = Keyword.get(opts, :pages, 1)
    delay = Keyword.get(opts, :delay, 2000)

    Logger.info("Starting OLX scrape for Malopolskie region, #{pages} page(s)")

    results =
      1..pages
      |> Enum.flat_map(fn page ->
        url = if page == 1, do: @malopolskie_url, else: "#{@malopolskie_url}?page=#{page}"

        case fetch_page(url) do
          {:ok, html} ->
            properties = parse_listings(html)
            Logger.info("Scraped page #{page}: found #{length(properties)} properties")

            # Add delay between requests to be respectful
            if page < pages, do: Process.sleep(delay)

            properties

          {:error, reason} ->
            Logger.error("Failed to fetch page #{page}: #{inspect(reason)}")
            []
        end
      end)

    # Save to database
    saved =
      Enum.map(results, fn property_data ->
        case RealEstate.upsert_property(property_data) do
          {:ok, property} ->
            {:ok, property}

          {:error, changeset} ->
            Logger.error("Failed to save property: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
      end)

    successful = Enum.count(saved, fn {status, _} -> status == :ok end)
    Logger.info("OLX scrape completed: #{successful}/#{length(results)} properties saved")

    {:ok, %{total: length(results), saved: successful}}
  end

  defp fetch_page(url) do
    Logger.debug("Fetching: #{url}")

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
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_listings(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # OLX uses data-cy="l-card" for listing cards
        document
        |> Floki.find("[data-cy='l-card']")
        |> Enum.map(&parse_listing/1)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        Logger.error("Failed to parse HTML: #{inspect(reason)}")
        []
    end
  end

  defp parse_listing(card) do
    # Extract data from listing card
    with {:ok, external_id} <- extract_id(card),
         {:ok, url} <- extract_url(card),
         {:ok, title} <- extract_title(card) do
      %{
        source: "olx",
        external_id: external_id,
        title: String.trim(title),
        url: ensure_absolute_url(url),
        price: extract_price(card),
        currency: "PLN",
        area_sqm: extract_area(card),
        rooms: extract_rooms(card),
        city: extract_city(card),
        district: extract_district(card),
        voivodeship: "małopolskie",
        image_url: extract_image(card),
        description: extract_description(card),
        raw_data: %{
          scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    else
      {:error, reason} ->
        Logger.debug("Skipping listing: #{inspect(reason)}")
        nil
    end
  end

  defp extract_id(card) do
    case Floki.attribute(card, "id") do
      [id | _] when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :no_id}
    end
  end

  defp extract_url(card) do
    case Floki.find(card, "a[data-cy='listing-ad-title']") do
      [{_tag, attrs, _} | _] ->
        case List.keyfind(attrs, "href", 0) do
          {"href", url} when is_binary(url) -> {:ok, url}
          _ -> {:error, :no_url}
        end

      _ ->
        {:error, :no_url}
    end
  end

  defp extract_title(card) do
    case Floki.find(card, "h6") |> Floki.text() do
      "" -> {:error, :no_title}
      title -> {:ok, title}
    end
  end

  defp extract_price(card) do
    card
    |> Floki.find("p[data-testid='ad-price']")
    |> Floki.text()
    |> parse_price()
  end

  defp parse_price(text) do
    text
    |> String.replace(~r/[^\d,]/, "")
    |> String.replace(",", ".")
    |> case do
      "" -> nil
      price_str ->
        case Decimal.parse(price_str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp extract_area(card) do
    card
    |> Floki.text()
    |> extract_number_with_unit("m²")
  end

  defp extract_rooms(card) do
    card
    |> Floki.text()
    |> extract_number_with_unit("pokoje")
    |> case do
      nil -> nil
      decimal -> Decimal.to_integer(decimal)
    end
  end

  defp extract_number_with_unit(text, unit) do
    regex = Regex.compile!("(\\d+[,\\.]?\\d*)\\s*#{Regex.escape(unit)}")

    case Regex.run(regex, text) do
      [_, number] ->
        number
        |> String.replace(",", ".")
        |> Decimal.parse()
        |> case do
          {decimal, _} -> decimal
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_city(card) do
    card
    |> Floki.find("p[data-testid='location-date']")
    |> Floki.text()
    |> String.split("-")
    |> List.first()
    |> case do
      nil -> nil
      city -> String.trim(city)
    end
  end

  defp extract_district(card) do
    # Try to extract district from location text
    card
    |> Floki.find("p[data-testid='location-date']")
    |> Floki.text()
    |> String.split(",")
    |> Enum.at(1)
    |> case do
      nil -> nil
      district -> String.trim(district) |> String.split("-") |> List.first() |> String.trim()
    end
  end

  defp extract_image(card) do
    card
    |> Floki.find("img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_description(card) do
    card
    |> Floki.find("p")
    |> Enum.map(&Floki.text/1)
    |> Enum.join(" ")
    |> String.slice(0, 500)
  end

  defp ensure_absolute_url(url) do
    if String.starts_with?(url, "http") do
      url
    else
      @base_url <> url
    end
  end
end
