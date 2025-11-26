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
    <.app flash={@flash} current_path={@current_path}>
      <div class="container mx-auto px-2 sm:px-4 py-4 pb-20 sm:pb-4 max-w-6xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-3 sm:mb-4">
          <ul>
            <li><a href="/life" class="hover:underline">Dashboard</a></li>
            <li class="truncate max-w-[150px] sm:max-w-none">Weekly Review</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-purple-500 to-pink-500 text-white shadow-xl mb-4 sm:mb-6 animate-in fade-in zoom-in duration-300">
          <div class="card-body p-4 sm:p-6">
            <h1 class="text-3xl sm:text-4xl font-bold flex items-center gap-2">
              <span class="text-4xl sm:text-5xl" aria-hidden="true">📋</span>
              <span>Weekly Review</span>
            </h1>
            <p class="text-base sm:text-lg opacity-90 mt-2">
              Week of <%= Calendar.strftime(@week_stats.week_start, "%B %d") %> - <%= Calendar.strftime(@week_stats.week_end, "%B %d, %Y") %>
            </p>
            <!-- Responsive Stats -->
            <div class="mt-4">
              <div class="grid grid-cols-2 gap-2 sm:stats sm:stats-horizontal shadow bg-white/20 rounded-lg">
                <div class="stat bg-white/10 sm:bg-transparent rounded-lg p-3 sm:p-4">
                  <div class="stat-title text-white opacity-80 text-xs sm:text-sm">Tasks Completed</div>
                  <div class="stat-value text-white text-2xl sm:text-3xl"><%= @week_stats.completed_tasks_count %></div>
                </div>
                <div class="stat bg-white/10 sm:bg-transparent rounded-lg p-3 sm:p-4">
                  <div class="stat-title text-white opacity-80 text-xs sm:text-sm">Active Projects</div>
                  <div class="stat-value text-white text-2xl sm:text-3xl"><%= @week_stats.active_projects_count %></div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
          <!-- Main Review Form (Left Column - 2/3 width) -->
          <div class="lg:col-span-2 space-y-4 sm:space-y-6">
            <!-- Stalled Projects Alert -->
            <%= if length(@week_stats.stalled_projects) > 0 do %>
              <div class="alert alert-warning shadow-lg animate-in fade-in duration-500">
                <div class="w-full">
                  <div class="flex items-center gap-2 mb-2">
                    <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-5 w-5 sm:h-6 sm:w-6" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                    </svg>
                    <h3 class="font-bold text-sm sm:text-base">⚠️ Stalled Projects (<%= length(@week_stats.stalled_projects) %>)</h3>
                  </div>
                  <div class="text-xs sm:text-sm">
                    These projects haven't had any completed tasks in 2+ weeks:
                  </div>
                  <ul class="list-disc list-inside mt-2 text-xs sm:text-sm space-y-1">
                    <%= for project <- @week_stats.stalled_projects do %>
                      <li>
                        <a href={"/life/projects/#{project.id}"} class="link hover:underline">
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
              <div class="card bg-base-200 shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-300">
                <div class="card-body p-4 sm:p-6">
                  <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                    <span class="text-2xl sm:text-3xl" aria-hidden="true">🎉</span>
                    <span>Wins & Accomplishments</span>
                  </h2>
                  <div class="form-control">
                    <textarea
                      name="wins"
                      class="textarea textarea-bordered textarea-lg sm:textarea-md h-32 text-base"
                      placeholder="What went well this week? What are you proud of?"
                      phx-change="update_review"
                      aria-label="Weekly wins and accomplishments"
                    ><%= @wins %></textarea>
                    <label class="label">
                      <span class="label-text-alt text-xs sm:text-sm">Celebrate your progress, no matter how small!</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Challenges -->
              <div class="card bg-base-200 shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-400">
                <div class="card-body p-4 sm:p-6">
                  <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                    <span class="text-2xl sm:text-3xl" aria-hidden="true">🚧</span>
                    <span>Challenges & Blockers</span>
                  </h2>
                  <div class="form-control">
                    <textarea
                      name="challenges"
                      class="textarea textarea-bordered textarea-lg sm:textarea-md h-32 text-base"
                      placeholder="What obstacles did you face? What's blocking progress?"
                      phx-change="update_review"
                      aria-label="Weekly challenges and blockers"
                    ><%= @challenges %></textarea>
                    <label class="label">
                      <span class="label-text-alt text-xs sm:text-sm">Identify problems to solve them</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Learnings -->
              <div class="card bg-base-200 shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-500">
                <div class="card-body p-4 sm:p-6">
                  <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                    <span class="text-2xl sm:text-3xl" aria-hidden="true">💡</span>
                    <span>Learnings & Insights</span>
                  </h2>
                  <div class="form-control">
                    <textarea
                      name="learnings"
                      class="textarea textarea-bordered textarea-lg sm:textarea-md h-32 text-base"
                      placeholder="What did you learn? Any insights or realizations?"
                      phx-change="update_review"
                      aria-label="Weekly learnings and insights"
                    ><%= @learnings %></textarea>
                    <label class="label">
                      <span class="label-text-alt text-xs sm:text-sm">Capture wisdom for future you</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Next Week Focus -->
              <div class="card bg-base-200 shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-600">
                <div class="card-body p-4 sm:p-6">
                  <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                    <span class="text-2xl sm:text-3xl" aria-hidden="true">🎯</span>
                    <span>Next Week's Focus</span>
                  </h2>
                  <div class="form-control">
                    <textarea
                      name="next_week_focus"
                      class="textarea textarea-bordered textarea-lg sm:textarea-md h-32 text-base"
                      placeholder="What are your top 3 goals for next week?"
                      phx-change="update_review"
                      aria-label="Next week's focus and goals"
                    ><%= @next_week_focus %></textarea>
                    <label class="label">
                      <span class="label-text-alt text-xs sm:text-sm">Keep it focused - 3 goals max!</span>
                    </label>
                  </div>
                </div>
              </div>

              <!-- Notes -->
              <div class="card bg-base-200 shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-700">
                <div class="card-body p-4 sm:p-6">
                  <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
                    <span class="text-2xl sm:text-3xl" aria-hidden="true">📝</span>
                    <span>Additional Notes</span>
                  </h2>
                  <div class="form-control">
                    <textarea
                      name="notes"
                      class="textarea textarea-bordered textarea-lg sm:textarea-md h-24 text-base"
                      placeholder="Any other thoughts, ideas, or reflections?"
                      phx-change="update_review"
                      aria-label="Additional notes and reflections"
                    ><%= @notes %></textarea>
                  </div>
                </div>
              </div>

              <!-- Save Button (Hidden on Mobile - FAB used instead) -->
              <button
                type="submit"
                class={"hidden sm:flex btn btn-primary btn-lg btn-block transition-all " <> if(@can_save, do: "hover:shadow-xl active:scale-[0.98]", else: "btn-disabled")}
                disabled={!@can_save}
                aria-label={if @this_week_review, do: "Update weekly review", else: "Complete weekly review"}
              >
                <%= if @this_week_review, do: "Update Review", else: "Complete Review" %>
              </button>

              <%= if !@can_save do %>
                <div class="hidden sm:block text-sm text-center mt-2 opacity-70">
                  Fill in at least one section to save your review
                </div>
              <% end %>
            </.form>
          </div>

          <!-- Sidebar (Right Column - 1/3 width) -->
          <div class="space-y-4 sm:space-y-6">
            <!-- Active Projects This Week -->
            <div class="card bg-base-200 shadow-lg animate-in fade-in duration-500">
              <div class="card-body p-4 sm:p-6">
                <h3 class="card-title text-base sm:text-lg flex items-center gap-2">
                  <span aria-hidden="true">✅</span>
                  <span>Active This Week</span>
                </h3>
                <%= if @week_stats.active_projects_count > 0 do %>
                  <ul class="space-y-2 mt-2">
                    <%= for project <- @projects do %>
                      <%= if project.id in @week_stats.active_project_ids do %>
                        <li>
                          <a href={"/life/projects/#{project.id}"} class="flex items-center gap-2 hover:underline text-sm sm:text-base">
                            <span class="text-xl sm:text-2xl"><%= project.emoji || "📋" %></span>
                            <span class="truncate"><%= project.name %></span>
                          </a>
                        </li>
                      <% end %>
                    <% end %>
                  </ul>
                <% else %>
                  <p class="text-xs sm:text-sm opacity-70">No tasks completed this week yet.</p>
                <% end %>
              </div>
            </div>

            <!-- Recent Reviews -->
            <div class="card bg-base-200 shadow-lg animate-in fade-in duration-600">
              <div class="card-body p-4 sm:p-6">
                <h3 class="card-title text-base sm:text-lg flex items-center gap-2">
                  <span aria-hidden="true">📚</span>
                  <span>Past Reviews</span>
                </h3>
                <%= if length(@recent_reviews) > 0 do %>
                  <div class="space-y-2 mt-2">
                    <%= for review <- @recent_reviews do %>
                      <div class="p-2 bg-base-100 rounded text-xs sm:text-sm">
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
                  <p class="text-xs sm:text-sm opacity-70">No past reviews yet. This will be your first!</p>
                <% end %>
              </div>
            </div>

            <!-- Quick Tips -->
            <div class="card bg-primary text-primary-content shadow-lg animate-in fade-in duration-700">
              <div class="card-body p-4 sm:p-6">
                <h3 class="card-title text-base sm:text-lg flex items-center gap-2">
                  <span aria-hidden="true">💡</span>
                  <span>Review Tips</span>
                </h3>
                <ul class="text-xs sm:text-sm space-y-2 mt-2">
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

        <!-- Floating Action Button (Mobile Only) -->
        <button
          type="submit"
          form="phx-form-"
          class={"fixed bottom-6 right-6 btn btn-primary btn-circle btn-lg shadow-2xl sm:hidden z-50 animate-in zoom-in duration-300 " <> if(@can_save, do: "active:scale-90", else: "btn-disabled opacity-50")}
          disabled={!@can_save}
          aria-label={if @this_week_review, do: "Save weekly review", else: "Complete weekly review"}
          phx-click="save_review_fab"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </button>
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

  @impl true
  def handle_event("save_review_fab", _params, socket) do
    # FAB uses current assigns instead of form params
    review_params = %{
      "wins" => socket.assigns.wins,
      "challenges" => socket.assigns.challenges,
      "learnings" => socket.assigns.learnings,
      "next_week_focus" => socket.assigns.next_week_focus,
      "notes" => socket.assigns.notes,
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
