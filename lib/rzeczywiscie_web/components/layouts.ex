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

  # Helper to check if a path is active
  defp is_active?(current_path, href, match_prefix) when is_binary(current_path) do
    cond do
      # If match_prefix is provided, check if current path starts with any of the prefixes
      match_prefix != nil ->
        prefixes = String.split(match_prefix, ",")
        Enum.any?(prefixes, fn prefix -> String.starts_with?(current_path, prefix) end)

      # Otherwise, exact match or starts with href
      true ->
        current_path == href or String.starts_with?(current_path, href <> "/")
    end
  end

  defp is_active?(_current_path, _href, _match_prefix), do: false

  @doc """
  Renders a navigation link with active state styling.
  """
  attr :href, :string, required: true
  attr :current_path, :string, default: nil
  attr :match_prefix, :string, default: nil
  slot :inner_block, required: true

  def nav_link(assigns) do
    active = is_active?(assigns.current_path, assigns.href, assigns.match_prefix)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@href}
      class={[
        "px-3 lg:px-4 py-2 text-xs lg:text-sm font-bold uppercase tracking-wide transition-colors",
        @active && "bg-base-content text-base-100",
        not @active && "hover:bg-base-content hover:text-base-100"
      ]}
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  @doc """
  Renders a mobile navigation link with active state styling.
  """
  attr :href, :string, required: true
  attr :current_path, :string, default: nil
  attr :match_prefix, :string, default: nil
  attr :icon, :string, required: true
  slot :inner_block, required: true

  def mobile_nav_link(assigns) do
    active = is_active?(assigns.current_path, assigns.href, assigns.match_prefix)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@href}
      class={[
        "px-4 py-3 text-sm font-bold uppercase tracking-wide border-2 transition-colors",
        @active && "border-base-content bg-base-content text-base-100",
        not @active && "border-transparent hover:border-base-content hover:bg-base-content hover:text-base-100"
      ]}
    >
      {@icon} {render_slot(@inner_block)}
    </a>
    """
  end

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

  attr :current_path, :string, default: nil, doc: "the current request path for active link highlighting"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-50 bg-base-100 border-b-4 border-base-content">
      <nav class="container mx-auto px-4">
        <div class="flex items-center justify-between h-16">
          <!-- Logo - Brutalist -->
          <a href={~p"/"} class="flex items-center gap-2 sm:gap-3 group">
            <div class="w-8 h-8 sm:w-10 sm:h-10 bg-primary border-2 border-base-content flex items-center justify-center font-black text-primary-content text-sm sm:text-base">
              K
            </div>
            <span class="text-base sm:text-xl font-black uppercase tracking-tighter hidden sm:inline">
              Kruk
            </span>
            <span class="text-base font-black uppercase tracking-tighter sm:hidden">
              KRK
            </span>
          </a>

          <!-- Desktop Navigation -->
          <div class="hidden md:flex items-center gap-1">
            <.nav_link href={~p"/draw"} current_path={@current_path}>Draw</.nav_link>
            <.nav_link href={~p"/kanban"} current_path={@current_path}>Kanban</.nav_link>
            <.nav_link href={~p"/world"} current_path={@current_path}>World</.nav_link>
            <.nav_link href={~p"/pixels"} current_path={@current_path}>Pixels</.nav_link>
            <.nav_link href={~p"/real-estate"} current_path={@current_path} match_prefix="/real-estate,/favorites,/stats,/admin">Properties</.nav_link>
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
            <.mobile_nav_link href={~p"/draw"} current_path={@current_path} icon="✏️">Draw</.mobile_nav_link>
            <.mobile_nav_link href={~p"/kanban"} current_path={@current_path} icon="📋">Kanban</.mobile_nav_link>
            <.mobile_nav_link href={~p"/world"} current_path={@current_path} icon="🌍">World</.mobile_nav_link>
            <.mobile_nav_link href={~p"/pixels"} current_path={@current_path} icon="🎨">Pixels</.mobile_nav_link>
            <.mobile_nav_link href={~p"/real-estate"} current_path={@current_path} icon="🏠" match_prefix="/real-estate,/favorites,/stats,/admin">Properties</.mobile_nav_link>
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
                K
              </div>
              <span class="text-2xl font-black uppercase tracking-tighter">
                Kruk
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
                  href={~p"/pixels"}
                  class="text-sm font-bold hover:underline hover:underline-offset-4 decoration-2 decoration-warning"
                >
                  Pixel Canvas
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
          © <%= Date.utc_today().year %> Kruk.live
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
