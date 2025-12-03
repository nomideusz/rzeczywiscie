defmodule Rzeczywiscie.Services.StreetExtractor do
  @moduledoc """
  Extracts street names from property titles and descriptions.
  Uses regex patterns and a database of known Kraków streets.
  """

  # Common Kraków street names (without "ul." prefix)
  # These are streets that often appear in listings
  @known_streets [
    # Major streets
    "kościuszki", "kosciuszki",
    "królewska",
    "floriańska", "florianska",
    "grodzka",
    "długa", "dluga",
    "szewska",
    "sławkowska", "slawkowska",
    "starowiślna", "starowislna",
    "dietla",
    "karmelicka",
    "piłsudskiego", "pilsudskiego",
    "lubicz",
    "pawia",
    "basztowa",
    "podwale",
    "powiśle", "powisle",
    "bulwary", "bulwarowa",
    "kalwaryjska",
    "limanowskiego",
    "wielicka",
    "zakopiańska", "zakopianska",
    "kapelanka",
    "konopnickiej",
    "monte cassino",
    "armii krajowej",
    "nowohucka",
    "aleja pokoju",
    "al. pokoju",
    "bieńczycka", "bienczycka",
    "kocmyrzowska",
    
    # Salwator / Zwierzyniec area
    "stachowicza",
    "królowej jadwigi",
    "kasztanowa",
    "wąska", "waska",
    "senatorska",
    "salwatorska",
    "księcia józefa", "ksiecia jozefa",
    "korzeniaka",
    
    # Wola Justowska area
    "emaus",
    "olszanicka",
    "jesionowa",
    "piastowska",
    "hamernia",
    "wiosenna",
    "pod fortem",
    
    # Bronowice area
    "armii krajowej",
    "bronowicka",
    "balicka",
    "widłakowa", "widlakowa",
    
    # Krowodrza area
    "lea",
    "królewska", "krolewska",
    "łobzowska", "lobzowska",
    "nawojki",
    "prądnicka", "pradnicka",
    "krowoderska",
    "długa", "dluga",
    
    # Kazimierz / Podgórze area
    "józefa", "jozefa",
    "szeroka",
    "miodowa",
    "bożego ciała", "bozego ciala",
    "mostowa",
    "paulińska", "paulinska",
    "skałeczna", "skaleczna",
    "nadwiślańska", "nadwislanska",
    "limanowskiego",
    "lwowska",
    "wadowicka",
    "przemysłowa", "przemyslowa",
    
    # Prądnik / Czyżyny area
    "opolska",
    "lublańska", "lublanska",
    "meissnera",
    "bratysławska", "bratyslawska",
    "bieńczycka", "bienczycka",
    
    # Other notable streets
    "tyniecka",
    "bolesława śmiałego", "boleslawa smialego",
    "malborska",
    "ks. popiełuszki", "ks. popieluszki",
    "aleja jana pawła ii", "al. jana pawła ii",
    "powstańców wielkopolskich", "powstancow wielkopolskich"
  ]

  @doc """
  Extracts street name from title and/or description.
  Returns %{street: "Kościuszki", street_number: "22", confidence: :high/:medium/:low} or nil
  """
  def extract(title, description \\ nil) do
    # Try title first, then description
    case extract_from_text(title) do
      nil -> 
        if description, do: extract_from_text(description), else: nil
      result -> 
        result
    end
  end

  @doc """
  Extract street from a single text.
  """
  def extract_from_text(nil), do: nil
  def extract_from_text(""), do: nil
  
  def extract_from_text(text) when is_binary(text) do
    text_lower = String.downcase(text)
    
    # Try patterns in order of confidence
    result = 
      extract_with_ul_prefix(text) ||           # "ul. Kościuszki 22" - highest confidence
      extract_with_ulica_prefix(text) ||        # "ulica Kościuszki" 
      extract_known_street(text_lower) ||       # Known street names
      extract_street_pattern(text)              # Generic street patterns
    
    result
  end

  # Pattern: "ul." or "UL." followed by street name and optional number
  defp extract_with_ul_prefix(text) do
    # Matches: ul. Kościuszki 22, UL. EMAUS, ul.Stachowicza, etc.
    pattern = ~r/\bul\.?\s*([A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż][a-ząćęłńóśźż]+(?:\s+[A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż]+)?)\s*(\d+[a-zA-Z]?)?/iu
    
    case Regex.run(pattern, text) do
      [_full, street | rest] ->
        number = List.first(rest)
        %{
          street: normalize_street_name(street),
          street_number: number,
          confidence: :high,
          source: "ul_prefix"
        }
      _ -> nil
    end
  end

  # Pattern: "ulica" followed by street name
  defp extract_with_ulica_prefix(text) do
    pattern = ~r/\bulica\s+([A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż][a-ząćęłńóśźż]+(?:\s+[A-ZĄĆĘŁŃÓŚŹŻa-ząćęłńóśźż]+)?)\s*(\d+[a-zA-Z]?)?/iu
    
    case Regex.run(pattern, text) do
      [_full, street | rest] ->
        number = List.first(rest)
        %{
          street: normalize_street_name(street),
          street_number: number,
          confidence: :high,
          source: "ulica_prefix"
        }
      _ -> nil
    end
  end

  # Check for known Kraków streets
  defp extract_known_street(text_lower) do
    # Find all matching known streets
    matches = @known_streets
    |> Enum.filter(fn street -> 
      # Check if street name appears as a word boundary
      pattern = ~r/\b#{Regex.escape(street)}\b/i
      Regex.match?(pattern, text_lower)
    end)
    |> Enum.sort_by(&String.length/1, :desc)  # Prefer longer matches
    
    case matches do
      [street | _] ->
        # Try to find street number nearby
        number = extract_nearby_number(text_lower, street)
        %{
          street: normalize_street_name(street),
          street_number: number,
          confidence: :medium,
          source: "known_street"
        }
      [] -> nil
    end
  end

  # Generic pattern for streets ending in common suffixes
  defp extract_street_pattern(text) do
    # Polish street names often end in: -ego, -iej, -ów, -a, -y, -i
    # Match capitalized words with these endings
    pattern = ~r/\b([A-ZĄĆĘŁŃÓŚŹŻ][a-ząćęłńóśźż]*(?:ego|iej|ów|owa|owej|skiego|skiej|ickiego|ickiej|ńskiego|ńskiej))\s*(\d+[a-zA-Z]?)?/u
    
    case Regex.run(pattern, text) do
      [_full, street | rest] ->
        number = List.first(rest)
        %{
          street: normalize_street_name(street),
          street_number: number,
          confidence: :low,
          source: "pattern_match"
        }
      _ -> nil
    end
  end

  # Try to find a number near the street name
  defp extract_nearby_number(text, street_name) do
    # Look for pattern: street_name + optional space + number
    pattern = ~r/#{Regex.escape(street_name)}\s*(\d+[a-zA-Z]?)/i
    
    case Regex.run(pattern, text) do
      [_, number] -> number
      _ -> nil
    end
  end

  # Normalize street name to title case
  defp normalize_street_name(street) do
    street
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.map(&capitalize_word/1)
    |> Enum.join(" ")
  end

  defp capitalize_word(word) do
    # Handle Polish characters properly
    {first, rest} = String.split_at(word, 1)
    String.upcase(first) <> String.downcase(rest)
  end

  @doc """
  Updates a property with extracted street if not already set.
  Returns {:ok, updated_attrs} or {:skip, reason}
  """
  def enrich_property_attrs(attrs) do
    current_street = attrs[:street] || attrs["street"]
    
    # Skip if street already set and not empty
    if current_street && String.trim(to_string(current_street)) != "" do
      {:skip, :already_has_street}
    else
      title = attrs[:title] || attrs["title"]
      description = attrs[:description] || attrs["description"]
      
      case extract(title, description) do
        nil -> 
          {:skip, :no_street_found}
        
        %{street: street, street_number: number, confidence: confidence} ->
          full_street = if number, do: "#{street} #{number}", else: street
          
          {:ok, %{
            street: full_street,
            street_extraction_confidence: to_string(confidence)
          }}
      end
    end
  end

  @doc """
  Process a batch of properties and extract streets.
  Returns stats about extraction.
  """
  def process_batch(properties) when is_list(properties) do
    alias Rzeczywiscie.RealEstate
    
    results = Enum.map(properties, fn property ->
      case extract(property.title, property.description) do
        nil -> 
          {:skip, property.id}
        
        %{street: street, street_number: number, confidence: _confidence} ->
          full_street = if number, do: "#{street} #{number}", else: street
          
          case RealEstate.update_property(property, %{street: full_street}) do
            {:ok, _} -> {:updated, property.id}
            {:error, _} -> {:error, property.id}
          end
      end
    end)
    
    %{
      total: length(results),
      updated: Enum.count(results, fn {status, _} -> status == :updated end),
      skipped: Enum.count(results, fn {status, _} -> status == :skip end),
      errors: Enum.count(results, fn {status, _} -> status == :error end)
    }
  end
end

