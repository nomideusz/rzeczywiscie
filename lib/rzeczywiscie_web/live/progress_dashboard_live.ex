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
      <div class="container mx-auto p-4 max-w-7xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-4">
          <ul>
            <li><a href="/life">Dashboard</a></li>
            <li>Progress Analytics</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-blue-500 to-cyan-500 text-white shadow-xl mb-6">
          <div class="card-body">
            <h1 class="text-4xl font-bold">
              📊 Progress Analytics
            </h1>
            <p class="text-lg opacity-90">
              Track your productivity and celebrate your growth
            </p>
          </div>
        </div>

        <!-- Key Metrics -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <div class="stat bg-base-200 shadow rounded-box">
            <div class="stat-title">Completion Rate</div>
            <div class="stat-value text-primary"><%= @insights.completion_rate %>%</div>
            <div class="stat-desc"><%= @insights.completed_tasks %>/<%= @insights.total_tasks %> tasks done</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box">
            <div class="stat-title">Weekly Velocity</div>
            <div class="stat-value text-secondary"><%= @insights.velocity %></div>
            <div class="stat-desc">tasks per week (last 4 weeks)</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box">
            <div class="stat-title">Pending Tasks</div>
            <div class="stat-value"><%= @insights.pending_tasks %></div>
            <div class="stat-desc">across <%= @insights.total_projects %> projects</div>
          </div>

          <div class="stat bg-base-200 shadow rounded-box">
            <div class="stat-title">Urgent</div>
            <div class="stat-value text-warning"><%= @insights.urgent_count %></div>
            <div class="stat-desc">
              <%= if @insights.overdue_count > 0 do %>
                <span class="text-error font-bold"><%= @insights.overdue_count %> overdue</span>
              <% else %>
                None overdue 🎉
              <% end %>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <!-- Weekly Completion Trend -->
          <div class="card bg-base-200 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-2xl mb-4">📈 Weekly Completions (Last 12 Weeks)</h2>
              <%= if length(@weekly_trend) > 0 do %>
                <% max_count = Enum.max_by(@weekly_trend, & &1.count, fn -> %{count: 1} end).count %>
                <div class="space-y-2">
                  <%= for week_data <- Enum.reverse(@weekly_trend) do %>
                    <div class="flex items-center gap-3">
                      <div class="text-xs w-24 opacity-70">
                        <%= Calendar.strftime(week_data.week_start, "%b %d") %>
                      </div>
                      <div class="flex-1">
                        <div class="flex items-center gap-2">
                          <div class="flex-1 bg-base-300 rounded-full h-6 overflow-hidden">
                            <div
                              class="bg-primary h-full rounded-full flex items-center justify-center text-xs font-bold text-primary-content"
                              style={"width: #{if max_count > 0, do: week_data.count / max_count * 100, else: 0}%"}
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
                <p class="text-sm opacity-70">No data yet. Start completing tasks!</p>
              <% end %>
            </div>
          </div>

          <!-- Daily Completion Trend (Last 30 Days) -->
          <div class="card bg-base-200 shadow-xl">
            <div class="card-body">
              <h2 class="card-title text-2xl mb-4">📅 Daily Activity (Last 30 Days)</h2>
              <%= if length(@daily_trend) > 0 do %>
                <% max_daily = Enum.max_by(@daily_trend, & &1.count, fn -> %{count: 1} end).count %>
                <div class="flex items-end justify-between gap-1 h-48">
                  <%= for day_data <- @daily_trend do %>
                    <div
                      class="tooltip flex-1 bg-primary rounded-t hover:bg-primary-focus cursor-pointer transition-colors"
                      data-tip={"#{Calendar.strftime(day_data.date, "%b %d")}: #{day_data.count} tasks"}
                      style={"height: #{if max_daily > 0, do: day_data.count / max_daily * 100, else: 0}%"}
                    >
                    </div>
                  <% end %>
                </div>
                <div class="text-xs opacity-70 text-center mt-2">
                  Hover over bars to see details
                </div>
              <% else %>
                <p class="text-sm opacity-70">No data yet. Start completing tasks!</p>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Project Completion Stats -->
        <div class="card bg-base-200 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">🎯 Project Progress</h2>
            <%= if length(@project_stats) > 0 do %>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Project</th>
                      <th>Progress</th>
                      <th>Tasks</th>
                      <th>Completion %</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for project <- @project_stats do %>
                      <tr class="hover">
                        <td>
                          <a href={"/life/projects/#{project.project_id}"} class="flex items-center gap-2 link">
                            <span class="text-2xl"><%= project.emoji %></span>
                            <span class="font-medium"><%= project.project_name %></span>
                          </a>
                        </td>
                        <td class="w-1/3">
                          <div class="flex items-center gap-2">
                            <progress
                              class="progress progress-primary w-full"
                              value={project.completion_rate}
                              max="100"
                            ></progress>
                          </div>
                        </td>
                        <td>
                          <span class="text-sm">
                            <%= project.completed_count %>/<%= project.total_count %>
                          </span>
                        </td>
                        <td>
                          <span class={"badge " <> completion_badge_class(project.completion_rate)}>
                            <%= project.completion_rate %>%
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <p class="text-sm opacity-70">No projects yet. Create your first project to get started!</p>
            <% end %>
          </div>
        </div>

        <!-- Insights & Recommendations -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="card bg-info text-info-content shadow-xl">
            <div class="card-body">
              <h3 class="card-title">💡 Insights</h3>
              <ul class="text-sm space-y-2">
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
                  <li>🎯 Top performer: <%= top_project.emoji %> <%= top_project.project_name %> (<%= top_project.completion_rate %>%)</li>
                <% end %>
              </ul>
            </div>
          </div>

          <div class="card bg-success text-success-content shadow-xl">
            <div class="card-body">
              <h3 class="card-title">🎯 Recommendations</h3>
              <ul class="text-sm space-y-2">
                <%= if @insights.urgent_count > 5 do %>
                  <li>Focus on urgent tasks before adding new ones</li>
                <% end %>

                <%= if @insights.velocity < 3 do %>
                  <li>Aim to complete at least 3 tasks per week</li>
                <% end %>

                <li>Set aside time weekly for your weekly review</li>
                <li>Break down large tasks into smaller, actionable steps</li>
                <li>Celebrate your wins - you've completed <%= @insights.completed_tasks %> tasks!</li>
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
