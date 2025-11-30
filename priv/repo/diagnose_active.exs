# Diagnose why active count is dropping
# Run with: mix run priv/repo/diagnose_active.exs

alias Rzeczywiscie.Repo
alias Rzeczywiscie.RealEstate.Property
import Ecto.Query

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("📊 ACTIVE PROPERTIES DIAGNOSIS")
IO.puts(String.duplicate("=", 60))

# Total counts
total = Repo.aggregate(Property, :count, :id)
active = Repo.aggregate(from(p in Property, where: p.active == true), :count, :id)
inactive = total - active

IO.puts("\n📈 TOTALS")
IO.puts("   Total: #{total}")
IO.puts("   Active: #{active} (#{Float.round(active / total * 100, 1)}%)")
IO.puts("   Inactive: #{inactive} (#{Float.round(inactive / total * 100, 1)}%)")

# When were inactive properties last seen?
IO.puts("\n⏰ INACTIVE PROPERTIES - LAST SEEN")

inactive_by_age = from(p in Property,
  where: p.active == false and not is_nil(p.last_seen_at),
  select: %{last_seen: p.last_seen_at}
)
|> Repo.all()

if length(inactive_by_age) > 0 do
  now = DateTime.utc_now()
  
  age_buckets = inactive_by_age
  |> Enum.map(fn %{last_seen: ls} -> 
    diff_hours = DateTime.diff(now, ls, :hour)
    cond do
      diff_hours < 24 -> "< 24h ago"
      diff_hours < 48 -> "24-48h ago"
      diff_hours < 72 -> "48-72h ago"
      diff_hours < 168 -> "3-7 days ago"
      diff_hours < 336 -> "1-2 weeks ago"
      true -> "> 2 weeks ago"
    end
  end)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {bucket, _} -> 
    case bucket do
      "< 24h ago" -> 1
      "24-48h ago" -> 2
      "48-72h ago" -> 3
      "3-7 days ago" -> 4
      "1-2 weeks ago" -> 5
      _ -> 6
    end
  end)
  
  for {bucket, count} <- age_buckets do
    IO.puts("   #{bucket}: #{count}")
  end
else
  IO.puts("   No last_seen data for inactive properties")
end

# When were active properties last seen?
IO.puts("\n✅ ACTIVE PROPERTIES - LAST SEEN")

active_by_age = from(p in Property,
  where: p.active == true and not is_nil(p.last_seen_at),
  select: %{last_seen: p.last_seen_at}
)
|> Repo.all()

if length(active_by_age) > 0 do
  now = DateTime.utc_now()
  
  age_buckets = active_by_age
  |> Enum.map(fn %{last_seen: ls} -> 
    diff_hours = DateTime.diff(now, ls, :hour)
    cond do
      diff_hours < 1 -> "< 1h ago"
      diff_hours < 6 -> "1-6h ago"
      diff_hours < 12 -> "6-12h ago"
      diff_hours < 24 -> "12-24h ago"
      diff_hours < 48 -> "24-48h ago"
      true -> "> 48h ago (STALE!)"
    end
  end)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {bucket, _} -> 
    case bucket do
      "< 1h ago" -> 1
      "1-6h ago" -> 2
      "6-12h ago" -> 3
      "12-24h ago" -> 4
      "24-48h ago" -> 5
      _ -> 6
    end
  end)
  
  for {bucket, count} <- age_buckets do
    indicator = if String.contains?(bucket, "STALE"), do: " ⚠️", else: ""
    IO.puts("   #{bucket}: #{count}#{indicator}")
  end
else
  IO.puts("   No last_seen data")
end

# Source breakdown
IO.puts("\n🌐 SOURCE BREAKDOWN (Active only)")

sources = from(p in Property,
  where: p.active == true,
  group_by: p.source,
  select: {p.source, count(p.id)}
)
|> Repo.all()

for {source, count} <- sources do
  IO.puts("   #{source || "unknown"}: #{count}")
end

# Recent scraper activity
IO.puts("\n🔄 RECENT SCRAPER ACTIVITY")

# Properties inserted in last 24h
recent_inserts = Repo.aggregate(
  from(p in Property, where: p.inserted_at > ago(24, "hour")),
  :count, :id
)

# Properties updated (last_seen_at) in last 24h
recent_updates = Repo.aggregate(
  from(p in Property, where: p.last_seen_at > ago(24, "hour")),
  :count, :id
)

IO.puts("   New properties (24h): #{recent_inserts}")
IO.puts("   Properties refreshed (24h): #{recent_updates}")

# Check if scrapers are running on schedule
IO.puts("\n⚙️ SCRAPER SCHEDULE CHECK")

# Get most recent property per source
latest_olx = from(p in Property, 
  where: p.source == "olx",
  order_by: [desc: p.last_seen_at],
  limit: 1,
  select: p.last_seen_at
) |> Repo.one()

latest_otodom = from(p in Property, 
  where: p.source == "otodom",
  order_by: [desc: p.last_seen_at],
  limit: 1,
  select: p.last_seen_at
) |> Repo.one()

if latest_olx do
  hours_ago = DateTime.diff(DateTime.utc_now(), latest_olx, :hour)
  status = if hours_ago > 6, do: "⚠️ NOT RECENT", else: "✅"
  IO.puts("   OLX last activity: #{hours_ago}h ago #{status}")
end

if latest_otodom do
  hours_ago = DateTime.diff(DateTime.utc_now(), latest_otodom, :hour)
  status = if hours_ago > 6, do: "⚠️ NOT RECENT", else: "✅"
  IO.puts("   Otodom last activity: #{hours_ago}h ago #{status}")
end

# Recommendation
IO.puts("\n💡 RECOMMENDATIONS")
IO.puts("   - Scrapers should run every 4-6 hours to keep properties fresh")
IO.puts("   - Currently stale cutoff is 48 hours (configurable)")
IO.puts("   - Properties get reactivated when seen again by scrapers")

IO.puts("\n" <> String.duplicate("=", 60) <> "\n")

