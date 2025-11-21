# Real Estate Scraper - Debugging Guide

## Current Issue

The scraper is successfully connecting to OLX but finding **0 properties** on each page. This typically means:

1. **OLX changed their HTML structure** (most likely) - websites frequently update their DOM
2. **Bot detection** - OLX may be serving different content to scrapers
3. **Region-specific rendering** - The page might use JavaScript to load content

## Enhanced Debugging Features

I've added extensive debugging to help identify the issue:

### Debug Logging

The scraper now logs:
- HTML response size
- Each selector attempt and result
- Available `data-cy` attributes when nothing is found
- Warning if response seems too short (possible blocking)
- Saved HTML files for manual inspection

### Testing the Scraper

#### Option 1: Trigger from UI
1. Visit `http://localhost:4001/real-estate`
2. Click "Manual Scrape" button
3. Watch the server logs for debug output

#### Option 2: Trigger from IEx Console
```elixir
# Start IEx with your app
iex -S mix phx.server

# Trigger a scrape
Rzeczywiscie.Workers.OlxScraperWorker.trigger(pages: 1)

# Or test the scraper directly
Rzeczywiscie.Scrapers.OlxScraper.scrape(pages: 1)
```

### What to Look For in Logs

**Successful scraping should show:**
```
[info] Found 40 cards using selector: [data-cy='l-card']
[info] Scraped page 1: found 40 properties
```

**Current issue shows:**
```
[debug] Selector '[data-cy='l-card']' found 0 cards
[debug] Selector 'div[data-cy='l-card']' found 0 cards
...
[warn] No listings found! Available data-cy values: [...]
[info] Scraped page 1: found 0 properties
```

**If blocked, you'll see:**
```
[warn] Response seems short (15000 bytes) - might be blocked
[warn] Possible bot detection - page contains captcha/robot keywords
```

### Inspecting Saved HTML

When the response seems suspicious, HTML is saved to `/tmp/olx_debug_*.html`:

```bash
# List debug files
ls -lah /tmp/olx_debug_*.html

# View the latest one
cat /tmp/olx_debug_*.html | head -100

# Or open in browser
xdg-open /tmp/olx_debug_*.html  # Linux
open /tmp/olx_debug_*.html      # Mac
```

Look for:
- CAPTCHA pages
- JavaScript-heavy pages (content loads client-side)
- Error messages
- Actual listing cards (to identify correct selectors)

## Solutions

### Solution 1: Update Selectors (If OLX Changed)

If the debug logs show different `data-cy` values:

1. Check the saved HTML or visit OLX in a browser
2. Inspect a property card element
3. Update selectors in `lib/rzeczywiscie/scrapers/olx_scraper.ex`:

```elixir
defp try_find_listings(document) do
  selectors = [
    "[data-cy='NEW-SELECTOR-HERE']",  # ← Update this
    # ... keep fallbacks
  ]
end
```

### Solution 2: Use Browser Automation (If Bot Blocked)

If OLX is blocking requests, consider using:

**Wallaby/Hound (Headless Browser):**
```elixir
# Add to mix.exs
{:wallaby, "~> 0.30"}

# Use real browser to fetch pages
# Slower but bypasses bot detection
```

**Splash/Browserless:**
```elixir
# External headless browser service
# Renders JavaScript, appears as real browser
```

### Solution 3: Use OLX API (If Available)

Check if OLX has an official API:
- More reliable
- No HTML parsing needed
- Terms of service compliant
- May require API key/authentication

### Solution 4: Alternative Real Estate Sites

Polish real estate sites with potentially easier scraping:

1. **Otodom** - Major competitor to OLX
2. **Gratka** - Another popular option
3. **Morizon** - Real estate portal
4. **Domiporta** - Property listings

The scraper architecture supports multiple sources - just add new scrapers following the OLX pattern.

## Manual Debugging Session

To deeply investigate what's happening:

```elixir
# In IEx
alias Rzeczywiscie.Scrapers.Debug

# Fetch and inspect OLX page structure
Debug.fetch_and_inspect_olx()

# This will:
# 1. Fetch the page
# 2. Try multiple selectors
# 3. Show available data-cy attributes
# 4. Save HTML to /tmp/olx_debug.html
```

## Code Structure

Key files:
- `lib/rzeczywiscie/scrapers/olx_scraper.ex` - Main scraper logic
- `lib/rzeczywiscie/scrapers/debug.ex` - Debug helper
- `lib/rzeczywiscie/workers/olx_scraper_worker.ex` - Oban background job
- `lib/rzeczywiscie/real_estate.ex` - Database operations

## Next Steps

1. **Trigger a scrape** and check the logs
2. **Review the debug output** to see which selectors were tried
3. **Inspect saved HTML** if response seems short
4. **Update selectors** based on findings OR
5. **Switch to browser automation** if bot detection is the issue

## Contact/Support

If you find the correct selectors or have questions:
- Check the logs first - they're very detailed now
- Inspect the saved HTML files
- The scraper tries 7 different selector strategies automatically
- Consider alternative sites if OLX proves too difficult

---

**Note:** Web scraping should always:
- Respect `robots.txt`
- Include delays between requests (currently 2 seconds)
- Use appropriate User-Agent headers
- Comply with Terms of Service
- Consider using official APIs when available
