# Database Migration Guide

## ✅ What I've Set Up For You

I've configured your app to **automatically run migrations** on every deployment:

1. **Created** [lib/rzeczywiscie/release.ex](lib/rzeczywiscie/release.ex) - Migration runner for production
2. **Updated** [Dockerfile](Dockerfile) - Runs migrations before starting the server

## How It Works

Every time you deploy to CapRover:
1. Container starts
2. Migrations run automatically
3. Server starts

You'll see this in the CapRover logs:
```
Running migrations...
Starting server...
```

## Next Steps

### 1. Deploy the Changes

Push these changes to trigger a new build:

```bash
git add .
git commit -m "Add automatic database migrations"
git push origin master
```

CapRover will automatically rebuild and deploy.

### 2. Watch the Logs

In CapRover dashboard:
- Go to your app
- Click "App Logs"
- Look for "Running migrations..." message

### 3. Verify Migrations Ran

You can manually check if migrations ran by SSH'ing into the container:

```bash
# SSH into CapRover, then run:
docker exec -it $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie remote

# In the Elixir console:
Ecto.Migrator.run(Rzeczywiscie.Repo, :up, all: true)
```

## Manual Migration (If Needed)

If you need to run migrations manually without redeploying:

### Option 1: Using the Release Module

```bash
# SSH into CapRover server
ssh your-caprover-server

# Run migrations
docker exec $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie eval "Rzeczywiscie.Release.migrate()"
```

### Option 2: Using Elixir Console

```bash
# SSH into CapRover server
ssh your-caprover-server

# Access Elixir console
docker exec -it $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie remote

# Run migrations manually
Rzeczywiscie.Release.migrate()
```

## Creating New Migrations

When you need to add database tables/fields:

```bash
# Locally, create a migration
mix ecto.gen.migration create_users

# Edit the migration file in priv/repo/migrations/
# Then commit and push - it will run automatically on deploy!
```

## Current Status

Currently, you have:
- ✅ Release module created
- ✅ Dockerfile configured for auto-migrations
- ℹ️ No migrations yet (database is empty)

The next time you create a migration and deploy, it will run automatically!

## Troubleshooting

### "Database does not exist" Error

Create the database first:

```bash
docker exec $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie eval "Rzeczywiscie.Repo.__adapter__().storage_up(Rzeczywiscie.Repo.config())"
```

### Migrations Fail

Check the logs for the specific error. Common issues:
- `DATABASE_URL` not set correctly
- Database doesn't exist
- Network connectivity to database

### Rollback a Migration

```bash
docker exec $(docker ps --filter name=srv-captain--rzeczywiscie --format "{{.ID}}") /app/bin/rzeczywiscie eval "Rzeczywiscie.Release.rollback(Rzeczywiscie.Repo, VERSION)"
```

Replace `VERSION` with the migration version number (the timestamp prefix).

## Database Connection String

Based on your DATABASE_URL, the format should be:

```
postgresql://postgres:PASSWORD@srv-captain--db-rzeczywiscie/rzeczywiscie
```

Replace `PASSWORD` with your actual PostgreSQL password from CapRover.

## Example: Creating Your First Migration

Let's say you want to create a users table:

```bash
# 1. Create migration locally
mix ecto.gen.migration create_users

# 2. Edit the generated file in priv/repo/migrations/
defmodule Rzeczywiscie.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end

# 3. Test locally
mix ecto.migrate

# 4. Commit and push
git add priv/repo/migrations/
git commit -m "Add users table migration"
git push

# 5. Migration runs automatically on CapRover!
```

---

**You're all set!** The next deployment will automatically handle migrations. 🚀
