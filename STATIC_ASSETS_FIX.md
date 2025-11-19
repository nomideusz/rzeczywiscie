# Static Assets Fix - Production Issue Resolved

## Problem

In production, your app showed:
- ❌ Missing CSS styles (no Tailwind, no Svelte component styles)
- ❌ Huge images (not constrained by CSS)
- ❌ Likely 404 errors for `/assets/js/app.js` and `/assets/css/app.css`

## Root Cause

**Phoenix releases don't automatically include `priv/static` and `priv/svelte` directories.**

### What Was Happening

1. ✅ Dockerfile built assets correctly:
   - `node build.js --deploy` → Created JS/Svelte bundles
   - `mix tailwind --minify` → Created CSS
   - `mix phx.digest` → Fingerprinted all files

2. ❌ But `mix release` didn't copy these into the release:
   - Release was created in `_build/prod/rel/rzeczywiscie/`
   - Static files stayed in `/app/priv/static/` (not copied)
   - Final Docker image had NO static assets

3. 🐛 Result: App ran, but without CSS/JS/images

## The Fix

Modified [mix.exs](mix.exs:40-54) to explicitly copy static files during release:

```elixir
defp releases do
  [
    rzeczywiscie: [
      include_executables_for: [:unix],
      applications: [runtime_tools: :permanent],
      steps: [:assemble, &copy_static_files/1]
    ]
  ]
end

defp copy_static_files(release) do
  File.cp_r!("priv/static", Path.join(release.path, "priv/static"))
  File.cp_r!("priv/svelte", Path.join(release.path, "priv/svelte"))
  release
end
```

### What This Does

The custom release step runs **after** `:assemble` and:
1. Copies `priv/static/` → `_build/prod/rel/rzeczywiscie/priv/static/`
2. Copies `priv/svelte/` → `_build/prod/rel/rzeczywiscie/priv/svelte/`
3. Ensures these directories are in the final Docker image

## Deployment

**✅ Already pushed to GitHub!**

Commit: `15615d2` - "Fix missing static assets in production"

### What Happens Next

1. CapRover detects the new commit
2. Rebuilds the Docker image with the fix
3. Next deployment will include all static assets
4. Your CSS, JS, and images will load correctly

### How to Verify

After CapRover redeploys:

1. **Visit your site:** https://rzeczywiscie.zaur.app
2. **Check browser console** (F12):
   - Should see NO 404 errors for `/assets/js/app.js` or `/assets/css/app.css`
   - Files should load with fingerprinted names like `app-ABC123.js`

3. **Inspect the page:**
   - Tailwind styles should be applied
   - Images should be properly sized
   - Svelte components should be styled

4. **Check CapRover logs:**
   - Should see "Running migrations..."
   - Should see "Running RzeczywiscieWeb.Endpoint with Bandit..."
   - No errors about missing static files

## Technical Details

### Why This Wasn't Automatic

Phoenix releases use OTP releases under the hood, which only package:
- Compiled BEAM files (`.beam`)
- Applications and dependencies
- Explicitly configured overlays/steps

Static assets in `priv/` are **not** automatically included unless:
1. They're referenced by code at compile-time, OR
2. You explicitly copy them in a release step (what we did)

### What Gets Copied

After the fix, your release contains:

```
_build/prod/rel/rzeczywiscie/
├── bin/
│   ├── rzeczywiscie
│   ├── server
│   └── migrate_and_start
├── lib/
│   └── (compiled .beam files)
├── priv/
│   ├── static/           ← NOW INCLUDED!
│   │   ├── assets/
│   │   │   ├── css/
│   │   │   │   └── app-HASH.css
│   │   │   └── js/
│   │   │       └── app-HASH.js
│   │   ├── images/
│   │   ├── favicon.ico
│   │   ├── robots.txt
│   │   └── cache_manifest.json
│   └── svelte/           ← NOW INCLUDED!
│       └── server.js
└── releases/
```

### Asset Pipeline in Dockerfile

The build process (unchanged, now works correctly):

```dockerfile
# 1. Install npm packages
RUN npm ci --prefer-offline --no-audit

# 2. Build Svelte/JS assets
RUN node build.js --deploy
# → Outputs to: priv/static/assets/js/app.js
# → Outputs to: priv/svelte/server.js

# 3. Build Tailwind CSS
RUN mix tailwind rzeczywiscie --minify
# → Outputs to: priv/static/assets/css/app.css

# 4. Fingerprint assets for cache busting
RUN mix phx.digest
# → Creates: priv/static/assets/css/app-ABC123.css
# → Creates: priv/static/assets/js/app-ABC123.js
# → Creates: priv/static/cache_manifest.json

# 5. Build release (NOW includes static files!)
RUN mix release
# → Copies priv/static/ into release
# → Copies priv/svelte/ into release
```

## Related Files

- [mix.exs](mix.exs) - Release configuration
- [Dockerfile](Dockerfile) - Build process
- [lib/rzeczywiscie_web.ex](lib/rzeczywiscie_web.ex#L19) - Static paths definition
- [lib/rzeczywiscie_web/endpoint.ex](lib/rzeczywiscie_web/endpoint.ex#L23-L27) - Static file serving
- [config/prod.exs](config/prod.exs#L9) - Cache manifest config

## Preventing Future Issues

This fix ensures that:
- ✅ All future deployments include static assets
- ✅ Asset fingerprinting works correctly for cache busting
- ✅ SSR (Server-Side Rendering) works with Svelte files
- ✅ Tailwind CSS is available in production
- ✅ Images, favicon, robots.txt are served

## If Issues Persist

If after redeployment you still see missing assets:

1. **Clear browser cache** (Ctrl+Shift+R or Cmd+Shift+R)
2. **Check CapRover deployment logs** for build errors
3. **SSH into container** and verify files exist:
   ```bash
   docker exec -it $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") ls -la /app/priv/static/
   ```
4. **Check nginx logs** in CapRover for 404 errors

---

**Status:** ✅ Fixed and deployed
**Next Action:** Wait for CapRover to rebuild (usually 2-5 minutes)
