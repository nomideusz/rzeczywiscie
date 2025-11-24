defmodule RzeczywiscieWeb.WeeklyReviewLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.LifePlanning

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    week_stats = LifePlanning.get_week_stats()
    this_week_review = LifePlanning.get_this_week_review()
    projects = LifePlanning.list_projects()
    recent_reviews = LifePlanning.list_weekly_reviews(8)

    socket =
      socket
      |> assign(:week_stats, week_stats)
      |> assign(:this_week_review, this_week_review)
      |> assign(:projects, projects)
      |> assign(:recent_reviews, recent_reviews)
      |> assign(:wins, this_week_review && this_week_review.wins || "")
      |> assign(:challenges, this_week_review && this_week_review.challenges || "")
      |> assign(:learnings, this_week_review && this_week_review.learnings || "")
      |> assign(:next_week_focus, this_week_review && this_week_review.next_week_focus || "")
      |> assign(:notes, this_week_review && this_week_review.notes || "")
      |> assign(:can_save, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <div class="container mx-auto p-4 max-w-6xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-4">
          <ul>
            <li><a href="/life">Dashboard</a></li>
            <li>Weekly Review</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-xl mb-6">
          <div class="card-body">
            <h1 class="text-4xl font-bold">
              📋 Weekly Review
            </h1>
            <p class="text-lg opacity-90">
              Week of <%= Calendar.strftime(@week_stats.week_start, "%B %d") %> - <%= Calendar.strftime(@week_stats.week_end, "%B %d, %Y") %>
            </p>
            <div class="mt-4">
              <div class="stats stats-horizontal shadow bg-white/20">
                <div class="stat">
                  <div class="stat-title text-white opacity-80">Tasks Completed</div>
                  <div class="stat-value text-white"><%= @week_stats.completed_tasks_count %></div>
                </div>
                <div class="stat">
                  <div class="stat-title text-white opacity-80">Active Projects</div>
                  <div class="stat-value text-white"><%= @week_stats.active_projects_count %></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Main Review Form (Left Column - 2/3 width) -->
          <div class="lg:col-span-2 space-y-6">
            <!-- Stalled Projects Alert -->
            <%= if length(@week_stats.stalled_projects) > 0 do %>
              <div class="alert alert-warning shadow-lg">
                <div class="w-full">
                  <div class="flex items-center gap-2 mb-2">
                    <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                    </svg>
                    <h3 class="font-bold">⚠️ Stalled Projects (<%= length(@week_stats.stalled_projects) %>)</h3>
                  </div>
                  <div class="text-sm">
                    These projects haven't had any completed tasks in 2+ weeks:
                  </div>
                  <ul class="list-disc list-inside mt-2 text-sm">
                    <%= for project <- @week_stats.stalled_projects do %>
                      <li>
                        <a href={"/life/projects/#{project.id}"} class="link">
                          <%= project.emoji %> <%= project.name %>
                        </a>
                      </li>
                    <% end %>
                  </ul>
                </div>
              </div>
            <% end %>

            <!-- Review Form -->
            <.form for={%{}} phx-change="update_review" phx-submit="save_review">
              <!-- Wins -->
              <div class="card bg-base-200 shadow-lg mb-6">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">🎉 Wins & Accomplishments</h2>
                  <div class="form-control">
                    <textarea
                      name="wins"
                      class="textarea textarea-bordered h-32"
                      placeholder="What went well this week? What are you proud of?"
                      phx-change="update_review"
                    ><%= @wins %></textarea>
                    <label class="label">
                      <span class="label-text-alt">Celebrate your progress, no matter how small!</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Challenges -->
              <div class="card bg-base-200 shadow-lg mb-6">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">🚧 Challenges & Blockers</h2>
                  <div class="form-control">
                    <textarea
                      name="challenges"
                      class="textarea textarea-bordered h-32"
                      placeholder="What obstacles did you face? What's blocking progress?"
                      phx-change="update_review"
                    ><%= @challenges %></textarea>
                    <label class="label">
                      <span class="label-text-alt">Identify problems to solve them</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Learnings -->
              <div class="card bg-base-200 shadow-lg mb-6">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">💡 Learnings & Insights</h2>
                  <div class="form-control">
                    <textarea
                      name="learnings"
                      class="textarea textarea-bordered h-32"
                      placeholder="What did you learn? Any insights or realizations?"
                      phx-change="update_review"
                    ><%= @learnings %></textarea>
                    <label class="label">
                      <span class="label-text-alt">Capture wisdom for future you</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Next Week Focus -->
              <div class="card bg-base-200 shadow-lg mb-6">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">🎯 Next Week's Focus</h2>
                  <div class="form-control">
                    <textarea
                      name="next_week_focus"
                      class="textarea textarea-bordered h-32"
                      placeholder="What are your top 3 goals for next week?"
                      phx-change="update_review"
                    ><%= @next_week_focus %></textarea>
                    <label class="label">
                      <span class="label-text-alt">Keep it focused - 3 goals max!</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Notes -->
              <div class="card bg-base-200 shadow-lg mb-6">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">📝 Additional Notes</h2>
                  <div class="form-control">
                    <textarea
                      name="notes"
                      class="textarea textarea-bordered h-24"
                      placeholder="Any other thoughts, ideas, or reflections?"
                      phx-change="update_review"
                    ><%= @notes %></textarea>
                  </div>
                </div>
              </div>

              <!-- Save Button -->
              <button
                type="submit"
                class={"btn btn-primary btn-lg btn-block " <> if(@can_save, do: "", else: "btn-disabled")}
                disabled={!@can_save}
              >
                <%= if @this_week_review, do: "Update Review", else: "Complete Review" %>
              </button>

              <%= if !@can_save do %>
                <div class="text-sm text-center mt-2 opacity-70">
                  Fill in at least one section to save your review
                </div>
              <% end %>
            </.form>
          </div>

          <!-- Sidebar (Right Column - 1/3 width) -->
          <div class="space-y-6">
            <!-- Active Projects This Week -->
            <div class="card bg-base-200 shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg">✅ Active This Week</h3>
                <%= if @week_stats.active_projects_count > 0 do %>
                  <ul class="space-y-2 mt-2">
                    <%= for project <- @projects do %>
                      <%= if project.id in @week_stats.active_project_ids do %>
                        <li>
                          <a href={"/life/projects/#{project.id}"} class="flex items-center gap-2 hover:underline">
                            <span class="text-2xl"><%= project.emoji || "📋" %></span>
                            <span><%= project.name %></span>
                          </a>
                        </li>
                      <% end %>
                    <% end %>
                  </ul>
                <% else %>
                  <p class="text-sm opacity-70">No tasks completed this week yet.</p>
                <% end %>
              </div>
            </div>

            <!-- Recent Reviews -->
            <div class="card bg-base-200 shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg">📚 Past Reviews</h3>
                <%= if length(@recent_reviews) > 0 do %>
                  <div class="space-y-2 mt-2">
                    <%= for review <- @recent_reviews do %>
                      <div class="p-2 bg-base-100 rounded text-sm">
                        <div class="font-bold">
                          <%= Calendar.strftime(review.week_start_date, "%b %d, %Y") %>
                        </div>
                        <%= if review.completed_tasks_count > 0 do %>
                          <div class="opacity-70">
                            ✅ <%= review.completed_tasks_count %> tasks
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <p class="text-sm opacity-70">No past reviews yet. This will be your first!</p>
                <% end %>
              </div>
            </div>

            <!-- Quick Tips -->
            <div class="card bg-primary text-primary-content shadow-lg">
              <div class="card-body">
                <h3 class="card-title text-lg">💡 Review Tips</h3>
                <ul class="text-sm space-y-2 mt-2">
                  <li>✓ Be honest about what worked and what didn't</li>
                  <li>✓ Celebrate small wins</li>
                  <li>✓ Identify patterns in blockers</li>
                  <li>✓ Limit next week to 3 key goals</li>
                  <li>✓ Do this weekly, same day/time</li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.app>
    """
  end

  @impl true
  def handle_event("update_review", params, socket) do
    wins = params["wins"] || ""
    challenges = params["challenges"] || ""
    learnings = params["learnings"] || ""
    next_week_focus = params["next_week_focus"] || ""
    notes = params["notes"] || ""

    # Can save if at least one field has content
    can_save =
      String.trim(wins) != "" ||
      String.trim(challenges) != "" ||
      String.trim(learnings) != "" ||
      String.trim(next_week_focus) != "" ||
      String.trim(notes) != ""

    {:noreply,
      socket
      |> assign(:wins, wins)
      |> assign(:challenges, challenges)
      |> assign(:learnings, learnings)
      |> assign(:next_week_focus, next_week_focus)
      |> assign(:notes, notes)
      |> assign(:can_save, can_save)
    }
  end

  @impl true
  def handle_event("save_review", params, socket) do
    review_params = %{
      "wins" => params["wins"],
      "challenges" => params["challenges"],
      "learnings" => params["learnings"],
      "next_week_focus" => params["next_week_focus"],
      "notes" => params["notes"],
      "completed_tasks_count" => socket.assigns.week_stats.completed_tasks_count,
      "projects_reviewed" => socket.assigns.week_stats.active_project_ids
    }

    case LifePlanning.upsert_this_week_review(review_params) do
      {:ok, review} ->
        {:noreply,
          socket
          |> assign(:this_week_review, review)
          |> assign(:recent_reviews, LifePlanning.list_weekly_reviews(8))
          |> put_flash(:info, "✅ Weekly review saved! Great job reflecting on your week.")
        }

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error saving review")}
    end
  end
end
