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
      <nav class="container mx-auto px-4">
        <div class="flex items-center justify-between h-16">
          <!-- Logo - Brutalist -->
          <a href={~p"/"} class="flex items-center gap-2 sm:gap-3 group">
            <div class="w-8 h-8 sm:w-10 sm:h-10 bg-primary border-2 border-base-content flex items-center justify-center font-black text-primary-content text-sm sm:text-base">
              R
            </div>
            <span class="text-base sm:text-xl font-black uppercase tracking-tighter hidden sm:inline">
              Rzeka
            </span>
            <span class="text-base font-black uppercase tracking-tighter sm:hidden">
              RZK
            </span>
          </a>

          <!-- Desktop Navigation -->
          <div class="hidden md:flex items-center gap-1">
            <a
              href={~p"/draw"}
              class="px-3 lg:px-4 py-2 text-xs lg:text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Draw
            </a>
            <a
              href={~p"/kanban"}
              class="px-3 lg:px-4 py-2 text-xs lg:text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Kanban
            </a>
            <a
              href={~p"/world"}
              class="px-3 lg:px-4 py-2 text-xs lg:text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              World
            </a>
            <a
              href={~p"/real-estate"}
              class="px-3 lg:px-4 py-2 text-xs lg:text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Properties
            </a>
          </div>

          <!-- Mobile Menu Button -->
          <button
            class="md:hidden p-2 border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            phx-click={JS.toggle(to: "#mobile-menu")}
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="square" stroke-linejoin="miter" stroke-width="3" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
        </div>

        <!-- Mobile Menu -->
        <div id="mobile-menu" class="hidden md:hidden border-t-2 border-base-content py-4">
          <div class="flex flex-col space-y-2">
            <a
              href={~p"/draw"}
              class="px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 border-transparent hover:border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              ✏️ Draw
            </a>
            <a
              href={~p"/kanban"}
              class="px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 border-transparent hover:border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              📋 Kanban
            </a>
            <a
              href={~p"/world"}
              class="px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 border-transparent hover:border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              🌍 World
            </a>
            <a
              href={~p"/real-estate"}
              class="px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 border-transparent hover:border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              🏠 Properties
            </a>
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
                Rzeka
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
              <li>
                <a
                  href={~p"/world"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-accent"
                >
                  Live World Map
                </a>
              </li>
              <li>
                <a
                  href={~p"/real-estate"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-success"
                >
                  Real Estate Scraper
                </a>
              </li>
              <li>
                <a
                  href={~p"/favorites"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-error"
                >
                  Favorites
                </a>
              </li>
              <li>
                <a
                  href={~p"/stats"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-info"
                >
                  Statistics
                </a>
              </li>
              <li>
                <a
                  href={~p"/admin"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-warning"
                >
                  Admin Panel
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
          © 2024 Rzeka.live
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

end
