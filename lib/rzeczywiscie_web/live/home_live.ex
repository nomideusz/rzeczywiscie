defmodule RzeczywiscieWeb.HomeLive do
  use RzeczywiscieWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="hero min-h-[60vh] bg-base-200">
      <div class="hero-content text-center">
        <div class="max-w-4xl">
          <h1 class="text-5xl font-bold mb-6">Welcome to Rzeczywiscie</h1>
          <p class="text-xl mb-8">
            Real-time collaborative applications built with Phoenix LiveView and Svelte 5
          </p>
          <p class="text-lg mb-12 text-base-content/70">
            Experience the power of real-time collaboration with these interactive applications.
            All changes are synchronized instantly across all connected clients.
          </p>
        </div>
      </div>
    </div>

    <div class="container mx-auto px-4 py-16">
      <h2 class="text-3xl font-bold text-center mb-12">Live Applications</h2>

      <div class="grid md:grid-cols-2 gap-8 max-w-5xl mx-auto">
        <!-- Drawing Board Card -->
        <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
          <figure class="px-10 pt-10">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              class="h-24 w-24 text-primary"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"
              />
            </svg>
          </figure>
          <div class="card-body items-center text-center">
            <h2 class="card-title text-2xl">Drawing Board</h2>
            <p class="text-base-content/70 mb-4">
              Collaborate in real-time on a shared canvas. Draw together with multiple users,
              see their cursors, and watch as drawings appear instantly across all connected clients.
            </p>
            <div class="flex flex-wrap gap-2 justify-center mb-4">
              <span class="badge badge-primary">Real-time sync</span>
              <span class="badge badge-secondary">Multiplayer</span>
              <span class="badge badge-accent">Canvas drawing</span>
            </div>
            <div class="card-actions">
              <a href={~p"/draw"} class="btn btn-primary btn-lg">
                Open Drawing Board
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-6 w-6"
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

        <!-- Kanban Board Card -->
        <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
          <figure class="px-10 pt-10">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              class="h-24 w-24 text-secondary"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
              />
            </svg>
          </figure>
          <div class="card-body items-center text-center">
            <h2 class="card-title text-2xl">Kanban Board</h2>
            <p class="text-base-content/70 mb-4">
              Manage tasks collaboratively with a real-time Kanban board. Create, move, and organize
              tasks with your team, seeing all changes instantly synchronized.
            </p>
            <div class="flex flex-wrap gap-2 justify-center mb-4">
              <span class="badge badge-primary">Task management</span>
              <span class="badge badge-secondary">Drag & drop</span>
              <span class="badge badge-accent">Team collaboration</span>
            </div>
            <div class="card-actions">
              <a href={~p"/kanban"} class="btn btn-secondary btn-lg">
                Open Kanban Board
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-6 w-6"
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

      <!-- Technology Stack Section -->
      <div class="mt-20">
        <h2 class="text-3xl font-bold text-center mb-8">Built With Modern Technology</h2>
        <div class="grid md:grid-cols-3 gap-6 max-w-4xl mx-auto">
          <div class="text-center p-6">
            <div class="text-4xl mb-3">⚡</div>
            <h3 class="text-xl font-semibold mb-2">Phoenix LiveView</h3>
            <p class="text-base-content/70">
              Real-time server-rendered applications with minimal JavaScript
            </p>
          </div>
          <div class="text-center p-6">
            <div class="text-4xl mb-3">🎨</div>
            <h3 class="text-xl font-semibold mb-2">Svelte 5</h3>
            <p class="text-base-content/70">
              Reactive components with blazing fast performance
            </p>
          </div>
          <div class="text-center p-6">
            <div class="text-4xl mb-3">🚀</div>
            <h3 class="text-xl font-semibold mb-2">LiveSvelte</h3>
            <p class="text-base-content/70">
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
