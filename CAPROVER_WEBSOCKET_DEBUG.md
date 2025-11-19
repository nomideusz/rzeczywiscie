# CapRover WebSocket Debugging Guide

## Current Issue

WebSocket connections are failing with:
```
WebSocket connection to 'wss://rzeczywiscie.zaur.app/live/websocket' failed
```

## What I've Already Fixed

✅ IPv4 binding (CapRover compatibility)
✅ check_origin configuration (allows your domain)
✅ X-Forwarded headers support (proxy compatibility)
✅ WebSocket timeout increased

## Next: Check Server Logs

**MOST IMPORTANT:** We need to see what error Phoenix is throwing when the WebSocket tries to connect.

### How to Check:

1. Go to CapRover dashboard
2. Navigate to: **Apps → rzeczywiscie → App Logs**
3. Keep this window open (live logs)
4. In another tab, visit: https://rzeczywiscie.zaur.app/example
5. Watch the logs for errors

### What to Look For:

#### Scenario A: Origin Check Failure
If you see:
```
[error] Could not check origin for Phoenix.Socket transport
[error] Origin of the request: https://rzeczywiscie.zaur.app
```

**This means:** check_origin is too strict

**Fix:** We may need to disable it temporarily or adjust it

#### Scenario B: Connection Refused
If you see:
```
[error] Ranch listener ... terminated
[error] ** (exit) ...
```

**This means:** The connection isn't reaching Phoenix

**Fix:** CapRover nginx configuration issue

#### Scenario C: No Logs at All
If you see no logs when visiting the page:

**This means:** The request isn't reaching the Phoenix app

**Fix:** CapRover routing or nginx issue

#### Scenario D: 403 Forbidden
If you see:
```
[info] GET /live/websocket
[info] Sent 403 in X ms
```

**This means:** check_origin is blocking the connection

**Fix:** Adjust check_origin configuration

## Temporary Test: Disable Origin Checking

If logs show origin-related errors, we can temporarily disable check_origin to test:

```elixir
# In config/runtime.exs, change:
check_origin: [
  "https://#{host}",
  ...
]

# To:
check_origin: false  # TEMPORARY - for testing only!
```

⚠️ **WARNING:** Only use `check_origin: false` for testing! It's a security risk in production.

## CapRover Nginx Configuration

CapRover should automatically configure nginx for WebSocket proxying, but we can verify:

### Check CapRover Nginx Config

SSH into CapRover and check:

```bash
# Find your app's nginx config
cat /etc/nginx/conf.d/captain-root.conf | grep -A 20 rzeczywiscie

# Look for these important headers:
# - Upgrade $http_upgrade
# - Connection "upgrade"
# - X-Forwarded-* headers
```

### Expected Nginx Config

For WebSockets to work, nginx should have:

```nginx
location / {
    proxy_pass http://rzeczywiscie_container:80;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    # Proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Alternative Test: Direct Container Access

Test if Phoenix works without nginx:

```bash
# SSH into CapRover server
ssh your-server

# Get container IP
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}")
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER)

# Test WebSocket upgrade (from inside the server)
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Host: rzeczywiscie.zaur.app" \
  http://$IP:80/live/websocket
```

**Expected response:**
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
```

**If you get 403 or 400:** Origin checking issue
**If you get 404:** Routing issue
**If you get connection refused:** App not listening

## Quick Fix Attempts

### Attempt 1: Simplify check_origin

```elixir
# config/runtime.exs
check_origin: ["//#{host}"]  # Protocol-agnostic
```

### Attempt 2: Use wildcard subdomain

```elixir
# config/runtime.exs
check_origin: ["//*.zaur.app"]
```

### Attempt 3: Disable (TEMPORARY TEST ONLY)

```elixir
# config/runtime.exs
check_origin: false
```

## Common CapRover Issues

### Issue 1: App not using HTTPS internally

CapRover terminates SSL at nginx. Phoenix should listen on plain HTTP (port 80), not HTTPS.

**Verify:**
```elixir
# config/runtime.exs should have:
http: [
  ip: {0, 0, 0, 0},
  port: 80  # Not 443!
],
url: [scheme: "https", port: 443]  # External URL, not internal
```

### Issue 2: CapRover force HTTPS redirect

If CapRover has "Force HTTPS" enabled, it might interfere.

**Check:** In CapRover app settings, see if "Enforce HTTPS" is enabled

### Issue 3: Container networking

Make sure the container is on CapRover's network and can be reached by nginx.

```bash
docker network inspect captain-overlay-network
# Should show your container
```

## Environment Variables Double-Check

In CapRover, verify these are EXACTLY:

```
PHX_HOST=rzeczywiscie.zaur.app
PORT=80
PHX_SERVER=true
```

NOT:
```
PHX_HOST=https://rzeczywiscie.zaur.app  # ❌ No protocol!
PORT=443  # ❌ Should be 80!
```

## Next Steps

1. **Check the logs** (most important!)
2. Copy any errors you see here
3. Based on the logs, we'll apply the specific fix

The logs will tell us exactly what's wrong!

---

**Status:** Waiting for log output to diagnose further
**Latest commit:** 40174c5 - "Add WebSocket proxy headers support to endpoint"
