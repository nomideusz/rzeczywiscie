defmodule Rzeczywiscie.RealEstate.Voivodeships do
  @moduledoc """
  Registry of the voivodeships (województwa) the aggregator covers.

  Everything region-specific lives here so adding a region is a single entry:

    * `:name` - canonical value stored in `properties.voivodeship` (lowercase, Polish spelling)
    * `:slug` - ASCII slug used in URLs and accepted from clients
    * `:label` - display name for the UI
    * `:olx_region_id` - OLX API `region_id` (verified against the live API)
    * `:otodom_slug` - path segment in Otodom search URLs
    * `:capital` / `:center` - fallback map center for the region
  """

  @voivodeships [
    %{
      name: "małopolskie",
      slug: "malopolskie",
      label: "Małopolskie",
      olx_region_id: 4,
      otodom_slug: "malopolskie",
      capital: "Kraków",
      center: %{lat: 50.0647, lng: 19.9450}
    },
    %{
      name: "podkarpackie",
      slug: "podkarpackie",
      label: "Podkarpackie",
      olx_region_id: 17,
      otodom_slug: "podkarpackie",
      capital: "Rzeszów",
      center: %{lat: 50.0413, lng: 21.9990}
    }
  ]

  @default hd(@voivodeships)

  @doc "All supported voivodeships, in display order."
  def all, do: @voivodeships

  @doc "The region used when nothing else is specified (małopolskie, the original coverage area)."
  def default, do: @default

  @doc "Canonical stored names, e.g. [\"małopolskie\", \"podkarpackie\"]."
  def names, do: Enum.map(@voivodeships, & &1.name)

  @doc "ASCII slugs, e.g. [\"malopolskie\", \"podkarpackie\"]."
  def slugs, do: Enum.map(@voivodeships, & &1.slug)

  @doc """
  Look up a voivodeship by name, slug or label - case and diacritic insensitive.

  Returns `nil` for anything unsupported.

      iex> Voivodeships.get("Podkarpackie").olx_region_id
      17
  """
  def get(nil), do: nil

  def get(value) when is_binary(value) do
    key = ascii_key(value)

    Enum.find(@voivodeships, fn v ->
      ascii_key(v.name) == key or v.slug == key or ascii_key(v.label) == key
    end)
  end

  def get(%{name: name}), do: get(name)
  def get(_), do: nil

  @doc "Same as `get/1` but raises for unsupported values."
  def fetch!(value) do
    get(value) ||
      raise ArgumentError,
            "unknown voivodeship #{inspect(value)}, supported: #{Enum.join(slugs(), ", ")}"
  end

  @doc """
  Normalize any spelling to the canonical stored name, or `nil` when unsupported.

      iex> Voivodeships.normalize("Małopolskie")
      "małopolskie"
  """
  def normalize(value) do
    case get(value) do
      nil -> nil
      voivodeship -> voivodeship.name
    end
  end

  @doc "True when the value names a supported voivodeship."
  def supported?(value), do: get(value) != nil

  @doc """
  Resolve a list of voivodeship names/slugs into registry entries.

  `nil`, `[]` or `"all"` expand to every supported region so callers that don't
  care about regions keep scraping everything.
  """
  def resolve(nil), do: all()
  def resolve([]), do: all()
  def resolve("all"), do: all()
  def resolve(value) when is_binary(value), do: resolve([value])
  def resolve(%{} = value), do: resolve([value])

  def resolve(values) when is_list(values) do
    case Enum.map(values, &get/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> all()
      resolved -> resolved
    end
  end

  @doc "Options for a `<select>` in the UI: `[%{value: name, label: label}]`."
  def select_options do
    Enum.map(@voivodeships, &%{value: &1.name, label: &1.label, slug: &1.slug, center: &1.center})
  end

  defp ascii_key(value) do
    value
    |> String.downcase()
    |> String.replace("ó", "o")
    |> String.replace("ą", "a")
    |> String.replace("ę", "e")
    |> String.replace("ł", "l")
    |> String.replace("ń", "n")
    |> String.replace("ś", "s")
    |> String.replace("ć", "c")
    |> String.replace("ż", "z")
    |> String.replace("ź", "z")
    |> String.trim()
  end
end
