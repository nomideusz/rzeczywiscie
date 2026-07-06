# Admin Panel Guide

The admin panel (`/admin`) shows automation status and provides manual controls
for the real estate pipeline.

## Authentication

`/admin` and `/friends/admin` are protected by HTTP Basic Auth (any username,
password from the `ADMIN_PASSWORD` env var). In dev the password defaults to
`admin`. **In production the panel is inaccessible until `ADMIN_PASSWORD` is
set.** The auth flag is stored in the session and re-checked on the LiveView
websocket mount, so it can't be bypassed by connecting directly.

## Quick Stats Bar

- **Active Properties** — currently listed
- **OLX / Otodom** — split by source
- **Geocoded** — % of active properties with coordinates
- **LLM Analyzed** — properties with completed LLM analysis
- **Stale (4d+)** — active but not seen by scrapers in 96h
- **Duplicates** — distinct URLs appearing more than once (red if > 0)

## Automated Tasks

Everything runs on Oban cron; the cards show the schedule and (where
available) the last completed run from `oban_jobs`:

- Scraping: OLX + Otodom every 6h (OLX also enriched every 8h)
- Geocoding: hourly
- LLM analysis: every 6h, 30 properties per run
- Price tracking: every 2h
- Maintenance (dedup, fix types, backfills): daily 4 AM
- Stale cleanup (deactivate 4d+ unseen): daily 5 AM

## Manual Actions

Collapsed by default. Buttons queue/run the same code the cron jobs use:

- 🌐 Scrape OLX / Scrape Otodom (3 pages, enriched)
- 📍 Geocode (batch of 50)
- 🤖 LLM Analysis (30 properties)
- 🧹 Maintenance job
- 🗑️ Mark Stale (96h)
- 🧬 Remove Duplicates (keeps the oldest per URL)
- 🏷️ Fix Sale/Rent Types (price-based reclassification)
- 💸 Clear Bad Prices (< 100 PLN → null)
- 📊 Recompute Medians (zł/m² price positions)

## Property Management

Searchable, paginated table of **all** properties (including inactive):

- Search matches title and description
- Per-row: open source listing, Activate/Deactivate, Delete (with confirm)
- 20 rows per page

## Quick Links

Shortcuts to `/real-estate`, `/hot-deals`, `/llm-results`, `/stats`, and the
Phoenix LiveDashboard (`/dev/dashboard`, dev only).
