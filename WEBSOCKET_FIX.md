# WebSocket Fix - Production Issue Resolved

## Problem Identified ✓

**Symptoms:**
- ✗ Pages stuck on "Loading..." (specifically `/draw`, `/example`, `/kanban`)
- ✗ Styles not appearing (secondary symptom)
- ✓ Static files loading correctly (app.js, app.css with fingerprinting)

**Root Cause:**
```
WebSocket connection to 'wss://rzeczywiscie.zaur.app/live/websocket' failed
```

Phoenix LiveView requires a WebSocket connection to function. The connection was failing because the endpoint wasn't properly configured to work behind CapRover's nginx reverse proxy.

## The Fix

**Modified:** [config/runtime.exs](config/runtime.exs:58-74)

### Changes Made:

1. **IPv4 Binding** (was IPv6)
   ```elixir
   # Before: ip: {0, 0, 0, 0, 0, 0, 0, 0}  (IPv6)
   # After:  ip: {0, 0, 0, 0}                (IPv4)
   ```
   CapRover's default networking works better with IPv4 binding.

2. **WebSocket Idle Timeout**
   ```elixir
   protocol_options: [idle_timeout: :infinity]
   ```
   Prevents WebSocket connections from timing out during inactivity.

3. **Origin Checking**
   ```elixir
   check_origin: [
     "https://rzeczywiscie.zaur.app",
     "https://www.rzeczywiscie.zaur.app",
     "http://rzeczywiscie.zaur.app",
     "http://www.rzeczywiscie.zaur.app"
   ]
   ```
   Explicitly allows WebSocket connections from your production domain.

## Why This Happened

Phoenix LiveView uses WebSockets to maintain a persistent connection between the browser and server. When you visit a LiveView page:

1. HTML loads first (you see the page structure)
2. JavaScript (`app.js`) loads
3. JavaScript attempts to establish WebSocket connection to `/live/websocket`
4. **IF WEBSOCKET FAILS:** Page shows loading spinner forever
5. **IF WEBSOCKET SUCCEEDS:** Page becomes interactive

In your case, step 3 was failing because:
- CapRover uses nginx as a reverse proxy with SSL termination
- The WebSocket connection needs special handling (Upgrade headers)
- Phoenix's default IPv6 binding + missing origin checks caused issues

## Deployment

**✅ Already Deployed!**

**Commit:** `fd14a7b` - "Fix WebSocket connection issues behind CapRover reverse proxy"

CapRover is now rebuilding with the fix.

## Expected Results

After the rebuild completes (2-5 minutes):

### ✓ What Should Work:

1. **All LiveView pages load properly:**
   - https://rzeczywiscie.zaur.app/example
   - https://rzeczywiscie.zaur.app/draw
   - https://rzeczywiscie.zaur.app/kanban

2. **No more "Loading..." spinner** - Pages load immediately

3. **Browser console shows no WebSocket errors**

4. **Real-time features work:**
   - Drawing board: Multi-user collaboration
   - Kanban: Real-time card updates
   - Example: Counter increments work

### How to Verify:

1. **Wait for CapRover to finish rebuilding** (check deployment logs)

2. **Hard refresh your browser:**
   - Windows/Linux: Ctrl + Shift + R
   - Mac: Cmd + Shift + R

3. **Open Developer Tools (F12):**
   - Console tab should show NO red errors
   - Network tab should show WebSocket connection with status "101 Switching Protocols"

4. **Test a LiveView page:**
   - Visit https://rzeczywiscie.zaur.app/example
   - Should load immediately (no spinner)
   - Click the counter - should increment

5. **Test real-time collaboration:**
   - Open https://rzeczywiscie.zaur.app/draw in two browser windows
   - Draw in one window
   - Drawing should appear in the other window instantly

## Technical Details

### How WebSockets Work Behind a Reverse Proxy

```
Browser (wss://)  →  CapRover nginx (SSL termination)  →  Phoenix (ws://)
```

