# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :rzeczywiscie,
  ecto_repos: [Rzeczywiscie.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RzeczywiscieWeb.ErrorHTML, json: RzeczywiscieWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Rzeczywiscie.PubSub,
  live_view: [signing_salt: "GwXXI8+u"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :rzeczywiscie, Rzeczywiscie.Mailer, adapter: Swoosh.Adapters.Local

# Configure Oban
config :rzeczywiscie, Oban,
  repo: Rzeczywiscie.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # === SCRAPING (spread throughout day) ===
       # OLX: Regular scrape every 6 hours - fast listing scrape
       {"0 0,6,12,18 * * *", Rzeczywiscie.Workers.OlxScraperWorker, args: %{"pages" => 10, "delay" => 2500}},
       # OLX: Enrichment every 8 hours - fetches detail pages for missing data
       {"0 3,11,19 * * *", Rzeczywiscie.Workers.OlxScraperWorker, args: %{"pages" => 5, "delay" => 3000, "enrich" => true}},
       # Otodom: Scrape with enrichment every 6 hours (offset from OLX)
       {"0 1,7,13,21 * * *", Rzeczywiscie.Workers.OtodomScraperWorker, args: %{"pages" => 5, "delay" => 3000, "enrich" => true}},
       
       # === ENRICHMENT ===
       # Geocode properties every hour
       {"0 * * * *", Rzeczywiscie.Workers.GeocodingWorker},
       # Track price changes every 2 hours
       {"0 */2 * * *", Rzeczywiscie.Workers.PriceTrackerWorker},
       
       # === ANALYSIS (run after scraping completes) ===
       # LLM Analysis: every 6 hours (30 properties each run)
       # Runs at: 2:00, 8:00, 14:00, 20:00 (1h after scraping)
       {"0 2,8,14,20 * * *", Rzeczywiscie.Workers.LLMAnalysisWorker, args: %{"limit" => 30}},
       
       # === MAINTENANCE (daily, low-traffic hours) ===
       # Data maintenance: daily at 4 AM (fix duplicates, misclassified, backfill)
       {"0 4 * * *", Rzeczywiscie.Workers.DataMaintenanceWorker},
       # Mark stale properties inactive: daily at 5 AM
       {"0 5 * * *", Rzeczywiscie.Workers.CleanupWorker, args: %{"hours" => 96}}
     ]},
    # Lifeline plugin helps rescue long-running jobs from timeout
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ],
  queues: [scraper: 10, default: 5],
  # Increase shutdown timeout for long-running jobs
  shutdown_grace_period: :timer.minutes(10)

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  rzeczywiscie: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
