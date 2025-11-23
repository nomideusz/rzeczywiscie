# Kruk.live - Real Estate Aggregator

## Project Overview

**Kruk.live** is a real estate listing aggregator for the Małopolskie region of Poland, built with Phoenix 1.8.1 and LiveSvelte 0.16.0 (Svelte 5). It scrapes property listings from OLX and Otodom, stores them in PostgreSQL, and provides a modern web interface for browsing, filtering, and favoriting properties.

**Key Features:**
- 🏠 **Property Listings**: Browse thousands of real estate listings from multiple sources
- ⭐ **Favorites**: Save properties with persistent user sessions (browser fingerprint)
- 🗺️ **Map View**: Interactive map showing properties with coordinates
- 🔍 **Advanced Filters**: Filter by city, price, area, transaction type, property type, source
- 🌬️ **Air Quality Data**: Automatic AQI lookup for properties with coordinates
- 📊 **Statistics**: View aggregated data about listings
- 🔄 **Auto-scraping**: Scheduled scraping from OLX and Otodom

**Key Technologies:**
- Phoenix Framework 1.8.1
- Phoenix LiveView 1.1.0
- LiveSvelte 0.16.0 (Svelte 5)
- PostgreSQL database with performance indexes
- Bandit web server (modern HTTP/1.1 and HTTP/2)
- Custom esbuild configuration (dual build process)
- Tailwind CSS with DaisyUI
- NodeJS.Supervisor for SSR
- HTTPoison for web scraping
- Floki for HTML parsing

**Development Server:** http://localhost:4001

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
     <.svelte name="Example" props={%{number: @number}} socket={@socket} />
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

## Application Routes

The application has the following main routes:

- **`/`** - Home page with welcome message
- **`/real-estate`** - Main property listings page (table + map view)
- **`/favorites`** - User's favorited properties
- **`/stats`** - Statistics dashboard
- **`/admin`** - Admin panel
- **`/example`** - Demo Svelte component (counter example)

All routes use Phoenix LiveView for real-time updates without page refreshes.

## Database Schema

### Properties Table

Stores scraped real estate listings:

```elixir
create table(:properties) do
  add :title, :text, null: false
  add :description, :text
  add :price, :decimal, precision: 12, scale: 2
  add :area_sqm, :decimal, precision: 8, scale: 2
  add :rooms, :integer
  add :city, :string
  add :district, :string
  add :url, :text, null: false
  add :source, :string  # "olx", "otodom", "gratka"
  add :external_id, :string
  add :transaction_type, :string  # "sprzedaż", "wynajem"
  add :property_type, :string  # "mieszkanie", "dom", "pokój", etc.
  add :latitude, :decimal, precision: 10, scale: 8
  add :longitude, :decimal, precision: 11, scale: 8
  add :image_url, :text
  add :active, :boolean, default: true
  add :aqi, :integer
  add :aqi_category, :string
  add :dominant_pollutant, :string

  timestamps(type: :utc_datetime)
end

# Performance indexes
create index(:properties, [:transaction_type])
create index(:properties, [:property_type])
create index(:properties, [:active, :inserted_at])
create index(:properties, [:source])
create index(:properties, [:active, :latitude, :longitude])
create unique_index(:properties, [:source, :external_id])
```

### Favorites Table

Stores user favorites (user identified by browser fingerprint):

```elixir
create table(:favorites) do
  add :property_id, references(:properties, on_delete: :delete_all), null: false
  add :user_id, :string  # MD5 hash of user agent or IP
  add :notes, :text
  add :alert_on_price_drop, :boolean, default: true

  timestamps(type: :utc_datetime)
end

create index(:favorites, [:property_id])
create index(:favorites, [:user_id])
create unique_index(:favorites, [:property_id, :user_id])
```

## Web Scrapers

The application includes scrapers for OLX and Otodom that automatically extract property listings.

### Scraper Architecture

**Location**: `lib/rzeczywiscie/scrapers/`
- `olx_scraper.ex` - Scrapes OLX.pl property listings
- `otodom_scraper.ex` - Scrapes Otodom.pl property listings

### Running Scrapers

```elixir
# Manually run scrapers
iex> Rzeczywiscie.Scrapers.OlxScraper.scrape_properties()
iex> Rzeczywiscie.Scrapers.OtodomScraper.scrape_properties()

# Or via mix commands
mix run -e "Rzeczywiscie.Scrapers.OlxScraper.scrape_properties()"
mix run -e "Rzeczywiscie.Scrapers.OtodomScraper.scrape_properties()"
```

### Metadata Extraction

Both scrapers extract property metadata from multiple sources to maximize data quality:

**OLX Scraper**:
- Searches title + description + URL for keywords
- Extracts transaction_type ("sprzedaż", "wynajem")
- Extracts property_type ("mieszkanie", "dom", "pokój", etc.)
- Handles price formats with "zł", spaces, and decimal points
- Parses area from text patterns (e.g., "50 m²", "50m2")

