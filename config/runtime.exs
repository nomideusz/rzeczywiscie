import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/rzeczywiscie start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :rzeczywiscie, RzeczywiscieWeb.Endpoint, server: true
end

# Configure Google Maps API key at runtime (works in all environments)
config :rzeczywiscie,
  google_maps_api_key: System.get_env("GOOGLE_MAPS_API_KEY", "")

# Configure OpenAI API key for LLM-based property analysis
config :rzeczywiscie,
  openai_api_key: System.get_env("OPENAI_API_KEY", "")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :rzeczywiscie, Rzeczywiscie.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :rzeczywiscie, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Check origin configuration - can be disabled for debugging
  check_origin_config =
    case System.get_env("ORIGIN_CHECK") do
      "false" -> false
      _ -> [
        "https://#{host}",
        "https://www.#{host}",
        "http://#{host}",
        "http://www.#{host}"
      ]
    end

  config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind on all IPv4 interfaces for CapRover compatibility
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: check_origin_config

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :rzeczywiscie, RzeczywiscieWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

end

# ## Mailer - SMTP submission to our own Stalwart server
#
# Alerts are sent through the mailbox server (Stalwart) over SMTP submission.
# Only 465 with implicit TLS is used: Stalwart's 587/STARTTLS submission
# listener is not reliably exposed, and on CapRover the internal
# srv-captain--mail address only serves HTTP - so this always goes out over the
# public submission endpoint with a real mailbox login.
#
#     MAIL_SMTP_HOST=mail.zaur.app
#     MAIL_SMTP_PORT=465
#     MAIL_SMTP_USERNAME=contact@kruk.live
#     MAIL_SMTP_PASSWORD=…            # mailbox password or Stalwart app password
#     MAIL_FROM=contact@kruk.live
#     MAIL_FROM_NAME=Kruk.live
#     ALERT_EMAIL_TO=contact@kruk.live # where alert digests are delivered
#
# With MAIL_SMTP_HOST unset the mailer stays on the local (no-op) adapter and
# Alerts.deliver/1 reports {:error, :not_configured} instead of crashing jobs.
smtp_host = System.get_env("MAIL_SMTP_HOST")

if smtp_host not in [nil, ""] do
  smtp_port = String.to_integer(System.get_env("MAIL_SMTP_PORT") || "465")

  # Implicit TLS on 465; STARTTLS only if someone deliberately points this at 587
  implicit_tls? = smtp_port == 465

  tls_options =
    [
      # SNI must name the public host even when connecting through a relay alias
      server_name_indication:
        String.to_charlist(System.get_env("MAIL_SMTP_TLS_SERVERNAME") || smtp_host),
      versions: [:"tlsv1.2", :"tlsv1.3"],
      depth: 3
    ] ++
      if System.get_env("MAIL_SMTP_INSECURE") == "true" do
        # Escape hatch for a self-signed cert on a private deployment
        [verify: :verify_none]
      else
        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      end

  config :rzeczywiscie, Rzeczywiscie.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: smtp_port,
    username: System.get_env("MAIL_SMTP_USERNAME"),
    password: System.get_env("MAIL_SMTP_PASSWORD"),
    ssl: implicit_tls?,
    tls: if(implicit_tls?, do: :never, else: :always),
    auth: :always,
    tls_options: tls_options,
    retries: 1,
    no_mx_lookups: true

  config :rzeczywiscie, :mail,
    from: System.get_env("MAIL_FROM") || System.get_env("MAIL_SMTP_USERNAME"),
    from_name: System.get_env("MAIL_FROM_NAME") || "Kruk.live",
    alert_to: System.get_env("ALERT_EMAIL_TO") || System.get_env("MAIL_FROM")
end

# Admin panel BasicAuth (any username). Unset => /admin is inaccessible.
if config_env() == :prod do
  config :rzeczywiscie, :admin_password, System.get_env("ADMIN_PASSWORD")
end
