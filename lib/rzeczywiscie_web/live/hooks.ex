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

  @doc """
  Blocks LiveView mounts unless the session was authenticated by the
  `:admin_auth` router plug. Guards the websocket mount, which does not
  re-run router pipelines.
  """
  def on_mount(:require_admin, _params, session, socket) do
    if session["admin_authed"] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp handle_params(_params, uri, socket) do
    %URI{path: path} = URI.parse(uri)
    {:cont, assign(socket, :current_path, path)}
  end
end

