# CapRover Environment Variables Setup Guide

## Step 1: Generate SECRET_KEY_BASE

Run this command **locally** in your project directory:

```bash
mix phx.gen.secret
```

This will output a long random string (64 characters). **Copy this value** - you'll need it in Step 3.

Example output:
```
vqB7zBqLn8F9xK3pW2mR5tY7uI9oP0aS4dG6hJ8kL1mN3vC5xZ2wQ4eR6tY8uI0o
```

## Step 2: Access CapRover Dashboard

1. Log in to your CapRover dashboard
2. Navigate to **"Apps"** in the left sidebar
3. Click on your **`rzeczywiscie`** app
4. Click the **"App Configs"** tab

## Step 3: Configure Environment Variables

Scroll down to the **"Environmental Variables"** section and add these variables:

### Required Variables

Add each variable by clicking **"+ Add Environmental Variable"**:

| Key | Value | Notes |
|-----|-------|-------|
| `PHX_SERVER` | `true` | Enables the Phoenix web server |
| `SECRET_KEY_BASE` | `<paste your generated secret>` | Paste the output from Step 1 |
| `DATABASE_URL` | `postgresql://postgres:PASSWORD@srv-captain--db-rzeczywiscie/rzeczywiscie` | See Database Setup below |
| `PHX_HOST` | `rzeczywiscie.zaur.app` | Your domain name |
| `PORT` | `80` | Internal container port |

### Optional Variables (recommended defaults)

| Key | Value | Notes |
|-----|-------|-------|
| `POOL_SIZE` | `10` | Database connection pool size |
| `MIX_ENV` | `prod` | Production environment |

## Step 4: Database Setup

### Option A: Using CapRover PostgreSQL One-Click App

If you haven't set up a database yet:

1. Go to **"One-Click Apps/Databases"** in CapRover
2. Search for **"PostgreSQL"**
3. Install it with the name: `db-rzeczywiscie`
4. After installation, note the password generated
5. Set `DATABASE_URL` as:
   ```
   postgresql://postgres:YOUR_PASSWORD@srv-captain--db-rzeczywiscie/rzeczywiscie
   ```

### Option B: External PostgreSQL Database

If using an external database (like ElephantSQL, Supabase, etc.):

1. Get the connection URL from your database provider
2. Set `DATABASE_URL` to that full URL
3. Format: `postgresql://username:password@host:port/database_name`

## Step 5: Run Database Migration

After setting environment variables, you need to run migrations:

### SSH into CapRover Container

```bash
# SSH into your CapRover server first, then:
docker exec -it $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie remote

# In the Elixir console, run:
Rzeczywiscie.Release.migrate()
```

### Alternative: Add Migration to Startup

Create a release module to run migrations automatically. See Step 6.

## Step 6: (Optional) Auto-Run Migrations on Deploy

Create a release module for automatic migrations:

1. Create `lib/rzeczywiscie/release.ex`:

```elixir
defmodule Rzeczywiscie.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :rzeczywiscie

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

2. Update your `Dockerfile` to run migrations on startup (add before `CMD`):

```dockerfile
# Add this line before the CMD instruction
RUN echo '#!/bin/sh\n/app/bin/rzeczywiscie eval "Rzeczywiscie.Release.migrate()"\nexec /app/bin/rzeczywiscie start' > /app/bin/server && chmod +x /app/bin/server
```

## Step 7: Restart the Application

After setting all environment variables:

1. Scroll to the top of the App Configs page
2. Click **"Save & Update"**
3. CapRover will restart your app with the new environment variables

## Step 8: Verify the Setup

1. Visit your app: https://rzeczywiscie.zaur.app
2. Check the logs in CapRover:
   - Go to your app
   - Click **"App Logs"**
   - Look for successful startup messages
   - Should see: `Running RzeczywiscieWeb.Endpoint with Bandit...`

### Troubleshooting

**If you see database errors:**
- Verify `DATABASE_URL` is correct
- Check that the database exists
- Run migrations (see Step 5)

**If the app doesn't start:**
- Check App Logs for error messages
- Verify `SECRET_KEY_BASE` is set and is long enough (64+ characters)
- Ensure `PHX_SERVER=true` is set

**If you see "address already in use":**
- Change `PORT` to a different value (try 8080)

## Current Environment Variables Checklist

Mark these off as you set them:

- [ ] `PHX_SERVER=true`
- [ ] `SECRET_KEY_BASE=<generated value>`
- [ ] `DATABASE_URL=<your database url>`
- [ ] `PHX_HOST=rzeczywiscie.zaur.app`
- [ ] `PORT=80`
- [ ] Database created
- [ ] Migrations run
- [ ] App restarted
- [ ] App loads successfully

## Quick Reference: CapRover Commands

```bash
# View app logs
# (In CapRover dashboard: Apps > rzeczywiscie > App Logs)

# Access app console (Elixir shell)
docker exec -it $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie remote

# Check environment variables inside container
docker exec $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") env | grep PHX
```

## Security Notes

⚠️ **Important Security Tips:**

1. **Never commit** `SECRET_KEY_BASE` to version control
2. **Keep** `DATABASE_URL` credentials private
3. **Rotate** `SECRET_KEY_BASE` if ever exposed (will invalidate all sessions)
4. Consider enabling **HTTPS only** by adding to `config/runtime.exs`:
   ```elixir
   config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
     force_ssl: [hsts: true]
   ```

## Next Steps After Setup

Once your app is running with environment variables:

1. Set up regular database backups in CapRover
2. Configure monitoring/alerts
3. Add a favicon to eliminate 404 errors
4. Consider setting up log aggregation
5. Configure nginx rate limiting for security

---

**Need Help?**
- CapRover Docs: https://caprover.com/docs/
- Phoenix Deployment Guide: https://hexdocs.pm/phoenix/deployment.html
- This project's README: [CLAUDE.md](CLAUDE.md)
