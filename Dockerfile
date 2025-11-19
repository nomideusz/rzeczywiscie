# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20231009-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.0-erlang-26.2.1-debian-bullseye-20231009-slim
#
ARG ELIXIR_VERSION=1.16.0
ARG OTP_VERSION=26.2.1
ARG DEBIAN_VERSION=bullseye-20231009-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets and lib (lib needed for Tailwind to scan templates)
COPY priv priv
COPY assets assets
COPY lib lib

# Install npm packages and build assets
WORKDIR /app/assets
RUN npm ci --prefer-offline --no-audit
RUN node build.js --deploy

# Compile Tailwind CSS (lib must exist for @source directives to work)
WORKDIR /app
RUN mix tailwind rzeczywiscie --minify

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Digest static files and verify they were created
RUN mix phx.digest && \
    echo "=== Listing digested files ===" && \
    ls -la priv/static/assets/css/ && \
    ls -la priv/static/assets/js/ && \
    echo "=== Cache manifest ===" && \
    head -20 priv/static/cache_manifest.json

# Build the release
RUN mix release

# Start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# Install runtime dependencies
RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js runtime (needed for SSR)
RUN apt-get update -y && apt-get install -y curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/rzeczywiscie ./

# Verify static files were copied to final image (build-time check)
RUN echo "=== Verifying in final container ===" && \
    ls -la /app/priv/static/ && \
    echo "=== Cache manifest exists? ===" && \
    test -f /app/priv/static/cache_manifest.json && echo "YES" || echo "NO"

# Create migration and startup script with runtime verification
RUN printf '#!/bin/sh\n\
echo "=== Runtime verification ==="\n\
echo "Static files at startup:"\n\
ls -la /app/priv/static/assets/css/ 2>&1 | head -3\n\
echo "Running migrations..."\n\
/app/bin/rzeczywiscie eval "Rzeczywiscie.Release.migrate()"\n\
echo "Starting server..."\n\
exec /app/bin/rzeczywiscie start\n' > /app/bin/migrate_and_start \
    && chmod +x /app/bin/migrate_and_start

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENV TINI_VERSION v0.19.0
# ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
# RUN chmod +x /tini
# ENTRYPOINT ["/tini", "--"]

# Run migrations and start the server
CMD ["/app/bin/migrate_and_start"]
