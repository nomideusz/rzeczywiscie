# Production Troubleshooting Guide

## Current Issues

1. ✗ Styles not loading
2. ✗ Pages `/draw` and `/example` loading forever (stuck on loading spinner)

## Diagnostic Steps

### 1. Check Browser Console

Open your browser's developer tools (F12) and check:

**Console Tab:**
Look for JavaScript errors, especially:
- 404 errors for `/assets/js/app.js` or `/assets/css/app.css`
- WebSocket connection errors
- "Failed to fetch" or CORS errors

**Network Tab:**
- Check if `app.js` and `app.css` are loading (200 status)
- Look for failed requests (404, 500 errors)
- Check the actual file names being requested (might be fingerprinted like `app-ABC123.js`)

### 2. Check CapRover Logs

In CapRover dashboard:
1. Go to Apps → rzeczywiscie → App Logs
2. Look for errors like:
   - `Could not find static manifest`
   - `File not found`
   - `NodeJS.Error` (SSR issues)
   - Any Elixir crash dumps

### 3. Verify Files Exist in Container

SSH into your CapRover server and run:

```bash
# Get container ID
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}")

# Check if static files exist
docker exec $CONTAINER ls -la /app/priv/static/

# Check for CSS files
docker exec $CONTAINER ls -la /app/priv/static/assets/css/

# Check for JS files
docker exec $CONTAINER ls -la /app/priv/static/assets/js/

# Check for cache manifest
docker exec $CONTAINER cat /app/priv/static/cache_manifest.json

# Check for SSR files
docker exec $CONTAINER ls -la /app/priv/svelte/
```

### 4. Test Asset URLs Directly

Try accessing these URLs directly in your browser:
- https://rzeczywiscie.zaur.app/assets/css/app.css
- https://rzeczywiscie.zaur.app/assets/js/app.js
- https://rzeczywiscie.zaur.app/favicon.ico

If these return 404, the static files aren't being served.

## Common Causes & Fixes

### Issue: 404 on all static files

**Cause:** Static files not copied to release or nginx misconfigured

**Fix:**
1. Check that build completed successfully (no errors in CapRover deployment logs)
2. Verify `copy_static_files/1` function ran during release
3. Check nginx configuration in CapRover

### Issue: LiveView stuck on "Loading..."

**Cause:** JavaScript bundle not loading or erroring

**Symptoms:**
- Page shows loading spinner forever
- No console errors (means JS didn't load at all)
- OR console shows WebSocket connection errors

**Fix:**
1. Ensure `app.js` loads successfully (check Network tab)
2. Check for JavaScript errors in console
3. Verify environment variables are set (especially `PHX_HOST`)

### Issue: "Could not find static manifest"

**Cause:** `cache_manifest.json` not created or not accessible

**Fix:**
Ensure these steps happen in order in Dockerfile:
1. Build assets
2. Run `mix phx.digest` (creates cache_manifest.json)
3. Run `mix release`
4. Copy priv/static (includes cache_manifest.json)

### Issue: SSR Errors (NodeJS.Error)

**Cause:** Svelte SSR files not available

**Symptoms:**
- Errors in logs mentioning NodeJS
- "Cannot find module 'server'" errors

**Fix:**
1. Verify `priv/svelte/server.js` exists in container
2. Check that Node.js is installed in runner image
3. Ensure `copy_static_files/1` copies priv/svelte

## Environment Variables Checklist

Make sure these are set in CapRover:

```bash
PHX_SERVER=true
SECRET_KEY_BASE=<your secret>
DATABASE_URL=postgresql://...
PHX_HOST=rzeczywiscie.zaur.app  # ← Important for WebSocket!
PORT=80
```

## Quick Test Script

Run this on your CapRover server:

```bash
#!/bin/bash
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}")

echo "=== Container Info ==="
docker ps --filter name=srv-captain--rzeczywiscie

echo -e "\n=== Static Files ==="
docker exec $CONTAINER ls -la /app/priv/static/ 2>/dev/null || echo "priv/static not found!"

echo -e "\n=== CSS Files ==="
docker exec $CONTAINER ls -la /app/priv/static/assets/css/ 2>/dev/null || echo "CSS directory not found!"

echo -e "\n=== JS Files ==="
docker exec $CONTAINER ls -la /app/priv/static/assets/js/ 2>/dev/null || echo "JS directory not found!"

echo -e "\n=== Cache Manifest ==="
docker exec $CONTAINER cat /app/priv/static/cache_manifest.json 2>/dev/null || echo "cache_manifest.json not found!"

echo -e "\n=== SSR Files ==="
docker exec $CONTAINER ls -la /app/priv/svelte/ 2>/dev/null || echo "priv/svelte not found!"

echo -e "\n=== Environment Variables ==="
docker exec $CONTAINER env | grep -E "PHX|DATABASE|SECRET|PORT" | sort

echo -e "\n=== Recent Logs ==="
docker logs --tail 50 $CONTAINER
```

## Next Steps Based on Findings

### If static files don't exist in container:
→ The `copy_static_files/1` function isn't working
→ Check mix.exs and rebuild

### If static files exist but return 404:
→ CapRover nginx not configured correctly
→ Check CapRover's nginx configuration
→ Ensure static file serving is enabled

### If JavaScript loads but LiveView won't connect:
→ WebSocket connection issue
→ Check `PHX_HOST` environment variable
→ Check for CORS or SSL issues
→ Verify Bandit is listening correctly

### If you see NodeJS errors:
→ SSR configuration problem
→ Check that NodeJS.Supervisor is starting
→ Verify priv/svelte/server.js exists

## Contact Information

When reporting issues, please provide:
1. Screenshot of browser console (F12)
2. Output of the test script above
3. Last 50 lines of CapRover deployment logs
4. Last 50 lines of app runtime logs

---

**Current Status:** Investigating production deployment issues
**Last Deploy:** Check CapRover for timestamp
**Version:** Check git commit hash in CapRover
