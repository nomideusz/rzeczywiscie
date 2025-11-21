defmodule RzeczywiscieWeb.HomeLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts

  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
    <!-- Hero Section - Neo-Brutalist -->
    <div class="relative overflow-hidden bg-base-100">
      <!-- Textured background pattern -->
      <div class="absolute inset-0 opacity-[0.03]" style="background-image: url('data:image/svg+xml,%3Csvg width=&quot;60&quot; height=&quot;60&quot; viewBox=&quot;0 0 60 60&quot; xmlns=&quot;http://www.w3.org/2000/svg&quot;%3E%3Cg fill=&quot;none&quot; fill-rule=&quot;evenodd&quot;%3E%3Cg fill=&quot;%23000000&quot; fill-opacity=&quot;1&quot;%3E%3Cpath d=&quot;M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z&quot;/%3E%3C/g%3E%3C/g%3E%3C/svg%3E');"></div>

      <!-- Asymmetric accent shape -->
      <div class="absolute top-0 right-0 w-[500px] h-[500px] bg-primary/5 rounded-bl-full -translate-y-1/2 translate-x-1/2"></div>

      <div class="container mx-auto px-4 py-16 sm:py-24 relative">
        <!-- Status indicator - raw style -->
        <div class="mb-12 flex items-center gap-3">
          <div class="w-3 h-3 bg-primary rounded-none animate-pulse"></div>
          <span class="text-xs uppercase tracking-[0.3em] font-bold opacity-70">
            Live
          </span>
        </div>

        <!-- Main title - oversized, bold, asymmetric -->
        <div class="grid lg:grid-cols-12 gap-8 items-center">
          <div class="lg:col-span-7">
            <h1 class="text-6xl sm:text-7xl lg:text-8xl xl:text-9xl font-black leading-[0.9] tracking-tighter mb-8">
              RZECZY
              <br />
              <span class="text-primary">WISCIE</span>
            </h1>

            <div class="flex items-start gap-4 mb-12">
              <div class="w-1 h-24 bg-primary"></div>
              <div>
                <p class="text-2xl sm:text-3xl font-light mb-4 leading-tight">
                  Real-time<br />collaboration
                </p>
                <p class="text-base opacity-70 max-w-md leading-relaxed">
                  Phoenix LiveView × Svelte 5.<br />
                  Instant synchronization.<br />
                  Zero configuration.
                </p>
              </div>
            </div>

            <!-- CTAs - brutal buttons -->
            <div class="flex flex-col sm:flex-row gap-3 sm:gap-4">
              <a
                href={~p"/draw"}
                class="group relative px-6 sm:px-8 py-3 sm:py-4 bg-primary text-primary-content font-bold text-base sm:text-lg tracking-wide uppercase border-4 border-base-content hover:translate-x-1 hover:translate-y-1 transition-transform text-center"
              >
                <span class="relative z-10">Draw</span>
                <div class="absolute inset-0 bg-base-content translate-x-1 translate-y-1 -z-10"></div>
              </a>
              <a
                href={~p"/kanban"}
                class="group relative px-6 sm:px-8 py-3 sm:py-4 bg-base-100 font-bold text-base sm:text-lg tracking-wide uppercase border-4 border-base-content hover:bg-base-content hover:text-base-100 transition-colors text-center"
              >
                Kanban
              </a>
              <a
                href={~p"/world"}
                class="group relative px-6 sm:px-8 py-3 sm:py-4 bg-accent text-accent-content font-bold text-base sm:text-lg tracking-wide uppercase border-4 border-base-content hover:translate-x-1 hover:translate-y-1 transition-transform text-center"
              >
                🌍 World
              </a>
            </div>
          </div>

          <!-- Geometric visual element -->
          <div class="lg:col-span-5 relative h-[400px] hidden lg:block">
            <div class="absolute top-0 right-0 w-64 h-64 border-[20px] border-primary"></div>
            <div class="absolute bottom-0 left-0 w-48 h-48 bg-secondary"></div>
            <div class="absolute top-1/3 right-1/4 w-32 h-32 border-8 border-accent rotate-45"></div>
          </div>
        </div>
      </div>
    </div>
    <!-- Apps Section - Asymmetric Grid -->
    <div class="bg-base-200/30 py-20">
      <div class="container mx-auto px-4">
        <!-- Section header - offset -->
        <div class="mb-16 max-w-xl">
          <div class="flex items-center gap-4 mb-6">
            <div class="w-12 h-1 bg-base-content"></div>
            <span class="text-sm uppercase tracking-widest font-bold opacity-50">
              02 / Apps
            </span>
          </div>
          <h2 class="text-5xl sm:text-6xl font-black tracking-tight leading-none">
            COLLABORATE
          </h2>
        </div>

        <div class="grid lg:grid-cols-2 gap-8 lg:gap-12 max-w-7xl">
        <!-- Drawing Board Card - Brutalist -->
        <div class="group relative border-4 border-base-content bg-base-100 p-8 hover:translate-x-1 hover:translate-y-1 transition-transform">
          <!-- Accent bar -->
          <div class="absolute top-0 left-0 w-2 h-full bg-primary"></div>

          <!-- Number badge -->
          <div class="absolute top-4 right-4 w-12 h-12 border-2 border-base-content flex items-center justify-center font-black text-xl">
            01
          </div>

          <div class="pr-16">
            <!-- Icon - geometric -->
            <div class="w-20 h-20 border-4 border-primary mb-6 flex items-center justify-center">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                class="h-10 w-10"
                stroke="currentColor"
                stroke-width="2.5"
              >
                <path
                  stroke-linecap="square"
                  stroke-linejoin="miter"
                  d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
                />
              </svg>
            </div>

            <h3 class="text-4xl font-black mb-4 tracking-tight uppercase">
              Drawing<br />Board
            </h3>

            <p class="text-base opacity-70 mb-6 leading-relaxed">
              Real-time collaborative canvas. Multiple users draw simultaneously with instant synchronization.
            </p>

            <!-- Tags - raw style -->
            <div class="flex flex-wrap gap-2 mb-8">
              <span class="px-3 py-1 text-xs uppercase tracking-wider bg-primary text-primary-content font-bold">
                Real-time
              </span>
              <span class="px-3 py-1 text-xs uppercase tracking-wider border-2 border-base-content font-bold">
                Multi-user
              </span>
              <span class="px-3 py-1 text-xs uppercase tracking-wider bg-base-content text-base-100 font-bold">
                Instant
              </span>
            </div>

            <a
              href={~p"/draw"}
              class="inline-block px-6 py-3 bg-primary text-primary-content font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Launch →
            </a>
          </div>
        </div>
        <!-- Kanban Board Card - Brutalist (offset for asymmetry) -->
        <div class="group relative border-4 border-base-content bg-base-100 p-8 hover:translate-x-1 hover:translate-y-1 transition-transform lg:mt-12">
          <!-- Accent bar -->
          <div class="absolute top-0 left-0 w-2 h-full bg-secondary"></div>

          <!-- Number badge -->
          <div class="absolute top-4 right-4 w-12 h-12 border-2 border-base-content flex items-center justify-center font-black text-xl">
            02
          </div>

          <div class="pr-16">
            <!-- Icon - geometric -->
            <div class="w-20 h-20 border-4 border-secondary mb-6 flex items-center justify-center">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                class="h-10 w-10"
                stroke="currentColor"
                stroke-width="2.5"
              >
                <path
                  stroke-linecap="square"
                  stroke-linejoin="miter"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
                />
              </svg>
            </div>

            <h3 class="text-4xl font-black mb-4 tracking-tight uppercase">
              Kanban<br />Board
            </h3>

            <p class="text-base opacity-70 mb-6 leading-relaxed">
              Organize tasks with drag-and-drop simplicity. Real-time updates for all team members.
            </p>

            <!-- Tags - raw style -->
            <div class="flex flex-wrap gap-2 mb-8">
              <span class="px-3 py-1 text-xs uppercase tracking-wider bg-secondary text-secondary-content font-bold">
                Tasks
              </span>
              <span class="px-3 py-1 text-xs uppercase tracking-wider border-2 border-base-content font-bold">
                Drag & Drop
              </span>
              <span class="px-3 py-1 text-xs uppercase tracking-wider bg-base-content text-base-100 font-bold">
                Team
              </span>
            </div>

            <a
              href={~p"/kanban"}
              class="inline-block px-6 py-3 bg-secondary text-secondary-content font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
            >
              Launch →
            </a>
          </div>
        </div>

        <!-- Live World Map Card - Full Width, Special Feature -->
        <div class="group relative border-4 border-base-content bg-gradient-to-br from-base-100 to-accent/5 p-6 sm:p-8 hover:translate-x-1 hover:translate-y-1 transition-transform lg:col-span-2">
          <!-- Accent bar -->
          <div class="absolute top-0 left-0 w-2 h-full bg-accent"></div>

          <!-- Number badge -->
          <div class="absolute top-4 right-4 w-12 h-12 border-2 border-base-content flex items-center justify-center font-black text-xl">
            03
          </div>

          <div class="grid md:grid-cols-2 gap-8">
            <div class="pr-4 sm:pr-16">
              <!-- Icon - geometric -->
              <div class="w-20 h-20 border-4 border-accent mb-6 flex items-center justify-center">
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  class="h-10 w-10"
                  stroke="currentColor"
                  stroke-width="2.5"
                >
                  <path
                    stroke-linecap="square"
                    stroke-linejoin="miter"
                    d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>

              <h3 class="text-3xl sm:text-4xl font-black mb-4 tracking-tight uppercase">
                Live<br />World Map
              </h3>

              <p class="text-base opacity-70 mb-6 leading-relaxed">
                See all connected users in real-time on an interactive world map. Drop pins, track cursors, and collaborate globally with IP geolocation.
              </p>

              <!-- Tags - raw style -->
              <div class="flex flex-wrap gap-2 mb-8">
                <span class="px-3 py-1 text-xs uppercase tracking-wider bg-accent text-accent-content font-bold">
                  🌍 Global
                </span>
                <span class="px-3 py-1 text-xs uppercase tracking-wider border-2 border-base-content font-bold">
                  Live Tracking
                </span>
                <span class="px-3 py-1 text-xs uppercase tracking-wider bg-base-content text-base-100 font-bold">
                  Geolocation
                </span>
              </div>

              <a
                href={~p"/world"}
                class="inline-block px-6 py-3 bg-accent text-accent-content font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
              >
                Explore →
              </a>
            </div>

            <!-- Visual Preview -->
            <div class="hidden md:flex items-center justify-center relative">
              <div class="relative w-full max-w-xs">
                <!-- Animated Globe Illustration -->
                <div class="w-48 h-48 mx-auto border-4 border-accent rounded-full flex items-center justify-center relative overflow-hidden">
                  <div class="absolute inset-0 opacity-10" style="background-image: radial-gradient(circle, currentColor 1px, transparent 1px); background-size: 20px 20px;"></div>
                  <span class="text-6xl animate-pulse">🌍</span>
                  <!-- Ping markers -->
                  <div class="absolute top-1/4 right-1/4 w-3 h-3 bg-primary rounded-full animate-ping"></div>
                  <div class="absolute bottom-1/3 left-1/4 w-2 h-2 bg-secondary rounded-full animate-ping" style="animation-delay: 0.5s;"></div>
                  <div class="absolute top-1/2 right-1/3 w-2 h-2 bg-accent rounded-full animate-ping" style="animation-delay: 1s;"></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Real Estate Scraper Card - Brutalist -->
        <div class="group relative border-4 border-base-content bg-gradient-to-br from-base-100 to-success/5 p-6 sm:p-8 hover:translate-x-1 hover:translate-y-1 transition-transform lg:col-span-2 mt-8">
          <!-- Accent bar -->
          <div class="absolute top-0 left-0 w-2 h-full bg-success"></div>

          <!-- Number badge -->
          <div class="absolute top-4 right-4 w-12 h-12 border-2 border-base-content flex items-center justify-center font-black text-xl">
            04
          </div>

          <div class="grid md:grid-cols-2 gap-8">
            <div class="pr-4 sm:pr-16">
              <!-- Icon - geometric -->
              <div class="w-20 h-20 border-4 border-success mb-6 flex items-center justify-center">
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  class="h-10 w-10"
                  stroke="currentColor"
                  stroke-width="2.5"
                >
                  <path
                    stroke-linecap="square"
                    stroke-linejoin="miter"
                    d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
                  />
                </svg>
              </div>

              <h3 class="text-3xl sm:text-4xl font-black mb-4 tracking-tight uppercase">
                Real Estate<br />Scraper
              </h3>

              <p class="text-base opacity-70 mb-6 leading-relaxed">
                Live property listings from OLX and Otodom for Małopolskie region. Auto-updating table with filters, search, and real-time notifications.
              </p>

              <!-- Tags - raw style -->
              <div class="flex flex-wrap gap-2 mb-8">
                <span class="px-3 py-1 text-xs uppercase tracking-wider bg-success text-success-content font-bold">
                  🏠 Properties
                </span>
                <span class="px-3 py-1 text-xs uppercase tracking-wider border-2 border-base-content font-bold">
                  Auto-Scrape
                </span>
                <span class="px-3 py-1 text-xs uppercase tracking-wider bg-base-content text-base-100 font-bold">
                  Live Updates
                </span>
              </div>

              <a
                href={~p"/real-estate"}
                class="inline-block px-6 py-3 bg-success text-success-content font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
              >
                Browse →
              </a>
            </div>

            <!-- Visual Preview -->
            <div class="hidden md:flex items-center justify-center relative">
              <div class="relative w-full max-w-xs">
                <!-- Table/List Illustration -->
                <div class="space-y-3">
                  <div class="h-12 border-4 border-success bg-base-100 flex items-center px-4">
                    <div class="w-3/4 h-2 bg-base-content/20"></div>
                  </div>
                  <div class="h-12 border-4 border-base-content/30 bg-base-100 flex items-center px-4">
                    <div class="w-2/3 h-2 bg-base-content/20"></div>
                  </div>
                  <div class="h-12 border-4 border-base-content/30 bg-base-100 flex items-center px-4">
                    <div class="w-1/2 h-2 bg-base-content/20"></div>
                  </div>
                  <div class="absolute top-0 right-0 w-4 h-4 bg-success rounded-full animate-ping"></div>
                </div>
              </div>
            </div>
          </div>
        </div>
        </div>
      </div>
    </div>
    <!-- Technology Stack Section - Raw Grid -->
    <div class="border-t-4 border-base-content py-20">
      <div class="container mx-auto px-4">
        <div class="mb-16">
          <div class="flex items-center gap-4 mb-6">
            <div class="w-12 h-1 bg-base-content"></div>
            <span class="text-sm uppercase tracking-widest font-bold opacity-50">
              03 / Stack
            </span>
          </div>
          <h2 class="text-5xl sm:text-6xl font-black tracking-tight leading-none">
            TECHNOLOGY
          </h2>
        </div>

        <div class="grid md:grid-cols-3 gap-6 max-w-5xl">
          <!-- Phoenix -->
          <div class="border-4 border-base-content bg-base-100 p-6 hover:bg-base-content hover:text-base-100 transition-colors group">
            <div class="text-7xl font-black mb-4 opacity-20 group-hover:opacity-30">01</div>
            <h3 class="text-2xl font-black mb-3 uppercase tracking-tight">
              Phoenix<br />LiveView
            </h3>
            <p class="text-sm opacity-70 leading-relaxed mb-4">
              Real-time server-rendered applications with minimal JavaScript
            </p>
            <div class="w-8 h-1 bg-primary"></div>
          </div>

          <!-- Svelte -->
          <div class="border-4 border-base-content bg-base-100 p-6 hover:bg-base-content hover:text-base-100 transition-colors group md:mt-8">
            <div class="text-7xl font-black mb-4 opacity-20 group-hover:opacity-30">02</div>
            <h3 class="text-2xl font-black mb-3 uppercase tracking-tight">
              Svelte 5
            </h3>
            <p class="text-sm opacity-70 leading-relaxed mb-4">
              Reactive components with blazing fast performance
            </p>
            <div class="w-8 h-1 bg-secondary"></div>
          </div>

          <!-- LiveSvelte -->
          <div class="border-4 border-base-content bg-base-100 p-6 hover:bg-base-content hover:text-base-100 transition-colors group">
            <div class="text-7xl font-black mb-4 opacity-20 group-hover:opacity-30">03</div>
            <h3 class="text-2xl font-black mb-3 uppercase tracking-tight">
              LiveSvelte
            </h3>
            <p class="text-sm opacity-70 leading-relaxed mb-4">
              Seamless integration between Phoenix and Svelte
            </p>
            <div class="w-8 h-1 bg-accent"></div>
          </div>
        </div>
      </div>
    </div>
    </.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
