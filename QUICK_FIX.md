# Quick Production Fix

## Most Likely Issue

Based on your symptoms (styles not loading, pages stuck on "Loading..."), the problem is most likely that **static assets aren't being served** or **JavaScript isn't loading**.

## Immediate Diagnostic

Run these commands on your CapRover server (SSH in first):

```bash
# 1. Check if container is running
docker ps | grep rzeczywiscie

# 2. Get container ID
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}")

# 3. Check if static files exist in container
echo "=== Checking static files ==="
docker exec $CONTAINER ls -la /app/priv/static/assets/

# 4. Check cache manifest
echo "=== Checking cache manifest ==="
docker exec $CONTAINER cat /app/priv/static/cache_manifest.json 2>&1

# 5. Check app logs for errors
echo "=== Recent app logs ==="
docker logs --tail 100 $CONTAINER
```

## What to Look For

### If `priv/static/assets/` is EMPTY or doesn't exist:
→ **The build isn't copying files correctly**
→ Go to "Fix A" below

### If `priv/static/assets/` exists and has files:
→ **Files exist but aren't being served**
→ Go to "Fix B" below

### If you see errors in logs:
→ **Application error preventing startup**
→ Go to "Fix C" below

---

## Fix A: Static Files Not Copied

The `copy_static_files` function might be running before `phx.digest` finishes.

**Issue:** In the current Dockerfile, we run:
1. `mix phx.digest` - creates fingerprinted files
2. `mix release` - runs `:assemble` then `copy_static_files`

But `phx.digest` might be creating files that need to be there BEFORE the copy happens.

**Solution:** Modify the Dockerfile to ensure files are copied at the right time.

Try this updated Dockerfile section:

```dockerfile
# After running phx.digest, explicitly list what gets created
RUN mix phx.digest && \
    echo "=== Digested files ===" && \
    find priv/static -type f -name "*.css" -o -name "*.js" | head -20 && \
    echo "=== Cache manifest ===" && \
    cat priv/static/cache_manifest.json

# Build the release
RUN mix release && \
    echo "=== Checking release static files ===" && \
    find _build/prod/rel/rzeczywiscie/priv/static -type f | head -20
```

This adds debugging output so we can see what's happening.

---

## Fix B: Files Exist But Not Served

If files exist in the container but return 404, the issue is with how CapRover/nginx serves them.

**Possible causes:**
1. CapRover's nginx is not configured to proxy static files correctly
2. Phoenix isn't serving the files (config issue)
3. Environment variables are missing

**Check environment variables:**
```bash
docker exec $CONTAINER env | grep PHX
```

You MUST have:
- `PHX_SERVER=true`
- `PHX_HOST=rzeczywiscie.zaur.app`

If missing, add them in CapRover:
1. Apps → rzeczywiscie → App Configs
2. Environmental Variables
3. Add the missing variables
4. Save & Update

---

## Fix C: Application Errors

Common errors and fixes:

### Error: "Could not find static manifest"
**Cause:** `cache_manifest.json` not found

**Fix:** Ensure `mix phx.digest` runs successfully:
```dockerfile
# In Dockerfile, add verbose output
RUN mix phx.digest || (echo "Digest failed!" && exit 1)
```

### Error: "Database connection failed"
**Cause:** `DATABASE_URL` not set or incorrect

**Fix:** Set in CapRover environment variables

### Error: "NodeJS.Error" or "Cannot find module 'server'"
**Cause:** SSR files not copied

**Fix:** Ensure `copy_static_files` copies `priv/svelte/`:
```elixir
File.cp_r!("priv/svelte", Path.join(priv_path, "svelte"))
```

---

## Nuclear Option: Test Without CapRover Nginx

To rule out nginx issues, test the app directly:

```bash
# Get the container's internal IP
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}")
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER)

# Test direct access
curl -I http://$IP/assets/css/app.css
curl -I http://$IP/assets/js/app.js
```

If these return 200, the app is working but CapRover nginx is the problem.
If these return 404, the app itself isn't serving files.

---

## Recommended First Action

**Run this single command on CapRover server:**

```bash
CONTAINER=$(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") && \
echo "=== Container: $CONTAINER ===" && \
echo "=== Static directory ===" && \
docker exec $CONTAINER ls -la /app/priv/static/ && \
echo "=== Assets ===" && \
docker exec $CONTAINER ls -la /app/priv/static/assets/ && \
echo "=== CSS ===" && \
docker exec $CONTAINER ls -la /app/priv/static/assets/css/ 2>&1 && \
echo "=== JS ===" && \
docker exec $CONTAINER ls -la /app/priv/static/assets/js/ 2>&1 && \
echo "=== Cache Manifest ===" && \
docker exec $CONTAINER test -f /app/priv/static/cache_manifest.json && echo "EXISTS" || echo "MISSING" && \
echo "=== Recent Logs ===" && \
docker logs --tail 30 $CONTAINER
```

**Copy the output and let me know what you see!**

---

## Most Common Solution

Based on similar issues, the most likely fix is ensuring the release includes the digested files properly. The current `copy_static_files` function copies `priv/static` which should work, but there might be a timing issue.

Try adding explicit logging to see what's being copied:

```elixir
defp copy_static_files(release) do
  priv_path = Path.join(release.path, "priv")
  File.mkdir_p!(priv_path)

  IO.puts("=== Copying static files ===")
  IO.puts("Source: priv/static")
  IO.puts("Destination: #{Path.join(priv_path, "static")}")

  # List what we're about to copy
  IO.puts("Files in priv/static:")
  IO.inspect(File.ls!("priv/static"))

  File.cp_r!("priv/static", Path.join(priv_path, "static"))
  File.cp_r!("priv/svelte", Path.join(priv_path, "svelte"))

  IO.puts("=== Copy complete ===")
  release
end
```

This will show in the build logs what's being copied.