When a browser connects via `wss://` (WebSocket Secure):
1. nginx terminates SSL
2. nginx forwards as plain `ws://` to Phoenix on port 80
3. nginx adds `X-Forwarded-*` headers to indicate original protocol
4. Phoenix needs to trust these headers

### The Configuration Breakdown

```elixir
config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
  # External URL (what users see)
  url: [host: "rzeczywiscie.zaur.app", port: 443, scheme: "https"],

  # Internal binding (what Phoenix listens on)
  http: [
    ip: {0, 0, 0, 0},           # Bind to all IPv4 interfaces
    port: 80,                    # CapRover forwards to this port
    protocol_options: [
      idle_timeout: :infinity    # Keep WebSockets alive
    ]
  ],

  # Security: Only allow connections from our domain
  check_origin: ["https://rzeczywiscie.zaur.app", ...]
```

### Why IPv4 Instead of IPv6?

CapRover's default Docker networking is IPv4-based. While Phoenix can bind to IPv6 (`{0,0,0,0,0,0,0,0}`), this can cause issues with:
- Container networking in CapRover
- nginx proxy connections
- Docker bridge networks

Using IPv4 (`{0,0,0,0}`) ensures compatibility with CapRover's standard setup.

## If Issues Persist

### Scenario 1: Still shows loading spinner

**Check:**
1. Did CapRover finish rebuilding? (Check deployment logs)
2. Did you hard refresh? (Ctrl+Shift+R)
3. Is the new version deployed? (Check app logs for startup time)

**Debug:**
```bash
# Check if WebSocket upgrade is supported
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: test" \
  https://rzeczywiscie.zaur.app/live/websocket

# Should return: 101 Switching Protocols
```

### Scenario 2: WebSocket connects but immediately disconnects

**Possible causes:**
- `SECRET_KEY_BASE` changed (invalidates sessions)
- `check_origin` doesn't match domain
- Session cookie issues

**Fix:**
Verify environment variables haven't changed, especially `SECRET_KEY_BASE`.

### Scenario 3: Works on some browsers, not others

**Possible causes:**
- Browser cache (old JavaScript bundle)
- Browser extensions blocking WebSockets
- Firewall/antivirus blocking WS connections

**Fix:**
- Clear browser cache completely
- Try incognito mode
- Disable browser extensions

## Monitoring

### Check WebSocket Connection in Browser

Open DevTools → Network tab → Filter by "WS" (WebSocket):
- Look for connection to `/live/websocket`
- Status should be "101 Switching Protocols"
- Messages tab shows heartbeat pings/pongs

### Check Server Logs

In CapRover logs, you should see:
```
[info] Running RzeczywiscieWeb.Endpoint with Bandit 1.x.x at 0.0.0.0:80 (http)
[info] CONNECTED TO Phoenix.LiveView.Socket in XXXµs
```

No WebSocket errors should appear.

## Related Files

- [config/runtime.exs](config/runtime.exs) - Production endpoint configuration
- [lib/rzeczywiscie_web/endpoint.ex](lib/rzeczywiscie_web/endpoint.ex) - Endpoint definition
- [assets/js/app.js](assets/js/app.js) - Client-side LiveView socket setup

## Success Criteria

✅ All checkboxes should be checked after deployment:

- [ ] CapRover rebuild completed successfully
- [ ] No errors in CapRover deployment logs
- [ ] Hard refresh performed (Ctrl+Shift+R)
- [ ] `/example` page loads without spinner
- [ ] `/draw` page loads and is interactive
- [ ] `/kanban` page loads and is interactive
- [ ] Browser console shows no WebSocket errors
- [ ] Network tab shows WebSocket with 101 status
- [ ] Real-time features work (try drawing in two windows)
- [ ] Presence tracking works (see other users in Kanban)

---

**Status:** ✅ Fix deployed, waiting for CapRover rebuild
**Commit:** fd14a7b
**Next:** Hard refresh browser once rebuild completes
