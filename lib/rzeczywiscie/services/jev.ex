defmodule Rzeczywiscie.Services.Jev do
  @moduledoc """
  Typed judgments about a listing from TypeSafe's Jev model: what is really
  on offer, which features the property has, its condition and how hard the
  seller is pushing. All questions go out in one request per listing.

  Runs next to the GPT analyzer (step 3 of `LLMAnalysisWorker`) and for
  alerts with Jev criteria (`Rzeczywiscie.Alerts`); /admin compares the
  answers with GPT's. Answers are stored verbatim in `properties.jev_signals`
  under the question ids below, so thresholds and weights can be tuned later
  without asking the model again:

    * Noul: `%{"noul" => p}`, the probability that the answer is yes
    * Choice: `%{"choice" => option, "probabilities" => %{option => p}, "confidence" => c}`
    * Score: `%{"score" => s, "probabilities" => %{"0" => p, ...}, "confidence" => c}`,
      with `s` from 0 to (number of levels - 1)

  Question ids never reach the model, so every question carries its whole
  meaning. Listings are Polish; questions are English (Jev's strongest
  language) with the Polish phrasing quoted.
  """

  @url "https://api.typesafe.ai/v1/systemone"
  # Pinned: thresholds get tuned against a model version, so bump it on purpose.
  @model "jev-1.13.0"
  # A yes/no answer at or above this counts as yes. From the 2026-09-23 smoke
  # test on 39 listings: true cases scored 0.9 or more, false ones 0.42 at most.
  @yes_threshold 0.7
  # Descriptions top out around 10k characters; the cap keeps a scraping
  # accident inside the model's context instead of failing every run.
  @max_description 20_000

  @questions %{
    # What is really on offer: the usual reasons a price sits far below the median.
    "fractional_share" => %{
      type: "noul",
      instructions:
        "Does `listing` offer only a fractional share of the property ('udział', e.g. '1/2 udziału') rather than the whole of it?",
      criteria: %{
        "true" =>
          "The buyer gets part of the ownership, e.g. 1/2 or 1/3 of a flat or house, shared with other co-owners.",
        "false" =>
          "The whole flat, house, room or plot is offered. A flat's usual share in the building's land or common parts ('udział w gruncie', 'udział w nieruchomości wspólnej') does not count."
      }
    },
    "sitting_tenant" => %{
      type: "noul",
      instructions:
        "Is the property in `listing` for sale with a tenant who lives in it and stays after the sale ('z lokatorem', 'z najemcą')?",
      criteria: %{
        "true" =>
          "A tenant or occupant stays after the sale, under a lease or a protected tenancy.",
        "false" =>
          "Nobody stays after the sale, or `listing` is a rental offer. A storage room called 'komórka lokatorska' or a flatmate ('współlokator') does not count."
      }
    },
    "forced_sale" => %{
      type: "noul",
      instructions:
        "Is the property in `listing` sold by a bailiff, a court or a bankruptcy trustee ('licytacja komornicza', 'syndyk') rather than by its owner or the owner's agent?"
    },
    "occupancy_right" => %{
      type: "noul",
      instructions:
        "Is `listing` selling something short of ownership, such as a co-operative tenant's right ('spółdzielcze lokatorskie prawo do lokalu') or a TBS participation ('partycypacja', 'TBS')?",
      criteria: %{
        "true" => "The buyer gets only a right to occupy or rent the property.",
        "false" =>
          "Ownership ('własność', 'odrębna własność'), or a co-operative ownership right ('spółdzielcze własnościowe prawo do lokalu') that can be sold and mortgaged like ownership, or `listing` is an ordinary rental offer."
      }
    },
    "contract_assignment" => %{
      type: "noul",
      instructions:
        "Is the seller in `listing` someone who signed a contract with a developer for a flat and now transfers that contract to a new buyer ('cesja umowy deweloperskiej', 'cesja umowy przedwstępnej')?",
      criteria: %{
        "true" =>
          "A contract assignment: the new buyer takes over another buyer's contract with the developer.",
        "false" =>
          "The owner sells the property, or a developer sells its own flats, including flats still being built or handed over later."
      }
    },
    "product" => %{
      type: "noul",
      instructions:
        "Is `listing` selling a structure to be built, delivered or assembled, or one that can be moved (a prefab or modular house, a house kit, a metal garage 'blaszak', a container, a pavilion), rather than real estate?",
      criteria: %{
        "true" =>
          "A product: made or assembled for the buyer, or moved onto the buyer's own land; delivery, assembly or a manufacturer ('producent', 'montaż') is mentioned.",
        "false" =>
          "An existing flat, house, room, plot or commercial unit, including a timber-frame or modular house that already stands on its own plot and is sold with the land."
      }
    },
    "wanted_ad" => %{
      type: "noul",
      instructions:
        "Is `listing` posted by someone who wants to buy or rent a property ('kupię', 'szukam mieszkania', 'poszukuję'), rather than by someone offering one?",
      criteria: %{
        "true" => "The author wants to acquire or rent a property.",
        "false" =>
          "The author offers a property for sale or rent, even when writing that they are looking for a buyer or tenant ('szukam najemcy', 'poszukujemy lokatora')."
      }
    },
    "swap" => %{
      type: "noul",
      instructions:
        "Does `listing` offer to swap the property for another property ('zamiana', 'zamienię'), alone or as an alternative to selling it?"
    },

    # Features, as filters. Portal fields come first; these fill the gaps.
    "balcony" => %{
      type: "noul",
      instructions:
        "Does the property in `listing` have a balcony, loggia or terrace ('balkon', 'loggia', 'taras')?"
    },
    "parking" => %{
      type: "noul",
      instructions:
        "Does `listing` include a parking space or garage with the property, or offer one with it ('miejsce parkingowe', 'miejsce postojowe', 'garaż')?",
      criteria: %{
        "true" =>
          "A dedicated parking space or garage comes with the property or is offered with it.",
        "false" =>
          "Parking is not mentioned, or only public, street or free parking nearby is mentioned."
      }
    },
    "lift" => %{
      type: "noul",
      instructions: "Does the building in `listing` have a lift ('winda')?"
    },
    "cellar" => %{
      type: "noul",
      instructions:
        "Does the property in `listing` come with a cellar or a separate storage room ('piwnica', 'komórka lokatorska')?"
    },
    "garden" => %{
      type: "noul",
      instructions:
        "Does the property in `listing` have a garden for its own use ('ogród', 'ogródek')?",
      criteria: %{
        "true" => "A private garden, or a garden plot reserved for this property.",
        "false" => "No garden, or only a shared courtyard or the estate's common green space."
      }
    },
    "ground_floor" => %{
      type: "noul",
      instructions:
        "Is the flat or room in `listing` on the ground floor of its building ('parter')?",
      criteria: %{
        "true" => "The flat or room is on the ground floor.",
        "false" =>
          "It is on the first floor or higher, the floor is not stated, or `listing` offers a whole house ('dom parterowy' is a single-storey house)."
      }
    },
    "pets_allowed" => %{
      type: "noul",
      instructions:
        "Does `listing` accept pets such as cats or dogs, or say they can be agreed with the owner ('zwierzęta akceptowane', 'przyjazne zwierzętom', 'zwierzęta do uzgodnienia')?",
      criteria: %{
        "true" => "Pets are welcome, or can be agreed with the owner.",
        "false" =>
          "Pets are not accepted ('bez zwierząt', 'nie akceptujemy zwierząt'), or `listing` does not mention pets."
      }
    },
    "pets_forbidden" => %{
      type: "noul",
      instructions:
        "Does `listing` rule out pets ('bez zwierząt', 'zwierzęta nie są akceptowane', 'dla osoby nieposiadającej zwierząt')?",
      criteria: %{
        "true" => "Pets are not accepted, or the tenant must not have pets.",
        "false" => "Pets are welcome or can be agreed, or `listing` does not mention pets."
      }
    },
    "furnished" => %{
      type: "noul",
      instructions: "Is the property in `listing` offered with furniture ('umeblowane')?",
      criteria: %{
        "true" => "Furniture is included, fully or partly.",
        "false" =>
          "It is unfurnished ('nieumeblowane'), only kitchen appliances are included, or furniture is not mentioned."
      }
    },
    "no_commission" => %{
      type: "noul",
      instructions:
        "Does `listing` say the buyer or tenant pays no agency commission ('bez prowizji', '0% prowizji', 'bezpośrednio od właściciela')?"
    },
    # Rental terms
    "long_term" => %{
      type: "noul",
      instructions:
        "Is the property in `listing` let for months or longer, rather than by the night or week ('na doby', 'noclegi', 'wynajem krótkoterminowy')?",
      criteria: %{
        "true" => "A lease of a month or longer, at a monthly rent.",
        "false" =>
          "Stays paid by the night or week, holiday or short-term lets, or `listing` is not a rental."
      }
    },
    "bed_space" => %{
      type: "noul",
      instructions:
        "Does `listing` offer beds rather than a home: a place in a room shared with other tenants ('miejsce w pokoju 2-osobowym'), or a house or flat fitted out as quarters for a group of workers ('kwatery pracownicze', 'dom dla pracowników', 'dom dla 10 osób')?",
      criteria: %{
        "true" =>
          "A bed or place in a shared room, or group quarters for workers, often priced per person.",
        "false" =>
          "A private room, or a whole flat or house for one tenant, a couple or a family who live there, even if they may sublet rooms; or `listing` is a sale."
      }
    },
    "sublet_forbidden" => %{
      type: "noul",
      instructions:
        "Does `listing` forbid subletting or sharing the property with other tenants, for example by letting it only to a family ('zakaz podnajmu', 'tylko dla rodziny', 'nie dla grup')?",
      criteria: %{
        "true" =>
          "Subletting or flatmates are ruled out, or the property is let only to a family.",
        "false" =>
          "Subletting or several tenants are allowed, or `listing` says nothing about it."
      }
    },

    # Condition and seller pressure. Options match the llm_condition values.
    "condition" => %{
      type: "choice",
      instructions: "What condition is the property in `listing` in, according to the listing?",
      criteria: %{
        "needs_renovation" =>
          "Needs renovation or modernization before comfortable use ('do remontu', 'do modernizacji').",
        "to_finish" =>
          "The interior is unfinished and needs finishing work ('stan deweloperski', 'do wykończenia', 'stan surowy').",
        "good" =>
          "Habitable as it is, in decent or good condition, with no recent renovation mentioned.",
        "renovated" =>
          "Recently renovated or refurbished ('po remoncie', 'po generalnym remoncie', 'odnowione').",
        "new" => "Newly built and finished, and nobody has lived in it yet.",
        "unknown" => "The listing does not describe the condition."
      }
    },
    "seller_pressure" => %{
      type: "score",
      instructions: "How much pressure to sell or let quickly does `listing` show?",
      criteria: [
        "None: a standard offer at a stated price. Being available immediately ('od zaraz') is not pressure.",
        "Some: the price is open to negotiation ('do negocjacji') or was recently lowered ('obniżka', 'nowa cena').",
        "Strong: the seller must sell fast ('pilne', 'pilnie sprzedam', 'szybka sprzedaż'), e.g. because of moving abroad, an inheritance, a divorce, debts or a liquidation."
      ]
    }
  }

  def configured?, do: api_key() != ""

  @doc "Ids of the yes/no questions, the ones alerts can filter on."
  def noul_ids, do: for({id, %{type: "noul"}} <- @questions, do: id) |> Enum.sort()

  def yes_threshold, do: @yes_threshold

  @doc """
  Asks every question about one listing. Returns
  `{:ok, %{"model" => version, "answers" => answers, "usage" => tokens}}`,
  ready to store (usage makes the spend queryable).
  """
  def analyze(%{title: title, description: description} = listing) do
    body = %{
      model: @model,
      state: %{
        # The portal's own fields ride along: agency descriptions often never
        # say that a house is for rent, or that 8000 zł is a monthly rent.
        listing: %{
          title: title,
          description: String.slice(description || "", 0, @max_description),
          transaction_type: Map.get(listing, :transaction_type),
          property_type: Map.get(listing, :property_type),
          price_pln: Map.get(listing, :price)
        }
      },
      questions: @questions
    }

    [url: @url, json: body, auth: {:bearer, api_key()}, retry: &retry?/2]
    |> Keyword.merge(Application.get_env(:rzeczywiscie, :jev_req_options, []))
    |> Req.post()
    |> case do
      {:ok, %{status: 200, body: %{"model" => _, "answers" => _} = body}} ->
        {:ok, Map.take(body, ["model", "answers", "usage"])}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc "Asks about `property` and stores the answers on it. A failure leaves it untouched."
  def analyze_and_store(property) do
    with {:ok, signals} <- analyze(property) do
      Rzeczywiscie.RealEstate.update_property(property, %{
        jev_signals: signals,
        jev_analyzed_at: DateTime.utc_now()
      })
    end
  end

  @doc "Whether stored `jev_signals` answer the yes/no question `id` with yes."
  def yes?(signals, id), do: (get_in(signals, ["answers", id, "noul"]) || 0) >= @yes_threshold

  # The endpoint has no side effects, so a POST is as safe to retry as a GET.
  # 529 is TypeSafe's "overloaded", which Req doesn't count as transient.
  defp retry?(_request, %Req.Response{status: status}), do: status in [429, 529]

  defp retry?(_request, %Req.TransportError{reason: reason}),
    do: reason in [:timeout, :econnrefused, :closed]

  defp retry?(_request, _other), do: false

  defp api_key, do: Application.get_env(:rzeczywiscie, :typesafe_api_key, "")
end
