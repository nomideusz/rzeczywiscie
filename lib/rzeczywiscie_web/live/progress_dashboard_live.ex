defmodule RzeczywiscieWeb.ProgressDashboardLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.LifePlanning

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    insights = LifePlanning.get_productivity_insights()
    daily_trend = LifePlanning.get_completion_trend(30)
    weekly_trend = LifePlanning.get_weekly_completion_trend(12)
    project_stats = LifePlanning.get_project_completion_stats()

    socket =
      socket
      |> assign(:insights, insights)
      |> assign(:daily_trend, daily_trend)
      |> assign(:weekly_trend, weekly_trend)
      |> assign(:project_stats, project_stats)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <div class="container mx-auto px-2 sm:px-4 py-4 pb-20 sm:pb-4 max-w-7xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-3 sm:mb-4">
          <ul>
            <li><a href="/life" class="hover:underline">Dashboard</a></li>
            <li class="truncate max-w-[150px] sm:max-w-none">Progress Analytics</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-xl mb-4 sm:mb-6 animate-in fade-in zoom-in duration-300">
          <div class="card-body p-4 sm:p-6">
            <h1 class="text-3xl sm:text-4xl font-bold flex items-center gap-2">
              <span class="text-4xl sm:text-5xl" aria-hidden="true">📊</span>
              <span>Progress Analytics</span>
            </h1>
            <p class="text-base sm:text-lg opacity-90 mt-2">
              Track your productivity and celebrate your growth
            </p>
          </div>
        </div>

        <!-- Key Metrics -->
        <div class="grid grid-cols-2 md:grid-cols-2 lg:grid-cols-4 gap-2 sm:gap-4 mb-4 sm:mb-6">
          <div class="stat bg-base-200 shadow rounded-box p-3 sm:p-4 animate-in fade-in duration-300">
            <div class="stat-title text-xs sm:text-sm">Completion Rate</div>
            <div class="stat-value text-primary text-2xl sm:text-3xl"><%= @insights.completion_rate %>%</div>
            <div class="stat-desc text-xs"><%= @insights.completed_tasks %>/<%= @insights.total_tasks %> tasks</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box p-3 sm:p-4 animate-in fade-in duration-400">
            <div class="stat-title text-xs sm:text-sm">Weekly Velocity</div>
            <div class="stat-value text-secondary text-2xl sm:text-3xl"><%= @insights.velocity %></div>
            <div class="stat-desc text-xs">tasks/week</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box p-3 sm:p-4 animate-in fade-in duration-500">
            <div class="stat-title text-xs sm:text-sm">Pending</div>
            <div class="stat-value text-2xl sm:text-3xl"><%= @insights.pending_tasks %></div>
            <div class="stat-desc text-xs">in <%= @insights.total_projects %> projects</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box p-3 sm:p-4 animate-in fade-in duration-600">
            <div class="stat-title text-xs sm:text-sm">Urgent</div>
            <div class="stat-value text-warning text-2xl sm:text-3xl"><%= @insights.urgent_count %></div>
            <div class="stat-desc text-xs">
              <%= if @insights.overdue_count > 0 do %>
                <span class="text-error font-bold"><%= @insights.overdue_count %> overdue</span>
              <% else %>
                None overdue
              <% end %>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-6 mb-4 sm:mb-6">
          <!-- Weekly Completion Trend -->
          <div class="card bg-base-200 shadow-xl animate-in fade-in duration-400">
            <div class="card-body p-4 sm:p-6">
              <h2 class="card-title text-lg sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                <span class="text-xl sm:text-2xl" aria-hidden="true">📈</span>
                <span class="text-sm sm:text-base">Weekly Completions</span>
              </h2>
              <%= if length(@weekly_trend) > 0 do %>
                <% max_count = Enum.max_by(@weekly_trend, & &1.count, fn -> %{count: 1} end).count %>
                <div class="space-y-1 sm:space-y-2">
                  <%= for week_data <- Enum.reverse(@weekly_trend) do %>
                    <div class="flex items-center gap-2 sm:gap-3">
                      <div class="text-xs w-16 sm:w-24 opacity-70 shrink-0">
                        <%= Calendar.strftime(week_data.week_start, "%b %d") %>
                      </div>
                      <div class="flex-1">
                        <div class="flex items-center gap-2">
                          <div class="flex-1 bg-base-300 rounded-full h-5 sm:h-6 overflow-hidden">
                            <div
                              class="bg-primary h-full rounded-full flex items-center justify-center text-xs font-bold text-primary-content transition-all"
                              style={"width: #{if max_count > 0, do: week_data.count / max_count * 100, else: 0}%"}
                              role="progressbar"
                              aria-valuenow={week_data.count}
                              aria-valuemin="0"
                              aria-valuemax={max_count}
                              aria-label={"#{week_data.count} tasks completed"}
                            >
                              <%= if week_data.count > 0, do: week_data.count, else: "" %>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-xs sm:text-sm opacity-70">No data yet. Start completing tasks!</p>
              <% end %>
            </div>
          </div>

          <!-- Daily Completion Trend (Last 30 Days) -->
          <div class="card bg-base-200 shadow-xl animate-in fade-in duration-500">
            <div class="card-body p-4 sm:p-6">
              <h2 class="card-title text-lg sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                <span class="text-xl sm:text-2xl" aria-hidden="true">📅</span>
                <span class="text-sm sm:text-base">Daily Activity</span>
              </h2>
              <%= if length(@daily_trend) > 0 do %>
                <% max_daily = Enum.max_by(@daily_trend, & &1.count, fn -> %{count: 1} end).count %>
                <div class="flex items-end justify-between gap-px sm:gap-1 h-32 sm:h-48">
                  <%= for day_data <- @daily_trend do %>
                    <div
                      class="tooltip flex-1 bg-primary rounded-t hover:bg-primary-focus cursor-pointer transition-all"
                      data-tip={"#{Calendar.strftime(day_data.date, "%b %d")}: #{day_data.count} tasks"}
                      style={"height: #{if max_daily > 0, do: day_data.count / max_daily * 100, else: 0}%"}
                      role="img"
                      aria-label={"#{Calendar.strftime(day_data.date, "%b %d")}: #{day_data.count} tasks"}
                    >
                    </div>
                  <% end %>
                </div>
                <div class="text-xs opacity-70 text-center mt-2">
                  <span class="hidden sm:inline">Hover over bars to see details</span>
                  <span class="sm:hidden">30-day activity view</span>
                </div>
              <% else %>
                <p class="text-xs sm:text-sm opacity-70">No data yet. Start completing tasks!</p>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Project Completion Stats -->
        <div class="card bg-base-200 shadow-xl mb-4 sm:mb-6 animate-in fade-in duration-600">
          <div class="card-body p-4 sm:p-6">
            <h2 class="card-title text-lg sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
              <span class="text-xl sm:text-2xl" aria-hidden="true">🎯</span>
              <span>Project Progress</span>
            </h2>
            <%= if length(@project_stats) > 0 do %>
              <div class="overflow-x-auto -mx-4 sm:mx-0">
                <table class="table table-sm sm:table-md">
                  <thead>
                    <tr>
                      <th class="text-xs sm:text-sm">Project</th>
                      <th class="text-xs sm:text-sm">Progress</th>
                      <th class="text-xs sm:text-sm">Tasks</th>
                      <th class="text-xs sm:text-sm">%</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for project <- @project_stats do %>
                      <tr class="hover">
                        <td class="min-w-[120px] sm:min-w-0">
                          <a href={"/life/projects/#{project.project_id}"} class="flex items-center gap-2 link hover:underline">
                            <span class="text-lg sm:text-2xl"><%= project.emoji %></span>
                            <span class="font-medium text-xs sm:text-sm truncate max-w-[100px] sm:max-w-none"><%= project.project_name %></span>
                          </a>
                        </td>
                        <td class="min-w-[100px] sm:w-1/3">
                          <div class="flex items-center gap-2">
                            <progress
                              class="progress progress-primary w-full h-2 sm:h-3"
                              value={project.completion_rate}
                              max="100"
                              aria-label={"Progress: #{project.completion_rate}%"}
                              aria-valuenow={project.completion_rate}
                              aria-valuemin="0"
                              aria-valuemax="100"
                            ></progress>
                          </div>
                        </td>
                        <td>
                          <span class="text-xs sm:text-sm whitespace-nowrap">
                            <%= project.completed_count %>/<%= project.total_count %>
                          </span>
                        </td>
                        <td>
                          <span class={"badge badge-xs sm:badge-sm " <> completion_badge_class(project.completion_rate)}>
                            <%= project.completion_rate %>%
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <p class="text-xs sm:text-sm opacity-70">No projects yet. Create your first project to get started!</p>
            <% end %>
          </div>
        </div>

        <!-- Insights & Recommendations -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-6">
          <div class="card bg-info text-info-content shadow-xl animate-in fade-in duration-700">
            <div class="card-body p-4 sm:p-6">
              <h3 class="card-title text-base sm:text-lg flex items-center gap-2">
                <span aria-hidden="true">💡</span>
                <span>Insights</span>
              </h3>
              <ul class="text-xs sm:text-sm space-y-2 mt-2">
                <%= if @insights.completion_rate >= 70 do %>
                  <li>✨ Excellent completion rate! You're crushing it!</li>
                <% else %>
                  <li>📈 <%= trunc(100 - @insights.completion_rate) %>% of tasks still pending - keep pushing!</li>
                <% end %>

                <%= if @insights.velocity > 0 do %>
                  <li>🚀 Completing ~<%= @insights.velocity %> tasks/week on average</li>
                <% else %>
                  <li>⏰ No tasks completed recently - time to build momentum!</li>
                <% end %>

                <%= if @insights.overdue_count > 0 do %>
                  <li>⚠️ <%= @insights.overdue_count %> tasks are overdue - prioritize these!</li>
                <% end %>

                <%= if length(@project_stats) > 0 do %>
                  <% top_project = Enum.at(@project_stats, 0) %>
                  <li>🎯 Top: <%= top_project.emoji %> <%= top_project.project_name %> (<%= top_project.completion_rate %>%)</li>
                <% end %>
              </ul>
            </div>
          </div>

          <div class="card bg-success text-success-content shadow-xl animate-in fade-in duration-800">
            <div class="card-body p-4 sm:p-6">
              <h3 class="card-title text-base sm:text-lg flex items-center gap-2">
                <span aria-hidden="true">🎯</span>
                <span>Recommendations</span>
              </h3>
              <ul class="text-xs sm:text-sm space-y-2 mt-2">
                <%= if @insights.urgent_count > 5 do %>
                  <li>Focus on urgent tasks before adding new ones</li>
                <% end %>

                <%= if @insights.velocity < 3 do %>
                  <li>Aim to complete at least 3 tasks per week</li>
                <% end %>

                <li>Set aside time weekly for your weekly review</li>
                <li>Break down large tasks into smaller steps</li>
                <li>Celebrate your wins - <%= @insights.completed_tasks %> tasks done!</li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </.app>
    """
  end

  # Private helpers

  defp completion_badge_class(rate) when rate >= 75, do: "badge-success"
  defp completion_badge_class(rate) when rate >= 50, do: "badge-info"
  defp completion_badge_class(rate) when rate >= 25, do: "badge-warning"
  defp completion_badge_class(_rate), do: "badge-ghost"
end
