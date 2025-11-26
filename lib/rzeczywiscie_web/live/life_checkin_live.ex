defmodule RzeczywiscieWeb.LifeCheckinLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.LifePlanning

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    projects = LifePlanning.list_projects()
    today_checkin = LifePlanning.get_today_checkin()
    streak = LifePlanning.calculate_streak()

    # Get today's completed tasks
    completed_today =
      if today_checkin do
        today_checkin.completed_task_ids
        |> Enum.map(&LifePlanning.get_task!/1)
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    socket =
      socket
      |> assign(:projects, projects)
      |> assign(:today_checkin, today_checkin)
      |> assign(:completed_today, completed_today)
      |> assign(:tomorrow_focus, today_checkin && today_checkin.tomorrow_focus || "")
      |> assign(:tomorrow_project_id, today_checkin && today_checkin.tomorrow_project_id || nil)
      |> assign(:notes, today_checkin && today_checkin.notes || "")
      |> assign(:streak, streak)
      |> assign(:can_complete, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="container mx-auto px-2 sm:px-4 py-4 pb-20 sm:pb-4 max-w-4xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-3 sm:mb-4">
          <ul>
            <li><a href="/life" class="hover:underline">Dashboard</a></li>
            <li class="truncate max-w-[150px] sm:max-w-none">Daily Check-in</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-accent to-secondary text-accent-content shadow-xl mb-4 sm:mb-6 animate-in fade-in zoom-in duration-300">
          <div class="card-body p-4 sm:p-6">
            <h1 class="text-3xl sm:text-4xl font-bold flex items-center gap-2">
              <span class="text-4xl sm:text-5xl" aria-hidden="true">🌅</span>
              <span>Daily Check-in</span>
            </h1>
            <p class="text-base sm:text-lg opacity-90 mt-2">
              <%= Calendar.strftime(Date.utc_today(), "%A, %B %d, %Y") %>
            </p>

            <%= if @streak > 0 do %>
              <div class="mt-4">
                <div class="text-5xl sm:text-6xl font-bold text-center animate-pulse" aria-label={"Current streak: #{@streak} #{if @streak == 1, do: "day", else: "days"}"}>
                  🔥 <%= @streak %>
                </div>
                <div class="text-center text-lg sm:text-xl mt-2">
                  <%= if @streak == 1, do: "day", else: "days" %> streak!
                </div>
              </div>
            <% else %>
              <div class="alert alert-warning mt-4">
                <div class="w-full">
                  <span class="font-bold text-sm sm:text-base">Start your streak today!</span>
                  <div class="text-xs sm:text-sm">Complete your first check-in to begin building momentum.</div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Accomplishments Section -->
        <div class="card bg-base-200 shadow-xl mb-4 sm:mb-6 animate-in fade-in duration-400">
          <div class="card-body p-4 sm:p-6">
            <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
              <span class="text-2xl sm:text-3xl" aria-hidden="true">✅</span>
              <span class="text-base sm:text-xl">What did you accomplish today?</span>
            </h2>

            <%= if length(@completed_today) > 0 do %>
              <div class="space-y-2 mb-4">
                <%= for task <- @completed_today do %>
                  <div class="flex items-start gap-2 sm:gap-3 p-3 bg-success/20 rounded-lg">
                    <span class="text-xl sm:text-2xl shrink-0" aria-hidden="true">✅</span>
                    <div class="flex-1 min-w-0">
                      <div class="font-medium text-sm sm:text-base break-words"><%= task.title %></div>
                      <div class="text-xs sm:text-sm opacity-70 truncate">
                        Project: <%= get_project_name(task.project_id, @projects) %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="alert">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-5 h-5 sm:w-6 sm:h-6" aria-hidden="true">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <span class="text-xs sm:text-sm">No tasks completed yet today. Go to your projects and check off some tasks!</span>
              </div>
            <% end %>

            <div class="flex gap-2 mt-4">
              <a href="/life" class="btn btn-primary btn-sm sm:btn-md" aria-label="Go to projects page">
                Go to Projects
              </a>
            </div>
          </div>
        </div>

        <!-- Tomorrow's Focus Section -->
        <div class="card bg-base-200 shadow-xl mb-4 sm:mb-6 animate-in fade-in duration-500">
          <div class="card-body p-4 sm:p-6">
            <h2 class="card-title text-xl sm:text-2xl mb-3 sm:mb-4 flex items-center gap-2">
              <span class="text-2xl sm:text-3xl" aria-hidden="true">⭐</span>
              <span class="text-base sm:text-xl">What's your ONE focus for tomorrow?</span>
            </h2>

            <.form for={%{}} phx-change="update_focus" phx-submit="save_checkin">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium text-sm sm:text-base">Choose a project</span>
                </label>
                <select
                  name="tomorrow_project_id"
                  class="select select-bordered select-lg sm:select-md text-base"
                  required
                  phx-change="update_focus"
                  aria-label="Select project for tomorrow's focus"
                >
                  <option value="">Select a project...</option>
                  <%= for project <- @projects do %>
                    <option value={project.id} selected={@tomorrow_project_id == project.id}>
                      <%= project.emoji %> <%= project.name %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium text-sm sm:text-base">Next action</span>
                </label>
                <textarea
                  name="tomorrow_focus"
                  class="textarea textarea-bordered textarea-lg sm:textarea-md h-24 text-base"
                  placeholder="What specific task will you focus on tomorrow?"
                  required
                  phx-change="update_focus"
                  aria-label="Tomorrow's focus task"
                ><%= @tomorrow_focus %></textarea>
                <label class="label">
                  <span class="label-text-alt text-xs sm:text-sm">Be specific! "Clean the living room" not just "work on apartment"</span>
                </label>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium text-sm sm:text-base">Notes (optional)</span>
                </label>
                <textarea
                  name="notes"
                  class="textarea textarea-bordered textarea-lg sm:textarea-md h-24 text-base"
                  placeholder="Any thoughts, blockers, or reflections about your progress?"
                  phx-change="update_focus"
                  aria-label="Daily notes and reflections"
                ><%= @notes %></textarea>
              </div>

              <!-- Desktop Save Button (Hidden on Mobile - FAB used instead) -->
              <button
                type="submit"
                class={"hidden sm:flex btn btn-primary btn-lg btn-block transition-all " <> if(@can_complete, do: "hover:shadow-xl active:scale-[0.98]", else: "btn-disabled")}
                disabled={!@can_complete}
                aria-label={if @today_checkin, do: "Update daily check-in", else: "Complete daily check-in"}
              >
                <%= if @today_checkin, do: "Update Check-in", else: "Complete Check-in" %>
              </button>

              <%= if !@can_complete do %>
                <div class="hidden sm:block text-sm text-center mt-2 opacity-70">
                  Please select a project and describe your focus to continue
                </div>
              <% end %>
            </.form>
          </div>
        </div>

        <!-- Recent Check-ins -->
        <div class="card bg-base-200 shadow-xl animate-in fade-in duration-600">
          <div class="card-body p-4 sm:p-6">
            <h2 class="card-title text-lg sm:text-xl mb-3 sm:mb-4 flex items-center gap-2">
              <span class="text-xl sm:text-2xl" aria-hidden="true">📅</span>
              <span>Recent Check-ins</span>
            </h2>

            <% recent_checkins = LifePlanning.list_checkins(7) %>

            <%= if length(recent_checkins) > 0 do %>
              <div class="space-y-2 sm:space-y-3">
                <%= for checkin <- recent_checkins do %>
                  <div class="p-3 bg-base-100 rounded-lg">
                    <div class="font-bold text-sm sm:text-base"><%= Calendar.strftime(checkin.date, "%A, %b %d") %></div>

                    <%= if checkin.tomorrow_focus do %>
                      <div class="text-xs sm:text-sm mt-1">
                        <span class="opacity-70">Focus:</span>
                        <%= checkin.tomorrow_focus %>
                      </div>
                    <% end %>

                    <%= if checkin.completed_task_ids && length(checkin.completed_task_ids) > 0 do %>
                      <div class="text-xs sm:text-sm mt-1 opacity-70">
                        ✅ <%= length(checkin.completed_task_ids) %> <%= if length(checkin.completed_task_ids) == 1, do: "task", else: "tasks" %> completed
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="alert">
                <span class="text-xs sm:text-sm">No previous check-ins yet. This will be your first!</span>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Floating Action Button (Mobile Only) -->
        <button
          type="submit"
          form="phx-form-"
          class={"fixed bottom-6 right-6 btn btn-primary btn-circle btn-lg shadow-2xl sm:hidden z-50 animate-in zoom-in duration-300 " <> if(@can_complete, do: "active:scale-90", else: "btn-disabled opacity-50")}
          disabled={!@can_complete}
          aria-label={if @today_checkin, do: "Save daily check-in", else: "Complete daily check-in"}
          phx-click="save_checkin_fab"
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
  def handle_event("update_focus", params, socket) do
    tomorrow_project_id = params["tomorrow_project_id"]
    tomorrow_focus = params["tomorrow_focus"] || ""
    notes = params["notes"] || ""

    can_complete =
      tomorrow_project_id != "" && tomorrow_project_id != nil &&
      String.trim(tomorrow_focus) != ""

    {:noreply,
      socket
      |> assign(:tomorrow_project_id, if(tomorrow_project_id == "", do: nil, else: tomorrow_project_id))
      |> assign(:tomorrow_focus, tomorrow_focus)
      |> assign(:notes, notes)
      |> assign(:can_complete, can_complete)
    }
  end

  @impl true
  def handle_event("save_checkin", params, socket) do
    # Collect today's completed task IDs
    completed_task_ids =
      socket.assigns.projects
      |> Enum.flat_map(fn project ->
        LifePlanning.list_tasks(project.id)
      end)
      |> Enum.filter(fn task ->
        task.completed && task.completed_at &&
        Date.compare(DateTime.to_date(task.completed_at), Date.utc_today()) == :eq
      end)
      |> Enum.map(& &1.id)

    checkin_params = %{
      "date" => Date.utc_today(),
      "tomorrow_project_id" => params["tomorrow_project_id"],
      "tomorrow_focus" => params["tomorrow_focus"],
      "notes" => params["notes"],
      "completed_task_ids" => completed_task_ids
    }

    case LifePlanning.upsert_today_checkin(checkin_params) do
      {:ok, checkin} ->
        {:noreply,
          socket
          |> assign(:today_checkin, checkin)
          |> assign(:streak, LifePlanning.calculate_streak())
          |> put_flash(:info, "✅ Check-in saved! See you tomorrow!")
        }

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error saving check-in")}
    end
  end

  @impl true
  def handle_event("save_checkin_fab", _params, socket) do
    # FAB uses current assigns instead of form params
    completed_task_ids =
      socket.assigns.projects
      |> Enum.flat_map(fn project ->
        LifePlanning.list_tasks(project.id)
      end)
      |> Enum.filter(fn task ->
        task.completed && task.completed_at &&
        Date.compare(DateTime.to_date(task.completed_at), Date.utc_today()) == :eq
      end)
      |> Enum.map(& &1.id)

    checkin_params = %{
      "date" => Date.utc_today(),
      "tomorrow_project_id" => socket.assigns.tomorrow_project_id,
      "tomorrow_focus" => socket.assigns.tomorrow_focus,
      "notes" => socket.assigns.notes,
      "completed_task_ids" => completed_task_ids
    }

    case LifePlanning.upsert_today_checkin(checkin_params) do
      {:ok, checkin} ->
        {:noreply,
          socket
          |> assign(:today_checkin, checkin)
          |> assign(:streak, LifePlanning.calculate_streak())
          |> put_flash(:info, "✅ Check-in saved! See you tomorrow!")
        }

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error saving check-in")}
    end
  end

  # Private helpers

  defp get_project_name(project_id, projects) do
    case Enum.find(projects, &(&1.id == project_id)) do
      nil -> "Unknown"
      project -> project.name
    end
  end
end
