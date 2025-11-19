defmodule RzeczywiscieWeb.HomeLive do
  use RzeczywiscieWeb, :live_view

  def render(assigns) do
    ~H"""
    <!-- Hero Section with Gradient -->
    <div class="relative overflow-hidden bg-gradient-to-br from-primary/5 via-base-100 to-secondary/5">
      <div class="absolute inset-0 bg-grid-pattern opacity-[0.02]"></div>
      <div class="container mx-auto px-4 py-24 sm:py-32 relative">
        <div class="max-w-4xl mx-auto text-center">
          <div class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 text-primary text-sm font-medium mb-8 animate-fade-in">
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-primary"></span>
            </span>
            Real-time collaboration platform
          </div>

          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-bold mb-6 bg-gradient-to-r from-primary via-secondary to-accent bg-clip-text text-transparent leading-tight">
            Rzeczywiscie
          </h1>

          <p class="text-xl sm:text-2xl mb-6 text-base-content/80 font-light">
            Build together in real-time
          </p>

          <p class="text-lg mb-12 text-base-content/60 max-w-2xl mx-auto leading-relaxed">
            Experience instant collaboration with Phoenix LiveView and Svelte 5.
            Every action synchronizes across all clients in milliseconds.
          </p>

          <div class="flex flex-col sm:flex-row gap-4 justify-center items-center">
            <a
              href={~p"/draw"}
              class="btn btn-primary btn-lg gap-2 group shadow-lg hover:shadow-xl transition-all"
            >
              Try Drawing Board
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 group-hover:translate-x-1 transition-transform"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                />
              </svg>
            </a>
            <a
              href={~p"/kanban"}
              class="btn btn-outline btn-lg gap-2 group hover:shadow-lg transition-all"
            >
              Try Kanban Board
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 group-hover:translate-x-1 transition-transform"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 7l5 5m0 0l-5 5m5-5H6"
                />
              </svg>
            </a>
          </div>
        </div>
      </div>
    </div>
    <!-- Apps Section -->
    <div class="container mx-auto px-4 py-20">
      <div class="text-center mb-16">
        <h2 class="text-4xl font-bold mb-4">Collaborative Applications</h2>
        <p class="text-lg text-base-content/60 max-w-2xl mx-auto">
          Choose your tool and start collaborating with others in real-time
        </p>
      </div>

      <div class="grid lg:grid-cols-2 gap-8 max-w-6xl mx-auto">
        <!-- Drawing Board Card - Modern Design -->
        <div class="group relative">
          <div class="absolute -inset-0.5 bg-gradient-to-r from-primary to-secondary rounded-3xl opacity-0 group-hover:opacity-100 transition duration-500 blur"></div>
          <div class="relative bg-base-100 rounded-3xl p-8 shadow-xl hover:shadow-2xl transition-all duration-300">
            <div class="flex items-start gap-6">
              <div class="flex-shrink-0">
                <div class="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center group-hover:scale-110 transition-transform duration-300">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    class="h-8 w-8 text-primary"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
                    />
                  </svg>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="text-2xl font-bold mb-3">Drawing Board</h3>
                <p class="text-base-content/70 mb-6 leading-relaxed">
                  Real-time collaborative canvas where multiple users can draw simultaneously.
                  See live cursors and instant stroke synchronization.
                </p>
                <div class="flex flex-wrap gap-2 mb-6">
                  <span class="badge badge-sm badge-primary gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    Real-time sync
                  </span>
                  <span class="badge badge-sm badge-secondary gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z" />
                    </svg>
                    Multiplayer
                  </span>
                  <span class="badge badge-sm badge-accent gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fill-rule="evenodd"
                        d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    Instant updates
                  </span>
                </div>
                <a
                  href={~p"/draw"}
                  class="btn btn-primary gap-2 group/btn shadow-md hover:shadow-lg transition-all"
                >
                  Launch App
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5 group-hover/btn:translate-x-1 transition-transform"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 7l5 5m0 0l-5 5m5-5H6"
                    />
                  </svg>
                </a>
              </div>
            </div>
          </div>
        </div>
        <!-- Kanban Board Card - Modern Design -->
        <div class="group relative">
          <div class="absolute -inset-0.5 bg-gradient-to-r from-secondary to-accent rounded-3xl opacity-0 group-hover:opacity-100 transition duration-500 blur"></div>
          <div class="relative bg-base-100 rounded-3xl p-8 shadow-xl hover:shadow-2xl transition-all duration-300">
            <div class="flex items-start gap-6">
              <div class="flex-shrink-0">
                <div class="w-16 h-16 rounded-2xl bg-secondary/10 flex items-center justify-center group-hover:scale-110 transition-transform duration-300">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    class="h-8 w-8 text-secondary"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
                    />
                  </svg>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="text-2xl font-bold mb-3">Kanban Board</h3>
                <p class="text-base-content/70 mb-6 leading-relaxed">
                  Organize tasks with drag-and-drop simplicity. All team members see updates
                  instantly as tasks move through your workflow.
                </p>
                <div class="flex flex-wrap gap-2 mb-6">
                  <span class="badge badge-sm badge-primary gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M2 6a2 2 0 012-2h5l2 2h5a2 2 0 012 2v6a2 2 0 01-2 2H4a2 2 0 01-2-2V6z" />
                    </svg>
                    Task management
                  </span>
                  <span class="badge badge-sm badge-secondary gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M3 12v3c0 1.657 3.134 3 7 3s7-1.343 7-3v-3c0 1.657-3.134 3-7 3s-7-1.343-7-3z" />
                      <path d="M3 7v3c0 1.657 3.134 3 7 3s7-1.343 7-3V7c0 1.657-3.134 3-7 3S3 8.657 3 7z" />
                      <path d="M17 5c0 1.657-3.134 3-7 3S3 6.657 3 5s3.134-3 7-3 7 1.343 7 3z" />
                    </svg>
                    Drag & drop
                  </span>
                  <span class="badge badge-sm badge-accent gap-1">
                    <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M13 6a3 3 0 11-6 0 3 3 0 016 0zM18 8a2 2 0 11-4 0 2 2 0 014 0zM14 15a4 4 0 00-8 0v3h8v-3zM6 8a2 2 0 11-4 0 2 2 0 014 0zM16 18v-3a5.972 5.972 0 00-.75-2.906A3.005 3.005 0 0119 15v3h-3zM4.75 12.094A5.973 5.973 0 004 15v3H1v-3a3 3 0 013.75-2.906z" />
                    </svg>
                    Team sync
                  </span>
                </div>
                <a
                  href={~p"/kanban"}
                  class="btn btn-secondary gap-2 group/btn shadow-md hover:shadow-lg transition-all"
                >
                  Launch App
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5 group-hover/btn:translate-x-1 transition-transform"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 7l5 5m0 0l-5 5m5-5H6"
                    />
                  </svg>
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    <!-- Technology Stack Section -->
    <div class="bg-base-200/50 py-20">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl font-bold mb-3">Powered by Modern Technology</h2>
          <p class="text-base-content/60">Built with the best tools for real-time applications</p>
        </div>
        <div class="grid md:grid-cols-3 gap-8 max-w-4xl mx-auto">
          <div class="text-center p-6 bg-base-100 rounded-2xl shadow-md hover:shadow-lg transition-shadow">
            <div class="w-12 h-12 mx-auto mb-4 rounded-xl bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center text-2xl">
              ⚡
            </div>
            <h3 class="text-xl font-semibold mb-2">Phoenix LiveView</h3>
            <p class="text-base-content/60 text-sm leading-relaxed">
              Real-time server-rendered apps with minimal JavaScript
            </p>
          </div>
          <div class="text-center p-6 bg-base-100 rounded-2xl shadow-md hover:shadow-lg transition-shadow">
            <div class="w-12 h-12 mx-auto mb-4 rounded-xl bg-gradient-to-br from-orange-500 to-red-500 flex items-center justify-center text-2xl">
              🎨
            </div>
            <h3 class="text-xl font-semibold mb-2">Svelte 5</h3>
            <p class="text-base-content/60 text-sm leading-relaxed">
              Reactive components with blazing fast performance
            </p>
          </div>
          <div class="text-center p-6 bg-base-100 rounded-2xl shadow-md hover:shadow-lg transition-shadow">
            <div class="w-12 h-12 mx-auto mb-4 rounded-xl bg-gradient-to-br from-blue-500 to-cyan-500 flex items-center justify-center text-2xl">
              🚀
            </div>
            <h3 class="text-xl font-semibold mb-2">LiveSvelte</h3>
            <p class="text-base-content/60 text-sm leading-relaxed">
              Seamless integration between Phoenix and Svelte
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
