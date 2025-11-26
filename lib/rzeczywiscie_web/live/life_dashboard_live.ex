defmodule RzeczywiscieWeb.LifeDashboardLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.LifePlanning

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      LifePlanning.subscribe()
    end

    socket =
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
      |> assign(:streak, LifePlanning.calculate_streak())
      |> assign(:urgent_tasks, LifePlanning.get_urgent_tasks())
      |> assign(:show_project_modal, false)
      |> assign(:editing_project, nil)
      |> assign(:project_form, to_form(%{}, as: "project"))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="container mx-auto px-2 sm:px-4 py-4 max-w-6xl pb-20 sm:pb-4">
        <!-- Header -->
        <div class="mb-6 sm:mb-8">
          <h1 class="text-3xl sm:text-4xl font-bold mb-2">Life Reboot Tracker</h1>
          <p class="text-base sm:text-lg opacity-70">Take control of your life, one step at a time</p>
        </div>

        <!-- Overall Progress Card -->
        <div class="card bg-gradient-to-r from-primary to-secondary text-primary-content shadow-xl mb-4 sm:mb-6 transition-all duration-300 hover:shadow-2xl">
          <div class="card-body p-4 sm:p-6">
            <h2 class="card-title text-xl sm:text-2xl">Your Progress</h2>
            <div class="flex flex-col lg:flex-row items-stretch lg:items-center gap-4 sm:gap-6 mt-4">
              <div class="flex-1">
                <div class="text-sm opacity-90 mb-2">Overall Completion</div>
                <progress
                  class="progress progress-primary-content w-full h-5 sm:h-6"
                  value={@overall_progress.progress}
                  max="100"
                  aria-label={"Progress: #{Float.round(@overall_progress.progress, 1)}%"}
                ></progress>
                <div class="text-lg font-bold mt-1"><%= Float.round(@overall_progress.progress, 1) %>%</div>
              </div>
              <div class="grid grid-cols-3 gap-2 lg:stats lg:stats-horizontal shadow">
                <div class="stat bg-base-100/10 rounded-lg p-3 lg:bg-transparent">
                  <div class="stat-title text-primary-content opacity-80 text-xs sm:text-sm">Completed</div>
                  <div class="stat-value text-primary-content text-2xl sm:text-3xl"><%= @overall_progress.completed_tasks %></div>
                </div>
                <div class="stat bg-base-100/10 rounded-lg p-3 lg:bg-transparent">
                  <div class="stat-title text-primary-content opacity-80 text-xs sm:text-sm">Total</div>
                  <div class="stat-value text-primary-content text-2xl sm:text-3xl"><%= @overall_progress.total_tasks %></div>
                </div>
                <div class="stat bg-base-100/10 rounded-lg p-3 lg:bg-transparent">
                  <div class="stat-title text-primary-content opacity-80 text-xs sm:text-sm">Streak</div>
                  <div class="stat-value text-primary-content text-2xl sm:text-3xl">
                    <%= if @streak > 0 do %>
                      🔥 <%= @streak %>
                    <% else %>
                      -
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Urgent Tasks Section -->
        <%= if length(@urgent_tasks) > 0 do %>
          <div class="alert alert-warning shadow-lg mb-4 sm:mb-6 animate-in fade-in duration-500">
            <div class="w-full">
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-5 w-5 sm:h-6 sm:w-6" fill="none" viewBox="0 0 24 24" aria-hidden="true">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                  <h3 class="font-bold text-base sm:text-lg">⏰ Urgent (<%= length(@urgent_tasks) %>)</h3>
                </div>
              </div>
              <div class="space-y-2">
                <%= for task <- Enum.take(@urgent_tasks, 5) do %>
                  <% urgency = Rzeczywiscie.LifePlanning.Task.urgency_level(task) %>
                  <% project = Enum.find(@projects, fn p -> p.id == task.project_id end) %>
                  <div class="flex flex-col sm:flex-row sm:items-center justify-between p-3 bg-base-100 rounded-lg gap-2 min-h-[60px] transition-all hover:shadow-md">
                    <div class="flex-1 min-w-0">
                      <div class="font-medium truncate"><%= task.title %></div>
                      <div class="text-xs sm:text-sm opacity-70 truncate">
                        <%= if project, do: "#{project.emoji} #{project.name}", else: "Unknown Project" %>
                      </div>
                    </div>
                    <div class="flex items-center gap-2 flex-shrink-0">
                      <div class={"badge badge-sm whitespace-nowrap " <> Rzeczywiscie.LifePlanning.Task.urgency_badge_class(urgency)}>
                        <%= Rzeczywiscie.LifePlanning.Task.urgency_text(urgency) %>
                      </div>
                      <%= if task.deadline do %>
                        <div class="text-xs sm:text-sm opacity-70 hidden sm:block">
                          📅 <%= Calendar.strftime(task.deadline, "%b %d") %>
                        </div>
                      <% end %>
                      <a href={"/life/projects/#{task.project_id}"} class="btn btn-xs sm:btn-sm btn-ghost" aria-label={"View task: #{task.title}"}>View</a>
                    </div>
                  </div>
                <% end %>
                <%= if length(@urgent_tasks) > 5 do %>
                  <div class="text-xs sm:text-sm opacity-70 text-center mt-2">
                    + <%= length(@urgent_tasks) - 5 %> more urgent tasks
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Navigation -->
        <div class="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-3 mb-4 sm:mb-6">
          <!-- Horizontal scrollable tabs on mobile -->
          <div class="tabs tabs-boxed overflow-x-auto flex-nowrap whitespace-nowrap scrollbar-hide">
            <a href="/life" class="tab tab-active" aria-current="page">Dashboard</a>
            <a href="/life/check-in" class="tab">Check-in</a>
            <a href="/life/weekly-review" class="tab">Review</a>
            <a href="/life/progress" class="tab">Analytics</a>
          </div>
          <!-- Desktop button -->
          <button
            class="btn btn-primary hidden sm:inline-flex"
            phx-click="show_new_project_modal"
            aria-label="Add new project"
          >
            + Add Project
          </button>
        </div>

        <!-- Projects Grid -->
        <div class="grid grid-cols-1 gap-4 sm:gap-6">
          <%= for project <- @projects do %>
            <% stats = get_project_stats(project.id) %>
            <% next_action = LifePlanning.get_next_action(project.id) %>

            <div class="card bg-base-200 shadow-lg hover:shadow-2xl transition-all duration-300 cursor-pointer active:scale-[0.98]"
                 phx-click="navigate_to_project"
                 phx-value-id={project.id}
                 role="button"
                 tabindex="0"
                 aria-label={"View project: #{project.name}"}>
              <div class="card-body p-4 sm:p-6">
                <div class="flex justify-between items-start gap-3">
                  <div class="flex-1 min-w-0">
                    <h2 class="card-title text-xl sm:text-2xl break-words">
                      <span class="text-2xl sm:text-3xl mr-2 flex-shrink-0" aria-hidden="true"><%= project.emoji || "📋" %></span>
                      <span class="break-words"><%= project.name %></span>
                    </h2>

                    <!-- Timeline -->
                    <%= if project.timeline_months do %>
                      <div class="text-xs sm:text-sm opacity-70 mt-1">
                        Timeline: ~<%= project.timeline_months %> <%= if project.timeline_months == 1, do: "month", else: "months" %>
                      </div>
                    <% end %>

                    <!-- Progress Bar -->
                    <div class="mt-3 sm:mt-4">
                      <div class="flex justify-between text-xs sm:text-sm mb-1">
                        <span class="opacity-70">Progress</span>
                        <span class="font-bold"><%= Float.round(stats.progress, 1) %>%</span>
                      </div>
                      <progress
                        class="progress progress-primary w-full h-3 sm:h-4"
                        value={stats.progress}
                        max="100"
                        style={"background-color: #{project.color}40;"}
                        aria-valuenow={stats.progress}
                        aria-valuemin="0"
                        aria-valuemax="100"
                      ></progress>
                      <div class="text-xs sm:text-sm opacity-70 mt-1">
                        ✅ <%= stats.completed %>/<%= stats.total %> tasks done
                      </div>
                    </div>

                    <!-- Next Action -->
                    <%= if next_action do %>
                      <div class="alert alert-info mt-3 sm:mt-4 py-2 sm:py-3">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-4 h-4 sm:w-5 sm:h-5" aria-hidden="true">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                        <div class="min-w-0 flex-1">
                          <div class="text-xs opacity-70">Next Action</div>
                          <div class="font-bold text-sm break-words"><%= next_action.title %></div>
                        </div>
                      </div>
                    <% else %>
                      <%= if stats.total > 0 && stats.completed < stats.total do %>
                        <div class="alert alert-warning mt-3 sm:mt-4 py-2 sm:py-3">
                          <div>
                            <div class="text-xs">⚠️ No next action set</div>
                            <div class="text-xs sm:text-sm">Tap to mark a task as your focus</div>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  </div>

                  <!-- Actions -->
                  <div class="dropdown dropdown-end flex-shrink-0">
                    <label tabindex="0" class="btn btn-ghost btn-sm btn-circle" onclick="event.stopPropagation()" aria-label="Project options">
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="w-5 h-5 stroke-current">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"></path>
                      </svg>
                    </label>
                    <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-52" onclick="event.stopPropagation()">
                      <li><a phx-click="edit_project" phx-value-id={project.id} onclick="event.stopPropagation()" class="active:bg-primary">✏️ Edit</a></li>
                      <li><a phx-click="archive_project" phx-value-id={project.id} onclick="event.stopPropagation()" class="active:bg-primary">📦 Archive</a></li>
                      <li><a phx-click="delete_project" phx-value-id={project.id} onclick="event.stopPropagation()" class="text-error active:bg-error active:text-error-content">🗑️ Delete</a></li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if length(@projects) == 0 do %>
            <div class="flex flex-col items-center justify-center py-12 px-4 text-center animate-in fade-in duration-700">
              <div class="text-6xl mb-4 animate-bounce">🚀</div>
              <h3 class="text-2xl font-bold mb-2">Ready to Start Your Journey?</h3>
              <p class="text-base opacity-70 mb-6 max-w-md">
                Create your first project and take the first step toward your goals!
              </p>
              <button
                class="btn btn-primary btn-lg"
                phx-click="show_new_project_modal"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                Create Your First Project
              </button>
            </div>
          <% end %>
        </div>

        <!-- Floating Action Button (Mobile Only) -->
        <button
          class="fixed bottom-6 right-6 btn btn-primary btn-circle btn-lg shadow-2xl sm:hidden z-50 animate-in zoom-in duration-300"
          phx-click="show_new_project_modal"
          aria-label="Add new project"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
        </button>

        <!-- Project Modal -->
        <%= if @show_project_modal do %>
          <div class="modal modal-open animate-in fade-in zoom-in duration-200">
            <div class="modal-box max-w-md w-full mx-4">
              <h3 class="font-bold text-xl mb-4 flex items-center gap-2">
                <span class="text-2xl" aria-hidden="true"><%= if @editing_project, do: "✏️", else: "➕" %></span>
                <%= if @editing_project, do: "Edit Project", else: "New Project" %>
              </h3>

              <.form for={@project_form} phx-submit="save_project">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Name</span>
                    <span class="label-text-alt text-error">Required</span>
                  </label>
                  <input
                    type="text"
                    name="project[name]"
                    class="input input-bordered input-lg sm:input-md"
                    placeholder="e.g., Get My Dream Apartment"
                    required
                    autofocus
                    value={@editing_project && @editing_project.name}
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Emoji</span>
                    <span class="label-text-alt opacity-70">Optional</span>
                  </label>
                  <input
                    type="text"
                    name="project[emoji]"
                    class="input input-bordered input-lg sm:input-md"
                    placeholder="🏠"
                    maxlength="4"
                    value={@editing_project && @editing_project.emoji}
                  />
                  <label class="label">
                    <span class="label-text-alt">Tip: Use any emoji to personalize!</span>
                  </label>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Timeline</span>
                    <span class="label-text-alt opacity-70">Optional</span>
                  </label>
                  <div class="join w-full">
                    <input
                      type="number"
                      name="project[timeline_months]"
                      class="input input-bordered input-lg sm:input-md join-item flex-1"
                      placeholder="3"
                      min="1"
                      max="120"
                      value={@editing_project && @editing_project.timeline_months}
                    />
                    <span class="btn btn-ghost join-item">months</span>
                  </div>
                </div>

                <div class="form-control mb-6">
                  <label class="label">
                    <span class="label-text font-medium">Color</span>
                    <span class="label-text-alt opacity-70">For progress bar</span>
                  </label>
                  <input
                    type="color"
                    name="project[color]"
                    class="input input-bordered h-14 w-full cursor-pointer"
                    value={(@editing_project && @editing_project.color) || "#3B82F6"}
                  />
                </div>

                <div class="modal-action">
                  <button type="button" class="btn btn-lg sm:btn-md flex-1" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary btn-lg sm:btn-md flex-1">
                    <%= if @editing_project, do: "Update", else: "Create" %>
                  </button>
                </div>
              </.form>
            </div>
            <div class="modal-backdrop bg-black/50" phx-click="close_modal"></div>
          </div>
        <% end %>
      </div>
    </.app>
    """
  end

  @impl true
  def handle_event("navigate_to_project", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: "/life/projects/#{id}")}
  end

  @impl true
  def handle_event("show_new_project_modal", _, socket) do
    {:noreply,
      socket
      |> assign(:show_project_modal, true)
      |> assign(:editing_project, nil)
      |> assign(:project_form, to_form(%{}, as: "project"))
    }
  end

  @impl true
  def handle_event("edit_project", %{"id" => id}, socket) do
    project = LifePlanning.get_project!(id)

    {:noreply,
      socket
      |> assign(:show_project_modal, true)
      |> assign(:editing_project, project)
      |> assign(:project_form, to_form(Map.from_struct(project), as: "project"))
    }
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_project_modal, false)}
  end

  @impl true
  def handle_event("save_project", %{"project" => project_params}, socket) do
    result =
      if socket.assigns.editing_project do
        LifePlanning.update_project(socket.assigns.editing_project, project_params)
      else
        # Set order to be last
        params_with_order = Map.put(project_params, "order", length(socket.assigns.projects))
        LifePlanning.create_project(params_with_order)
      end

    case result do
      {:ok, _project} ->
        {:noreply,
          socket
          |> assign(:show_project_modal, false)
          |> assign(:projects, load_projects())
          |> assign(:overall_progress, LifePlanning.get_overall_progress())
          |> put_flash(:info, "Project saved successfully!")
        }

      {:error, changeset} ->
        {:noreply,
          socket
          |> assign(:project_form, to_form(changeset, as: "project"))
          |> put_flash(:error, "Error saving project")
        }
    end
  end

  @impl true
  def handle_event("archive_project", %{"id" => id}, socket) do
    project = LifePlanning.get_project!(id)

    case LifePlanning.archive_project(project) do
      {:ok, _} ->
        {:noreply,
          socket
          |> assign(:projects, load_projects())
          |> assign(:overall_progress, LifePlanning.get_overall_progress())
          |> put_flash(:info, "Project archived")
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error archiving project")}
    end
  end

  @impl true
  def handle_event("delete_project", %{"id" => id}, socket) do
    project = LifePlanning.get_project!(id)

    case LifePlanning.delete_project(project) do
      {:ok, _} ->
        {:noreply,
          socket
          |> assign(:projects, load_projects())
          |> assign(:overall_progress, LifePlanning.get_overall_progress())
          |> put_flash(:info, "Project deleted")
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting project")}
    end
  end

  @impl true
  def handle_info({:project_created, _project}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
    }
  end

  @impl true
  def handle_info({:project_updated, _project}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
    }
  end

  @impl true
  def handle_info({:project_deleted, _project}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
    }
  end

  @impl true
  def handle_info({:task_created, _task}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
      |> assign(:urgent_tasks, LifePlanning.get_urgent_tasks())
    }
  end

  @impl true
  def handle_info({:task_updated, _task}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
      |> assign(:urgent_tasks, LifePlanning.get_urgent_tasks())
    }
  end

  @impl true
  def handle_info({:task_toggled, _task}, socket) do
    {:noreply,
      socket
      |> assign(:projects, load_projects())
      |> assign(:overall_progress, LifePlanning.get_overall_progress())
      |> assign(:urgent_tasks, LifePlanning.get_urgent_tasks())
    }
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private functions

  defp load_projects do
    projects = LifePlanning.list_projects()

    # Preload tasks for each project to avoid N+1
    Enum.map(projects, fn project ->
      Map.put(project, :tasks, LifePlanning.list_tasks(project.id))
    end)
  end

  defp get_project_stats(project_id) do
    LifePlanning.get_project_stats(project_id)
  end
end
