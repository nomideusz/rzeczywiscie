# Rzeka - Phoenix + LiveSvelte Project

## Project Overview

**Live at:** https://rzeka.live

This is a Phoenix 1.8.1 application integrating LiveSvelte 0.16.0 with Svelte 5, featuring both client-side and server-side rendering (SSR) of Svelte components within Phoenix LiveView.

**Key Technologies:**
- Phoenix Framework 1.8.1
- Phoenix LiveView 1.1.0
- LiveSvelte 0.16.0 (Svelte 5)
- PostgreSQL database
- Oban 2.17 (background job processing)
- Bandit web server
- Custom esbuild configuration (dual build process)
- Tailwind CSS with DaisyUI
- NodeJS.Supervisor for SSR
- Google Maps JavaScript API (with Air Quality heatmap tiles)
- Google Geocoding API
- Google Air Quality API

**Development Server:** http://localhost:4001

## Applications

Rzeka consists of 4 main collaborative apps:

1. **Draw** - Real-time collaborative drawing board
2. **Kanban** - Task management with drag-and-drop
3. **World** - Live world map with user tracking
4. **Properties** - Real estate scraper for Małopolskie region with:
   - Properties listings (table and map views)
   - Favorites (session-based)
   - Stats (monitoring dashboard)
   - Admin (manual scraper triggers)

## Architecture

### Dual Build Process

