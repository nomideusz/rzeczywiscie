defmodule RzeczywiscieWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use RzeczywiscieWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-50 bg-base-100 border-b-4 border-base-content">
      <nav class="container mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <!-- Logo - Brutalist -->
          <a href={~p"/"} class="flex items-center gap-3 group">
            <div class="w-10 h-10 bg-primary border-2 border-base-content flex items-center justify-center font-black text-primary-content">
              R
            </div>
            <span class="text-xl font-black uppercase tracking-tighter">
              Rzeczywiscie
            </span>
          </a>
          <!-- Navigation - Raw style -->
          <div class="flex items-center gap-1">
            <a
              href={~p"/"}
              class="px-4 py-2 text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Home
            </a>
            <a
              href={~p"/draw"}
              class="px-4 py-2 text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Draw
            </a>
            <a
              href={~p"/kanban"}
              class="px-4 py-2 text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Kanban
            </a>
            <div class="ml-4 border-l-2 border-base-content pl-4">
              <.theme_toggle />
            </div>
          </div>
        </div>
      </nav>
    </header>

    <main class="min-h-[calc(100vh-4rem)]">
      {render_slot(@inner_block)}
    </main>

    <footer class="border-t-4 border-base-content bg-base-100">
      <div class="container mx-auto px-4 py-16">
        <div class="grid md:grid-cols-4 gap-12 mb-12">
          <!-- Brand Column -->
          <div class="md:col-span-2">
            <div class="flex items-center gap-3 mb-6">
              <div class="w-12 h-12 bg-primary border-2 border-base-content flex items-center justify-center font-black text-primary-content text-xl">
                R
              </div>
              <span class="text-2xl font-black uppercase tracking-tighter">
                Rzeczywiscie
              </span>
            </div>
            <p class="text-sm opacity-70 leading-relaxed max-w-md mb-6">
              Real-time collaborative applications. Phoenix LiveView × Svelte 5.
            </p>
            <div class="flex gap-2">
              <div class="w-16 h-1 bg-primary"></div>
              <div class="w-16 h-1 bg-secondary"></div>
              <div class="w-16 h-1 bg-accent"></div>
            </div>
          </div>
          <!-- Links Column -->
          <div>
            <h3 class="text-xs uppercase tracking-widest font-bold mb-4 opacity-50">Apps</h3>
            <ul class="space-y-3">
              <li>
                <a
                  href={~p"/draw"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-primary"
                >
                  Drawing Board
                </a>
              </li>
              <li>
                <a
                  href={~p"/kanban"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-secondary"
                >
                  Kanban Board
                </a>
              </li>
            </ul>
          </div>
          <!-- Tech Column -->
          <div>
            <h3 class="text-xs uppercase tracking-widest font-bold mb-4 opacity-50">Stack</h3>
            <ul class="space-y-3 text-sm">
              <li>
                <a
                  href="https://phoenixframework.org/"
                  class="font-bold hover:underline hover:underline-offset-4 decoration-2"
                  target="_blank"
                  rel="noopener"
                >
                  Phoenix
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/woutdp/live_svelte"
                  class="font-bold hover:underline hover:underline-offset-4 decoration-2"
                  target="_blank"
                  rel="noopener"
                >
                  LiveSvelte
                </a>
              </li>
              <li>
                <a
                  href="https://svelte.dev"
                  class="font-bold hover:underline hover:underline-offset-4 decoration-2"
                  target="_blank"
                  rel="noopener"
                >
                  Svelte 5
                </a>
              </li>
            </ul>
          </div>
        </div>
        <!-- Copyright bar -->
        <div class="pt-8 border-t-2 border-base-content text-xs uppercase tracking-widest font-bold opacity-50">
          © 2024 Rzeczywiscie
        </div>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