**Otodom Scraper**:
- Parses JSON-LD structured data from listing pages
- Extracts property_type from title + URL using keyword matching
- Gets transaction_type from URL patterns
- Handles both old and new Otodom URL formats
- Extracts coordinates from geo data when available

### Data Quality

Properties with missing `transaction_type` or `property_type` are:
- Still stored in the database (not discarded)
- Shown in filtered results with visual indicators ("?" badge, "Unknown" text)
- Included when users filter by type (won't miss potential matches)

## Performance Optimizations

The application has been heavily optimized for performance:

### 1. N+1 Query Prevention
- **Batch favorite loading**: `get_favorited_property_ids/1` returns a MapSet for O(1) lookups
- **Preload associations**: All necessary data loaded in single queries
- **Result**: Reduced page load from 746ms → 150ms (80% improvement)

### 2. Lazy Loading Strategies
- **Lazy AQI**: AQI data only loaded for map view, not table view
- **Deferred map data**: Map properties only loaded when user clicks "Map" tab
- **Temporary assigns**: Properties cleared from memory after each render

### 3. Database Indexes
Multiple indexes for common query patterns:
- Single column: `transaction_type`, `property_type`, `source`
- Composite: `[active, inserted_at]`, `[active, latitude, longitude]`
- Unique: `[source, external_id]`

### 4. Client-Side Optimizations
- **Debounced filters**: 500ms delay prevents query spam while typing
- **Push events**: Favorite toggles use lightweight updates (no full reload)
- **Collapsible UI**: Filters collapse to save space, show active badges

### 5. Production Optimizations
- **Asset minification**: Production builds minify JS and CSS
- **Phoenix digest**: Fingerprinted assets for optimal caching
- **Gzip static files**: Can be enabled via `Plug.Static` with `gzip: true`

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

     def render(assigns) do
       ~H"""
       <.svelte name="MyComponent" props={%{name: @name}} socket={@socket} />
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
- `config/config.exs` - Tailwind config (esbuild removed)
- `config/dev.exs` - Development settings, port 4001, watchers
- `config/runtime.exs` - Production runtime configuration
- `lib/rzeczywiscie/application.ex` - NodeJS.Supervisor setup

### Assets
- `assets/build.js` - **Dual build configuration** (client + server)
- `assets/package.json` - Node dependencies
- `assets/js/app.js` - Client-side LiveView setup with LiveSvelte hooks
- `assets/js/server.js` - SSR render function
- `assets/svelte/` - **All Svelte components go here**
  - `PropertyView.svelte` - Main property listings container
  - `PropertyTable.svelte` - Table view with filters and pagination
  - `PropertyMap.svelte` - Interactive map view
  - `Example.svelte` - Demo counter component
- `assets/tailwind.config.js` - Tailwind + DaisyUI configuration

### LiveView Modules
- `lib/rzeczywiscie_web.ex` - Imports LiveSvelte in html_helpers
- `lib/rzeczywiscie_web/live/` - LiveView modules
  - `real_estate_live.ex` - Main property listings page
  - `favorites_live.ex` - User favorites page
  - `stats_live.ex` - Statistics dashboard
  - `admin_live.ex` - Admin panel
  - `example_live.ex` - Demo counter
- `lib/rzeczywiscie_web/router.ex` - Route definitions

### Business Logic
- `lib/rzeczywiscie/real_estate.ex` - Database context for properties and favorites
- `lib/rzeczywiscie/scrapers/` - Web scraper modules
  - `olx_scraper.ex` - OLX.pl scraper
  - `otodom_scraper.ex` - Otodom.pl scraper
- `lib/rzeczywiscie/schemas/` - Ecto schemas
  - `property.ex` - Property schema
  - `favorite.ex` - Favorite schema

### Database
- `priv/repo/migrations/` - Database migrations
  - `*_create_properties.exs` - Properties table
  - `*_create_favorites.exs` - Favorites table with indexes
  - `*_add_performance_indexes.exs` - Performance optimization indexes

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

### Port Already in Use

**Error**: `(Bandit.TransportError) listen: address already in use`

**Fix**:
```bash
# Find process on port 4001
netstat -ano | grep 4001

# Kill process (replace PID)
taskkill //PID <PID> //F
```

### NodeJS.Error - Cannot find module 'server'

**Cause**: Missing `assets/js/server.js` or server build failed

**Fix**:
1. Ensure `assets/js/server.js` exists with SSR render function
2. Check `priv/svelte/server.js` was generated
3. Rebuild: `cd assets && node build.js`

### Mix Command Not Found (Windows)

**Cause**: Elixir not in PATH

**Fix**:
```bash
export PATH="/c/ProgramData/chocolatey/lib/elixir/tools/bin:/c/ProgramData/chocolatey/bin:$PATH"
```

## Key Architectural Decisions

1. **Custom esbuild over Phoenix default**: Allows dual build process (client + server)
2. **Port 4001**: Avoids conflicts with other Phoenix apps on default 4000
3. **NodeJS.Supervisor pool_size: 4**: Balances SSR performance and resource usage
4. **Glob-based component discovery**: No manual imports needed for new components
5. **CSS injection**: Svelte styles injected into JS bundle for simplicity
6. **Bandit web server**: Modern HTTP server, default in Phoenix 1.8+

## Application Features

### Main Property Listings (`/real-estate`)

The core feature of the application:
- **Table View**: Sortable, filterable table of all properties
  - Sort by: source, title, city, price, area, AQI, date added
  - Filter by: city, price range, area range, source, transaction type, property type
  - Collapsible filters with active badges
  - Debounced auto-apply (500ms)
  - Pagination (50 properties per page)
- **Map View**: Interactive Leaflet map showing properties with coordinates
  - Deferred loading (only loads when user clicks "Map" tab)
  - Markers clustered by location
  - Popup shows property details
- **Favorites**: Heart icon to save/unsave properties
  - Instant UI updates via push events
  - Persistent across sessions (browser fingerprint)
- **Stats**: Live statistics showing total count, geocoded properties, AQI coverage
- **Geocoding**: Manual trigger to geocode up to 50 properties using Google API

### Favorites Page (`/favorites`)

- View all saved properties in a clean list
- Remove favorites with one click
- Shows property details: price, area, location, transaction type
- Persistent user identification via browser fingerprint (user agent → IP → random)

### Implementation Example

Want to see how LiveView + Svelte works? Check out the counter demo:
- URL: http://localhost:4001/example
- Svelte component: `assets/svelte/Example.svelte`
- LiveView: `lib/rzeczywiscie_web/live/example_live.ex`
- Demonstrates bidirectional communication between Svelte and LiveView

## Database Configuration

**Development**: PostgreSQL
- Username: `postgres`
- Password: `postgres`
- Host: `localhost`
- Database: `rzeczywiscie_dev`

Update in `config/dev.exs` if your local PostgreSQL has different credentials.

## User Identification Strategy

Since this is a public application without authentication, users are identified via browser fingerprinting:

**Priority Order**:
1. **User Agent Hash** (most persistent) - MD5 hash of browser user agent, 16 chars
2. **IP Address Hash** (fallback) - MD5 hash of peer IP address, 16 chars
3. **Random ID** (last resort) - Random 16-char hex, NOT persistent across sessions

**Implementation**:
```elixir
# In both real_estate_live.ex and favorites_live.ex
defp get_or_create_user_id(socket) do
  get_user_agent_id(socket) || get_peer_ip_id(socket) || get_fallback_id()
end
```

This allows favorites to persist across page refreshes for the same browser, while maintaining user privacy (no cookies, no tracking pixels).

## Filter UX Best Practices

The application implements smart filtering to maximize user value:

**Include Unknown Metadata**:
- When filtering by `transaction_type` or `property_type`, properties with `nil` values are INCLUDED
- Rationale: Scrapers may fail to extract metadata, but listings might still match user intent
- Visual indicators: "?" badge for unknown transaction type, "Unknown" text for property type
- Users won't miss potentially good listings due to incomplete scraping

**Backend Logic**:
```elixir
# In real_estate.ex filter_properties/1
{:property_type, type}, query ->
  where(query, [p], p.property_type == ^type or is_nil(p.property_type))
```

## Notes for Future Development

### Svelte + LiveView Patterns
- Always create Svelte components in `assets/svelte/` (they're auto-discovered)
- Use `export let live` in Svelte components to access LiveView socket
- Communication: `live.pushEvent()` (Svelte → LiveView), `handle_event/3` (LiveView → Svelte)
- Props from LiveView use the `props={%{...}}` attribute in `<.svelte>` helper
- The build process must complete successfully before starting the server
- Both client and server builds are required for proper SSR functionality

### Performance Considerations
- Use `temporary_assigns` for large data sets that don't need to persist
- Implement lazy loading for expensive operations (AQI lookups, geocoding)
- Batch database queries to avoid N+1 problems (use MapSet for O(1) lookups)
- Add database indexes for all filtered and sorted columns
- Use `push_event` for lightweight UI updates instead of full assigns
- Debounce user input to prevent query spam (500ms is a good default)

### Scraper Best Practices
- Extract metadata from multiple sources (title + description + URL)
- Handle various formats for price, area, and other numeric fields
- Store properties even with incomplete data (mark fields as nil)
- Use unique constraints on `[source, external_id]` to prevent duplicates
- Parse both HTML and JSON-LD for maximum data extraction
- Implement error handling for network failures and parsing errors
