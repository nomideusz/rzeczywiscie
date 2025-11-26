defmodule RzeczywiscieWeb.Live.Hooks do
  @moduledoc """
  LiveView lifecycle hooks for common functionality.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  @doc """
  Sets the current path in socket assigns for navigation highlighting.

  Usage in router:
      live_session :default, on_mount: {RzeczywiscieWeb.Live.Hooks, :set_current_path} do
        live "/page", PageLive
      end
  """
  def on_mount(:set_current_path, _params, _session, socket) do
    {:cont, attach_hook(socket, :set_path, :handle_params, &handle_params/3)}
  end

  defp handle_params(_params, uri, socket) do
    %URI{path: path} = URI.parse(uri)
    {:cont, assign(socket, :current_path, path)}
  end
end

