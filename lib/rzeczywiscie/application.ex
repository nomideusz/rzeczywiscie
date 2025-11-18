defmodule Rzeczywiscie.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]},
      RzeczywiscieWeb.Telemetry,
      Rzeczywiscie.Repo,
      {DNSCluster, query: Application.get_env(:rzeczywiscie, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rzeczywiscie.PubSub},
      RzeczywiscieWeb.Presence,
      # Start a worker by calling: Rzeczywiscie.Worker.start_link(arg)
      # {Rzeczywiscie.Worker, arg},
      # Start to serve requests, typically the last entry
      RzeczywiscieWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rzeczywiscie.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RzeczywiscieWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
