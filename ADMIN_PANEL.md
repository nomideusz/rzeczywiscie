# Admin Panel Guide

The admin panel (`/admin`) provides tools for managing the real estate property database.

## Quick Stats Bar

The top stats bar shows:

- **Total** - All properties in database
- **Active** - Properties still available (seen within 48 hours)
- **Geocoded** - Properties with coordinates for map display
- **No Type** - Properties missing transaction or property type
- **Duplicates** - Properties with duplicate URLs (red if > 0)
- **Inactive** - Properties marked as no longer available

## Manual Scrapers

### OLX Scraper
- Scrapes listings from OLX.pl (Małopolskie region)
- Select 1-10 pages to scrape
- Default: 2 pages per run
- Delay: 2 seconds between requests

### Otodom Scraper
- Scrapes listings from Otodom.pl (Małopolskie region)
- Select 1-10 pages to scrape
- Default: 2 pages per run
- Delay: 3 seconds between requests

**Both scrapers:**
- Automatically extract property and transaction types
- Handle duplicates via upsert logic
- Update existing properties if found
- Show results: "Found X listings, saved Y"

## Maintenance Tasks

### 📍 Geocoding

**Purpose:** Add GPS coordinates to properties without location data

**How it works:**
- Processes up to 50 properties without coordinates
- Uses Google Geocoding API
- Converts city/address to lat/lng
- Enables properties to appear on map

**When to use:**
- After scraping new properties
- When "Geocoded" count is low
- Before using map features

**Limitations:**
- Requires Google Maps API key
- Rate limited to avoid API costs
- Processes in batches

### 🏷️ Backfill Types

**Purpose:** Infer missing property and transaction types

**How it works:**
- Finds properties without transaction_type or property_type
- Analyzes URLs, titles, and descriptions
- Uses pattern matching to detect:
  - **Transaction types:** sprzedaż (sale), wynajem (rent)
  - **Property types:** mieszkanie, dom, pokój, garaż, działka, lokal użytkowy
- Only updates missing fields (preserves existing data)

**Pattern Examples:**

Transaction type patterns:
- Sale: "sprzedaż", "sprzedam", "na-sprzedaz", "/sprzedaz/"
- Rent: "wynajem", "wynajmę", "do-wynajęcia", "najem"

Property type patterns:
- Apartment: "mieszkanie", "mieszkania", "M2", "M3"
- House: "dom", "domy", "domek"
- Room: "pokój", "pokoj", "stancja", "kawalerka"
- Commercial: "lokal", "biuro", "sklep", "magazyn"
- Garage: "garaż", "parking", "miejsce parkingowe"
- Plot: "działka", "grunt", "teren"

**When to use:**
- After scraping if types are missing
- When "No Type" count is high
- To improve filtering and search

**Results:**
- Shows "Updated X out of Y properties"
- Only counts properties where types were found
- Safe to run multiple times

### 🔄 Deduplication

**Purpose:** Remove duplicate properties with the same URL

**How it works:**
- Scans database for properties sharing the same URL
- Groups duplicates together
- Keeps the oldest entry (first inserted)
- Deletes newer duplicates
- Updates stats automatically

**When to use:**
- When "Duplicates" stat shows > 0
- After importing data from multiple sources
- Before running migrations that add unique constraints

**Safety:**
- Always preserves the oldest entry
- Removes only exact URL matches
- Shows count of removed duplicates
- Can be run repeatedly (idempotent)

**Example:**
```
Before: 3 properties with URL "https://olx.pl/abc123"
  - Property #100 (created 2025-11-01)
  - Property #250 (created 2025-11-15)
  - Property #380 (created 2025-11-28)

After: 1 property remains
  - Property #100 (created 2025-11-01) ✓ KEPT
  
Result: "Removed 2 duplicate properties"
```

### 🧹 Cleanup

**Purpose:** Mark old listings as inactive

**How it works:**
- Finds properties not seen in 48+ hours
- Marks them as `active = false`
- Hides from main listing view
- Preserves data for history

**When to use:**
- Daily or weekly
- After long periods without scraping
- To keep active listings accurate

**Why it matters:**
- Properties get removed from websites
- Inactive properties clutter results
- Stats become inaccurate
- Map shows sold/rented properties

## Quick Links

- **🔍 URL Inspector** - Test property URL parsing
- **📊 Phoenix Dashboard** - Monitor app performance
- **📧 Mailbox** - View sent emails (dev only)

## Best Practices

### Daily Routine
1. Run scrapers (OLX and/or Otodom)
2. Run Geocoding for new properties
3. Run Backfill Types for missing data
4. Run Cleanup to mark stale listings

### Weekly Routine
1. Check Duplicates count
2. Run Deduplication if needed
3. Review stats for anomalies

### After Database Changes
1. Run Deduplication before adding unique constraints
2. Run Backfill Types to populate new fields
3. Run Geocoding to populate coordinates

## Troubleshooting

### "Geocoding failed"
- Check Google Maps API key in environment
- Verify API is enabled in Google Cloud Console
- Check API quotas and billing

### "No properties updated" (Backfill)
- All properties already have types ✓
- Patterns don't match URLs/titles
- Properties are inactive (only updates active)

### "0 duplicates found" (Deduplication)
- Database is clean ✓
- Duplicates already removed
- No properties share URLs

### Scraper errors
- Website structure may have changed
- Network connectivity issues
- Rate limiting from source website
- Invalid selectors in scraper code

## API Keys Required

- **Google Maps API** - For geocoding and map display
  - Enable: Geocoding API
  - Enable: Maps JavaScript API
  - Enable: Air Quality API (for AQI data)

Set in environment:
```bash
GOOGLE_MAPS_API_KEY=your_key_here
```

## Performance Notes

- **Scrapers:** ~2-5 minutes per page depending on delay
- **Geocoding:** ~1-2 minutes for 50 properties
- **Backfill:** ~1-3 seconds per 100 properties
- **Deduplication:** <1 second for 1000 duplicates
- **Cleanup:** <1 second for 10,000 properties

All tasks run in background (async) so you can continue using the app.

