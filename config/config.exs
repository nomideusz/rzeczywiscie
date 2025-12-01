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
       # Scrape OLX every 4 hours with 10 pages (regular fast scrape)
       # Runs at: 0:00, 4:00, 8:00, 12:00, 16:00, 20:00
       {"0 */4 * * *", Rzeczywiscie.Workers.OlxScraperWorker, args: %{"pages" => 10, "delay" => 2500}},
       # Scrape Otodom every 4 hours with 8 pages (offset by 2 hours from OLX)
       # Runs at: 2:00, 6:00, 10:00, 14:00, 18:00, 22:00
       {"0 2,6,10,14,18,22 * * *", Rzeczywiscie.Workers.OtodomScraperWorker, args: %{"pages" => 8, "delay" => 3000}},
       # Daily enrichment run - scrape with enrichment once a day at 5 AM
       # Fixes missing data + fetches descriptions
       {"0 5 * * *", Rzeczywiscie.Workers.OlxScraperWorker, args: %{"pages" => 5, "delay" => 3000, "enrich" => true}},
       {"30 5 * * *", Rzeczywiscie.Workers.OtodomScraperWorker, args: %{"pages" => 5, "delay" => 3000, "enrich" => true}},
       # Track price changes every 2 hours
       {"0 */2 * * *", Rzeczywiscie.Workers.PriceTrackerWorker},
       # Mark stale properties inactive daily at 3 AM (96 hours = 4 days without being seen)
       {"0 3 * * *", Rzeczywiscie.Workers.CleanupWorker, args: %{"hours" => 96}},
       # Geocode properties every hour
       {"0 * * * *", Rzeczywiscie.Workers.GeocodingWorker}
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