This project uses a **custom esbuild setup** (not Phoenix's default esbuild) configured in `assets/build.js`:

1. **Client Build**: Compiles Svelte components for browser
   - Entry: `assets/js/app.js`
   - Output: `priv/static/assets/js/app.js`
   - Compiler: `{generate: "client", css: "injected"}`

2. **Server Build**: Compiles Svelte components for SSR
   - Entry: `assets/js/server.js`
   - Output: `priv/svelte/server.js`
   - Compiler: `{generate: "server"}`
   - Platform: `node`

**CRITICAL**: Both builds must output to their specific directories:
- Client: `../priv/static/assets/js` (HTML expects `/assets/js/app.js`)
- Server: `../priv/svelte` (NodeJS.Supervisor loads from here)

### Component Discovery

The `esbuild-plugin-import-glob` plugin enables automatic component discovery:

```javascript
// In both app.js and server.js
import * as Components from "../svelte/**/*.svelte"
```

This glob pattern automatically imports all `.svelte` files from the `assets/svelte/` directory.

### LiveView Integration

LiveSvelte connects Svelte components to Phoenix LiveView:

1. **Client-side** (`assets/js/app.js`):
   ```javascript
   import {getHooks} from "live_svelte"
   import * as Components from "../svelte/**/*.svelte"

   const Hooks = {...getHooks(Components)}
   let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, ...})
   ```

2. **Server-side** (`assets/js/server.js`):
   ```javascript
   import {getRender} from "live_svelte"
   export const render = getRender(Components)
   ```

3. **LiveView render** (e.g., `lib/rzeczywiscie_web/live/example_live.ex`):
   ```elixir
   def render(assigns) do
     ~H"""
     <.app flash={@flash}>
       <.svelte name="Example" props={%{number: @number}} socket={@socket} />
     </.app>
     """
   end
   ```

### SSR Setup

The application supervisor starts NodeJS.Supervisor for server-side rendering:

```elixir
# lib/rzeczywiscie/application.ex
children = [
  {NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]},
  # ... other children
]
```

## Real Estate Scraper

### Overview

The Properties app scrapes real estate listings from OLX and Otodom for the Małopolskie region, featuring:
- Automated scraping via Oban background jobs
- Google Maps integration with Air Quality heatmaps (US_AQI)
- Price history tracking with change detection
- Session-based favorites (no authentication required)
- Real-time updates via Phoenix PubSub
- Comprehensive monitoring dashboard

### Routes

- `/real-estate` - Main listings (table and map views)
- `/favorites` - Saved properties
- `/stats` - Monitoring dashboard
- `/admin` - Manual scraper triggers and backfill tasks

All property pages have sub-navigation tabs for easy switching.

### Scrapers

**OLX Scraper** (`lib/rzeczywiscie/scrapers/olx_scraper.ex`)
- Scrapes: https://www.olx.pl/nieruchomosci/malopolskie/
- Extracts: title, price, area, rooms, location, images, URLs
- Runs: Every 30 minutes (:00, :30)
- Worker: `Rzeczywiscie.Workers.OlxScraperWorker`

**Otodom Scraper** (`lib/rzeczywiscie/scrapers/otodom_scraper.ex`)
- Scrapes: https://www.otodom.pl/pl/wyniki/...
- Extracts: same as OLX
- Runs: Every 30 minutes (:15, :45)
- Worker: `Rzeczywiscie.Workers.OtodomScraperWorker`

### Background Jobs (Oban)

```elixir
# config/config.exs
crontab: [
  {"*/30 * * * *", OlxScraperWorker},       # Every 30 min
  {"15,45 * * * *", OtodomScraperWorker},   # Every 30 min (offset)
  {"0 */2 * * *", PriceTrackerWorker},      # Every 2 hours
  {"0 * * * *", GeocodingWorker},           # Every hour
  {"0 3 * * *", CleanupWorker}              # Daily 3 AM
]
```

### Database Schema

**Properties** (`properties` table):
- Core fields: title, description, price, currency, area_sqm, rooms, floor
- Types: transaction_type (sprzedaż/wynajem), property_type (mieszkanie/dom/etc)
- Location: city, district, street, postal_code, voivodeship
- Geocoding: latitude, longitude
- Metadata: source (olx/otodom), external_id, url, image_url, active, last_seen_at

**Price History** (`price_history` table):
- Tracks price changes over time
- Fields: property_id, price, price_per_sqm, currency, change_percentage, detected_at
- Automatically records changes when price updates detected

**Favorites** (`favorites` table):
- Session-based (no authentication)
- Fields: property_id, user_id (session/socket ID), notes, alert_on_price_drop

**Air Quality Cache** (`air_quality_cache` table):
- Caches Google Air Quality API responses
- Fields: lat, lng, aqi, category, dominant_pollutant, pollutant values
- TTL: 1 hour

### Google APIs Integration

**Maps JavaScript API**:
- Used in PropertyMap component
- Displays properties as markers
- Air Quality heatmap tiles (US_AQI)
- Configured via `GOOGLE_MAPS_API_KEY` env var

**Geocoding API**:
- Converts addresses to coordinates
- Runs hourly via GeocodingWorker
- Batch size: 50 properties at a time
- Delay: 500ms between requests

**Air Quality API**:
- Fetches current conditions for property locations
- Cached for 1 hour per location
- Returns: AQI value, category, dominant pollutant

### Features

**Price Tracking**:
- Automatically detects price changes
- Calculates percentage change
- Tracks price per m² (if area available)
- Displays recent drops in Stats dashboard

**Favorites**:
- Click heart icon (❤️/🤍) to save properties
- No login required (uses session ID)
- View all saved properties at `/favorites`
- Remove favorites individually

**Monitoring Dashboard** (`/stats`):
- Total properties and active count
- Geocoding coverage percentage
- Air Quality data coverage
- Properties added today
- Source breakdown (OLX vs Otodom)
- Transaction type distribution
- Property type distribution
- Top 10 cities
- Data quality metrics
- Recent price drops
- Recent activity (last 7 days)

**Admin Panel** (`/admin`):
- Manual OLX scraper trigger
- Manual Otodom scraper trigger
- Backfill task (classify existing properties)

## Common Commands

### Development

```bash
# Start Phoenix server (includes asset watchers)
mix phx.server

# The server runs watchers for:
# - node build.js --watch (Svelte compilation)
# - tailwind --watch (CSS compilation)
# - Phoenix live reload
```

### Database

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Reset database
mix ecto.reset

# Database console
psql -U postgres -d rzeczywiscie_dev
```

**Production (Caprover):**
Migrations run automatically on deploy via Dockerfile:
```bash
/app/bin/rzeczywiscie eval "Rzeczywiscie.Release.migrate()"
```

### Assets

```bash
# Install dependencies
cd assets && npm install

# Build assets once (both client and server)
cd assets && node build.js

# Build for production
cd assets && node build.js --deploy

# Watch mode (auto-rebuild on changes)
cd assets && node build.js --watch
```

### Mix Tasks

```bash
# Setup project from scratch
mix setup  # Runs: deps.get, ecto.setup, npm install

# Build assets (from root)
mix assets.build  # Runs: tailwind + node build.js

# Deploy assets
mix assets.deploy  # Runs: tailwind --minify + node build.js --deploy + phx.digest

# Run backfill task
mix backfill.property_types
```

## Creating New Features

### Adding a Svelte Component

1. Create component in `assets/svelte/`:
   ```svelte
   <!-- assets/svelte/MyComponent.svelte -->
   <script>
       export let name = "World"
       export let live  // LiveView socket

       function handleClick() {
           live.pushEvent("my_event", {data: "value"}, () => {})
       }
   </script>

   <div>
       <h1>Hello {name}!</h1>
       <button on:click={handleClick}>Click me</button>
   </div>
   ```

2. Create LiveView in `lib/rzeczywiscie_web/live/`:
   ```elixir
   defmodule RzeczywiscieWeb.MyComponentLive do
     use RzeczywiscieWeb, :live_view
     import RzeczywiscieWeb.Layouts

     def render(assigns) do
       ~H"""
       <.app flash={@flash}>
         <.svelte name="MyComponent" props={%{name: @name}} socket={@socket} />
       </.app>
       """
     end

     def handle_event("my_event", %{"data" => data}, socket) do
       # Handle event
       {:noreply, socket}
     end

     def mount(_params, _session, socket) do
       {:ok, assign(socket, :name, "Phoenix")}
     end
   end
   ```

3. Add route in `lib/rzeczywiscie_web/router.ex`:
   ```elixir
   scope "/", RzeczywiscieWeb do
     pipe_through :browser
     live "/my-component", MyComponentLive
   end
   ```

4. Component is automatically discovered and bundled (no imports needed!)

### Using Tailwind CSS

Tailwind is configured to scan Svelte files:

```javascript
// assets/tailwind.config.js
content: [
  "./js/**/*.js",
  "../lib/rzeczywiscie_web/**/*.*ex",
  "./svelte/**/*.svelte"  // Svelte support
]
```

Just use Tailwind classes in your Svelte components and they'll be included.

## Important File Paths

### Configuration
- `mix.exs` - Dependencies and aliases
- `config/config.exs` - Oban cron schedule, Tailwind config
- `config/dev.exs` - Development settings, port 4001, watchers
- `config/runtime.exs` - Environment variables (Google API keys)
- `lib/rzeczywiscie/application.ex` - NodeJS.Supervisor and Oban setup

### Assets
- `assets/build.js` - **Dual build configuration** (client + server)
- `assets/package.json` - Node dependencies
- `assets/js/app.js` - Client-side LiveView setup with LiveSvelte hooks
- `assets/js/server.js` - SSR render function
- `assets/svelte/` - **All Svelte components go here**
- `assets/tailwind.config.js` - Tailwind + DaisyUI configuration

### LiveView
- `lib/rzeczywiscie_web.ex` - Imports LiveSvelte in html_helpers
- `lib/rzeczywiscie_web/live/` - LiveView modules
- `lib/rzeczywiscie_web/router.ex` - Route definitions
- `lib/rzeczywiscie_web/components/layouts.ex` - Header, footer, navigation

### Real Estate Scraper
- `lib/rzeczywiscie/scrapers/olx_scraper.ex` - OLX scraper
- `lib/rzeczywiscie/scrapers/otodom_scraper.ex` - Otodom scraper
- `lib/rzeczywiscie/workers/` - Oban background workers
- `lib/rzeczywiscie/real_estate.ex` - Context module
- `lib/rzeczywiscie/real_estate/property.ex` - Property schema
- `lib/rzeczywiscie/real_estate/price_history.ex` - Price history schema
- `lib/rzeczywiscie/real_estate/favorite.ex` - Favorites schema
- `lib/rzeczywiscie/services/geocoding.ex` - Google Geocoding integration
- `lib/rzeczywiscie/services/air_quality.ex` - Google Air Quality integration

### Build Output (DO NOT EDIT)
- `priv/static/assets/js/` - Client-side compiled JS
- `priv/svelte/` - Server-side compiled JS

## Troubleshooting

### Empty Page / JavaScript Not Loading

**Symptom**: Page loads but appears empty, browser console shows 404 for `/assets/js/app.js`

**Cause**: Build output directory misconfigured in `assets/build.js`

**Fix**: Ensure `optsClient.outdir` is `"../priv/static/assets/js"` (not `"../priv/static/assets"`)

```javascript
// Correct:
outdir: "../priv/static/assets/js"

// Incorrect (produces /assets/app.js instead of /assets/js/app.js):
outdir: "../priv/static/assets"
```

Then rebuild: `cd assets && node build.js`

### Numeric Field Overflow

**Error**: `numeric field overflow - A field with precision 8, scale 2 must round to...`

**Cause**: Property area or price exceeds database column precision

**Fix**: Migrations added to increase precision:
- `area_sqm`: precision 10, scale 2 (up to 99,999,999.99 m²)
- `price`: precision 12, scale 2 (up to 9,999,999,999.99 PLN)

Run migrations: `mix ecto.migrate` or deploy (auto-runs)

### Wrong Area Values (e.g., 202574.80 m² instead of 75 m²)

**Cause**: Area extraction regex matching wrong numbers in card text

**Fix**: Updated `extract_area/1` in OLX scraper with:
- Better regex for Polish number formatting
- Validation: area must be 0.1 - 100,000 m²
- Cleanup migration to NULL invalid data

### Port Already in Use

**Error**: `(Bandit.TransportError) listen: address already in use`

**Fix**:
```bash
# Find process on port 4001
lsof -i :4001  # macOS/Linux
netstat -ano | grep 4001  # Windows

# Kill process (replace PID)
kill -9 <PID>  # macOS/Linux
taskkill //PID <PID> //F  # Windows
```

### NodeJS.Error - Cannot find module 'server'

**Cause**: Missing `assets/js/server.js` or server build failed

**Fix**:
1. Ensure `assets/js/server.js` exists with SSR render function
2. Check `priv/svelte/server.js` was generated
3. Rebuild: `cd assets && node build.js`

### Scraper Finds 0 Properties

**Cause**: OLX/Otodom changed their HTML structure or blocking requests

**Debug**:
1. Check logs for selector debugging output
2. HTML saved to `/tmp/olx_debug_*.html` for inspection
3. Try different user-agent strings
4. Check for captcha/bot detection keywords in response

### Favorites Not Persisting

**Cause**: Database migrations not run

**Fix**:
```bash
# Local development
mix ecto.migrate

# Production (Caprover)
# Migrations run automatically on deploy via Dockerfile
```

## Key Architectural Decisions

1. **Custom esbuild over Phoenix default**: Allows dual build process (client + server)
2. **Port 4001**: Avoids conflicts with other Phoenix apps on default 4000
3. **NodeJS.Supervisor pool_size: 4**: Balances SSR performance and resource usage
4. **Glob-based component discovery**: No manual imports needed for new components
5. **CSS injection**: Svelte styles injected into JS bundle for simplicity
6. **Bandit web server**: Modern HTTP server, default in Phoenix 1.8+
7. **Oban for background jobs**: Reliable job processing with cron scheduling
8. **Session-based favorites**: No authentication complexity, uses session/socket ID
9. **Air Quality caching**: 1-hour TTL to minimize API calls
10. **Automatic migrations**: Dockerfile runs migrations on every deploy

## Database Configuration

**Development**: PostgreSQL
- Username: `postgres`
- Password: `postgres`
- Host: `localhost`
- Database: `rzeczywiscie_dev`

Update in `config/dev.exs` if your local PostgreSQL has different credentials.

**Production**: Configured via `DATABASE_URL` environment variable in Caprover

## Environment Variables

Required for production:

```bash
# Google APIs (get from Google Cloud Console)
GOOGLE_MAPS_API_KEY=your_api_key_here
GOOGLE_GEOCODING_API_KEY=your_api_key_here
GOOGLE_AIR_QUALITY_API_KEY=your_api_key_here

# Database
DATABASE_URL=ecto://user:pass@host/database

# Phoenix
SECRET_KEY_BASE=generate_with_mix_phx.gen.secret
PHX_HOST=rzeka.live
```

## Notes for Future Development

- Always create Svelte components in `assets/svelte/` (they're auto-discovered)
- Use `export let live` in Svelte components to access LiveView socket
- Communication: `live.pushEvent()` (Svelte → LiveView), `handle_event/3` (LiveView → Svelte)
- Props from LiveView use the `props={%{...}}` attribute in `<.svelte>` helper
- The build process must complete successfully before starting the server
- Both client and server builds are required for proper SSR functionality
- Always wrap LiveView renders with `<.app flash={@flash}>` and `import RzeczywiscieWeb.Layouts`
- Use Phoenix PubSub for real-time updates across LiveView processes
- Background jobs should be idempotent (safe to run multiple times)
- Respect scraping delays to avoid being blocked (2-3 seconds between requests)
