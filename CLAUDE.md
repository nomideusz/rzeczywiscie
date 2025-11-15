# Rzeczywiscie - Phoenix + LiveSvelte Project

## Project Overview

This is a Phoenix 1.8.1 application integrating LiveSvelte 0.16.0 with Svelte 5, featuring both client-side and server-side rendering (SSR) of Svelte components within Phoenix LiveView.

**Key Technologies:**
- Phoenix Framework 1.8.1
- Phoenix LiveView 1.1.0
- LiveSvelte 0.16.0 (Svelte 5)
- PostgreSQL database
- Bandit web server
- Custom esbuild configuration (dual build process)
- Tailwind CSS with DaisyUI
- NodeJS.Supervisor for SSR

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
- `lib/rzeczywiscie/application.ex` - NodeJS.Supervisor setup

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

## Example: Current Working Feature

Visit http://localhost:4001/example to see the counter component:
- Svelte component: `assets/svelte/Example.svelte`
- LiveView: `lib/rzeczywiscie_web/live/example_live.ex`
- Demonstrates bidirectional communication between Svelte and LiveView
- Styled with Tailwind CSS

## Database Configuration

**Development**: PostgreSQL
- Username: `postgres`
- Password: `postgres`
- Host: `localhost`
- Database: `rzeczywiscie_dev`

Update in `config/dev.exs` if your local PostgreSQL has different credentials.

## Notes for Future Development

- Always create Svelte components in `assets/svelte/` (they're auto-discovered)
- Use `export let live` in Svelte components to access LiveView socket
- Communication: `live.pushEvent()` (Svelte → LiveView), `handle_event/3` (LiveView → Svelte)
- Props from LiveView use the `props={%{...}}` attribute in `<.svelte>` helper
- The build process must complete successfully before starting the server
- Both client and server builds are required for proper SSR functionality
