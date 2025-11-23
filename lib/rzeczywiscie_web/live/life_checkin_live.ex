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
    <.app flash={@flash}>
      <div class="container mx-auto p-4 max-w-4xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-4">
          <ul>
            <li><a href="/life">Dashboard</a></li>
            <li>Daily Check-in</li>
          </ul>
        </div>

        <!-- Header Card -->
        <div class="card bg-gradient-to-r from-accent to-secondary text-accent-content shadow-xl mb-6">
          <div class="card-body">
            <h1 class="text-4xl font-bold">
              🌅 Daily Check-in
            </h1>
            <p class="text-lg opacity-90">
              <%= Calendar.strftime(Date.utc_today(), "%A, %B %d, %Y") %>
            </p>

            <%= if @streak > 0 do %>
              <div class="mt-4">
                <div class="text-6xl font-bold text-center animate-pulse">
                  🔥 <%= @streak %>
                </div>
                <div class="text-center text-xl mt-2">
                  <%= if @streak == 1, do: "day", else: "days" %> streak!
                </div>
              </div>
            <% else %>
              <div class="alert alert-warning mt-4">
                <div>
                  <span class="font-bold">Start your streak today!</span>
                  <div class="text-sm">Complete your first check-in to begin building momentum.</div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Accomplishments Section -->
        <div class="card bg-base-200 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">
              ✅ What did you accomplish today?
            </h2>

            <%= if length(@completed_today) > 0 do %>
              <div class="space-y-2 mb-4">
                <%= for task <- @completed_today do %>
                  <div class="flex items-center gap-3 p-3 bg-success/20 rounded-lg">
                    <span class="text-2xl">✅</span>
                    <div class="flex-1">
                      <div class="font-medium"><%= task.title %></div>
                      <div class="text-sm opacity-70">
                        Project: <%= get_project_name(task.project_id, @projects) %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="alert">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <span>No tasks completed yet today. Go to your projects and check off some tasks!</span>
              </div>
            <% end %>

            <div class="flex gap-2 mt-4">
              <a href="/life" class="btn btn-primary">
                Go to Projects
              </a>
            </div>
          </div>
        </div>

        <!-- Tomorrow's Focus Section -->
        <div class="card bg-base-200 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">
              ⭐ What's your ONE focus for tomorrow?
            </h2>

            <.form for={%{}} phx-change="update_focus" phx-submit="save_checkin">
              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Choose a project</span>
                </label>
                <select
                  name="tomorrow_project_id"
                  class="select select-bordered"
                  required
                  phx-change="update_focus"
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
                  <span class="label-text font-medium">Next action</span>
                </label>
                <textarea
                  name="tomorrow_focus"
                  class="textarea textarea-bordered h-24"
                  placeholder="What specific task will you focus on tomorrow?"
                  required
                  phx-change="update_focus"
                ><%= @tomorrow_focus %></textarea>
                <label class="label">
                  <span class="label-text-alt">Be specific! "Clean the living room" not just "work on apartment"</span>
                </label>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text font-medium">Notes (optional)</span>
                </label>
                <textarea
                  name="notes"
                  class="textarea textarea-bordered h-24"
                  placeholder="Any thoughts, blockers, or reflections about your progress?"
                  phx-change="update_focus"
                ><%= @notes %></textarea>
              </div>

              <button
                type="submit"
                class={"btn btn-primary btn-lg btn-block " <> if(@can_complete, do: "", else: "btn-disabled")}
                disabled={!@can_complete}
              >
                <%= if @today_checkin, do: "Update Check-in", else: "Complete Check-in" %>
              </button>

              <%= if !@can_complete do %>
                <div class="text-sm text-center mt-2 opacity-70">
                  Please select a project and describe your focus to continue
                </div>
              <% end %>
            </.form>
          </div>
        </div>

        <!-- Recent Check-ins -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4">
              📅 Recent Check-ins
            </h2>

            <% recent_checkins = LifePlanning.list_checkins(7) %>

            <%= if length(recent_checkins) > 0 do %>
              <div class="space-y-3">
                <%= for checkin <- recent_checkins do %>
                  <div class="p-3 bg-base-100 rounded-lg">
                    <div class="font-bold"><%= Calendar.strftime(checkin.date, "%A, %b %d") %></div>

                    <%= if checkin.tomorrow_focus do %>
                      <div class="text-sm mt-1">
                        <span class="opacity-70">Focus:</span>
                        <%= checkin.tomorrow_focus %>
                      </div>
                    <% end %>

                    <%= if checkin.completed_task_ids && length(checkin.completed_task_ids) > 0 do %>
                      <div class="text-sm mt-1 opacity-70">
                        ✅ <%= length(checkin.completed_task_ids) %> <%= if length(checkin.completed_task_ids) == 1, do: "task", else: "tasks" %> completed
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="alert">
                <span>No previous check-ins yet. This will be your first!</span>
              </div>
            <% end %>
          </div>
        </div>
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

  # Private helpers

  defp get_project_name(project_id, projects) do
    case Enum.find(projects, &(&1.id == project_id)) do
      nil -> "Unknown"
      project -> project.name
    end
  end
end
