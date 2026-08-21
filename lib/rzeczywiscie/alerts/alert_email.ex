defmodule Rzeczywiscie.Alerts.AlertEmail do
  @moduledoc """
  Builds the alert digest emails.

  Both a text and an HTML part are always set: the text part is what most
  clients fall back to, and it keeps the mail readable if the HTML is stripped.
  Everything interpolated into the HTML comes from scraped listings, so it all
  goes through `escape/1` - a scraped title is untrusted input.
  """

  import Swoosh.Email

  alias Rzeczywiscie.Alerts
  alias Rzeczywiscie.RealEstate.Voivodeships

  @doc """
  Digest of new listings for one alert.

  ## Options
    * `:to` - recipient address (required)
    * `:remaining` - listings matched but not included, reported in the footer
  """
  def new_listings(alert, properties, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    remaining = Keyword.get(opts, :remaining, 0)
    count = length(properties)

    subject =
      "#{alert.name}: #{count} #{pluralize(count, "new listing", "new listings")}"

    new()
    |> to(to)
    |> from(Alerts.mail_sender())
    |> subject(subject)
    |> text_body(text_body(alert, properties, remaining))
    |> html_body(html_body(alert, properties, remaining))
  end

  @doc """
  Sample digest used to verify the mail path from the admin panel.
  """
  def test_email(properties, opts \\ []) do
    to = Keyword.fetch!(opts, :to)
    alert = %{name: "Test alert", criteria: %{}}

    new()
    |> to(to)
    |> from(Alerts.mail_sender())
    |> subject("Kruk.live: alert test")
    |> text_body(
      "This is a test of the Kruk.live alert mail path.\n\n" <>
        text_body(alert, properties, 0)
    )
    |> html_body(
      "<p style=\"font-family:system-ui,sans-serif;font-size:14px\">This is a test of the Kruk.live alert mail path.</p>" <>
        html_body(alert, properties, 0)
    )
  end

  ## Text part

  defp text_body(alert, properties, remaining) do
    header =
      case criteria_summary(alert.criteria) do
        nil -> alert.name
        summary -> "#{alert.name} — #{summary}"
      end

    listings =
      properties
      |> Enum.map(&text_listing/1)
      |> Enum.join("\n\n")

    [header, String.duplicate("-", String.length(header)), "", listings, "", footer_text(remaining)]
    |> Enum.join("\n")
  end

  defp text_listing(property) do
    """
    #{property.title}
      #{price(property)}#{price_per_sqm_suffix(property)} · #{area(property)}#{rooms_suffix(property)}
      #{location(property)} · #{property.source} · #{type_summary(property)}
      #{property.url}
    """
    |> String.trim_trailing()
  end

  defp footer_text(remaining) do
    base = "All listings: #{site_url()}/real-estate"

    if remaining > 0 do
      "#{remaining} more #{pluralize(remaining, "match", "matches")} waiting — they go out in the next run.\n#{base}"
    else
      base
    end
  end

  ## HTML part

  defp html_body(alert, properties, remaining) do
    rows = properties |> Enum.map(&html_listing/1) |> Enum.join("")

    summary =
      case criteria_summary(alert.criteria) do
        nil -> ""
        text -> ~s(<div style="font-size:12px;text-transform:uppercase;letter-spacing:.05em;opacity:.6;margin-top:4px">#{escape(text)}</div>)
      end

    remaining_note =
      if remaining > 0 do
        ~s(<p style="font-size:12px;opacity:.6;margin:16px 0 0">#{remaining} more #{pluralize(remaining, "match", "matches")} waiting — they go out in the next run.</p>)
      else
        ""
      end

    """
    <div style="font-family:system-ui,-apple-system,'Segoe UI',sans-serif;max-width:640px;margin:0 auto;padding:16px;color:#111">
      <div style="border-bottom:3px solid #111;padding-bottom:12px;margin-bottom:16px">
        <div style="font-size:20px;font-weight:800;text-transform:uppercase;letter-spacing:-.02em">#{escape(alert.name)}</div>
        #{summary}
      </div>
      #{rows}
      #{remaining_note}
      <p style="font-size:12px;margin:24px 0 0;padding-top:12px;border-top:1px solid #ddd">
        <a href="#{escape(site_url())}/real-estate" style="color:#111">See every listing on Kruk.live</a>
      </p>
    </div>
    """
  end

  defp html_listing(property) do
    """
    <div style="border:2px solid #111;padding:12px;margin-bottom:12px">
      <div style="font-size:15px;font-weight:700;line-height:1.3">
        <a href="#{escape(property.url)}" style="color:#111;text-decoration:none">#{escape(property.title)}</a>
      </div>
      <div style="font-size:17px;font-weight:800;margin-top:6px">#{escape(price(property))}</div>
      <div style="font-size:13px;opacity:.7;margin-top:2px">
        #{escape(area(property))}#{escape(price_per_sqm_html_suffix(property))}#{escape(rooms_suffix(property))}
      </div>
      <div style="font-size:12px;text-transform:uppercase;letter-spacing:.04em;opacity:.6;margin-top:6px">
        #{escape(location(property))} · #{escape(property.source)} · #{escape(type_summary(property))}
      </div>
    </div>
    """
  end

  ## Formatting helpers

  defp criteria_summary(criteria) when is_map(criteria) and map_size(criteria) > 0 do
    parts =
      [
        region_label(criteria["voivodeship"]),
        criteria["city"],
        criteria["property_type"],
        criteria["transaction_type"],
        criteria["source"],
        criteria["search"] && "\"#{criteria["search"]}\"",
        range_label(criteria["min_price"], criteria["max_price"], "zł"),
        range_label(criteria["min_area"], criteria["max_area"], "m²"),
        criteria["rooms"] && "#{criteria["rooms"]} rooms"
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp criteria_summary(_), do: nil

  defp region_label(nil), do: nil

  defp region_label(value) do
    case Voivodeships.get(value) do
      nil -> value
      region -> region.label
    end
  end

  defp range_label(nil, nil, _unit), do: nil
  defp range_label(min, nil, unit), do: "from #{number(min)} #{unit}"
  defp range_label(nil, max, unit), do: "up to #{number(max)} #{unit}"
  defp range_label(min, max, unit), do: "#{number(min)}–#{number(max)} #{unit}"

  defp price(%{price: nil}), do: "Price not given"
  defp price(%{price: price} = property), do: "#{number(price)} #{property.currency || "PLN"}"

  defp price_per_sqm_suffix(property) do
    case price_per_sqm(property) do
      nil -> ""
      value -> " (#{number(value)} zł/m²)"
    end
  end

  defp price_per_sqm_html_suffix(property) do
    case price_per_sqm(property) do
      nil -> ""
      value -> " · #{number(value)} zł/m²"
    end
  end

  defp price_per_sqm(%{price: nil}), do: nil
  defp price_per_sqm(%{area_sqm: nil}), do: nil

  defp price_per_sqm(%{price: price, area_sqm: area}) do
    area_float = to_float(area)

    if area_float > 0 do
      Float.round(to_float(price) / area_float)
    else
      nil
    end
  end

  defp area(%{area_sqm: nil}), do: "Area not given"
  defp area(%{area_sqm: area}), do: "#{area_number(area)} m²"

  # Areas are small enough that rounding to a whole number loses real
  # information (58.5 m² is not 59 m²), so keep one decimal when there is one
  defp area_number(value) do
    rounded = value |> to_float() |> Float.round(1)
    whole = trunc(rounded)

    if rounded == whole * 1.0 do
      number(whole)
    else
      # Polish decimal comma, to match the thousands space above
      [int_part, decimal_part] = rounded |> :erlang.float_to_binary(decimals: 1) |> String.split(".")
      "#{number(int_part)},#{decimal_part}"
    end
  end

  defp rooms_suffix(%{rooms: nil}), do: ""
  defp rooms_suffix(%{rooms: rooms}), do: " · #{rooms} #{pluralize(rooms, "room", "rooms")}"

  defp location(property) do
    [property.city, property.district, property.street]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.uniq()
    |> case do
      [] -> "Location unknown"
      parts -> Enum.join(parts, ", ")
    end
  end

  defp type_summary(property) do
    [property.transaction_type, property.property_type]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "type unknown"
      parts -> Enum.join(parts, " / ")
    end
  end

  # 450000 -> "450 000" (thin spaces would not survive every client)
  defp number(value) do
    value
    |> to_float()
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _rest} -> float
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  # Scraped titles land in the HTML part - never interpolate them raw
  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp site_url do
    RzeczywiscieWeb.Endpoint.url()
  rescue
    _ -> "https://kruk.live"
  end
end
