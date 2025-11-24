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
    <.app flash={@flash}>
      <div class="container mx-auto p-4 max-w-6xl">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-4xl font-bold mb-2">Life Reboot Tracker</h1>
          <p class="text-lg opacity-70">Take control of your life, one step at a time</p>
        </div>

        <!-- Overall Progress Card -->
        <div class="card bg-gradient-to-r from-primary to-secondary text-primary-content shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-2xl">Your Progress</h2>
            <div class="flex items-center gap-6 mt-4">
              <div class="flex-1">
                <div class="text-sm opacity-90 mb-2">Overall Completion</div>
                <progress
                  class="progress progress-primary-content w-full h-6"
                  value={@overall_progress.progress}
                  max="100"
                ></progress>
                <div class="text-lg font-bold mt-1"><%= Float.round(@overall_progress.progress, 1) %>%</div>
              </div>
              <div class="stats stats-vertical lg:stats-horizontal shadow">
                <div class="stat">
                  <div class="stat-title text-primary-content opacity-80">Completed</div>
                  <div class="stat-value text-primary-content"><%= @overall_progress.completed_tasks %></div>
                </div>
                <div class="stat">
                  <div class="stat-title text-primary-content opacity-80">Total Tasks</div>
                  <div class="stat-value text-primary-content"><%= @overall_progress.total_tasks %></div>
                </div>
                <div class="stat">
                  <div class="stat-title text-primary-content opacity-80">Streak</div>
                  <div class="stat-value text-primary-content">
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
          <div class="alert alert-warning shadow-lg mb-6">
            <div class="w-full">
              <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                  <h3 class="font-bold text-lg">⏰ Urgent Tasks (<%= length(@urgent_tasks) %>)</h3>
                </div>
              </div>
              <div class="space-y-2">
                <%= for task <- Enum.take(@urgent_tasks, 5) do %>
                  <% urgency = Rzeczywiscie.LifePlanning.Task.urgency_level(task) %>
                  <% project = Enum.find(@projects, fn p -> p.id == task.project_id end) %>
                  <div class="flex items-center justify-between p-2 bg-base-100 rounded">
                    <div class="flex-1">
                      <div class="font-medium"><%= task.title %></div>
                      <div class="text-sm opacity-70">
                        <%= if project, do: "#{project.emoji} #{project.name}", else: "Unknown Project" %>
                      </div>
                    </div>
                    <div class="flex items-center gap-2">
                      <div class={"badge badge-sm " <> Rzeczywiscie.LifePlanning.Task.urgency_badge_class(urgency)}>
                        <%= Rzeczywiscie.LifePlanning.Task.urgency_text(urgency) %>
                      </div>
                      <%= if task.deadline do %>
                        <div class="text-sm opacity-70">
                          📅 <%= Calendar.strftime(task.deadline, "%b %d") %>
                        </div>
                      <% end %>
                      <a href={"/life/projects/#{task.project_id}"} class="btn btn-xs btn-ghost">View</a>
                    </div>
                  </div>
                <% end %>
                <%= if length(@urgent_tasks) > 5 do %>
                  <div class="text-sm opacity-70 text-center mt-2">
                    + <%= length(@urgent_tasks) - 5 %> more urgent tasks
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Navigation -->
        <div class="flex justify-between items-center mb-6">
          <div class="tabs tabs-boxed">
            <a href="/life" class="tab tab-active">Dashboard</a>
            <a href="/life/check-in" class="tab">Daily Check-in</a>
            <a href="/life/weekly-review" class="tab">Weekly Review</a>
            <a href="/life/progress" class="tab">Analytics</a>
          </div>
          <button
            class="btn btn-primary"
            phx-click="show_new_project_modal"
          >
            + Add Project
          </button>
        </div>

        <!-- Projects Grid -->
        <div class="grid grid-cols-1 gap-6">
          <%= for project <- @projects do %>
            <% stats = get_project_stats(project.id) %>
            <% next_action = LifePlanning.get_next_action(project.id) %>

            <div class="card bg-base-200 shadow-xl hover:shadow-2xl transition-shadow cursor-pointer"
                 phx-click="navigate_to_project"
                 phx-value-id={project.id}>
              <div class="card-body">
                <div class="flex justify-between items-start">
                  <div class="flex-1">
                    <h2 class="card-title text-2xl">
                      <span class="text-3xl mr-2"><%= project.emoji || "📋" %></span>
                      <%= project.name %>
                    </h2>

                    <!-- Timeline -->
                    <%= if project.timeline_months do %>
                      <div class="text-sm opacity-70 mt-1">
                        Timeline: ~<%= project.timeline_months %> <%= if project.timeline_months == 1, do: "month", else: "months" %>
                      </div>
                    <% end %>

                    <!-- Progress Bar -->
                    <div class="mt-4">
                      <div class="flex justify-between text-sm mb-1">
                        <span class="opacity-70">Progress</span>
                        <span class="font-bold"><%= Float.round(stats.progress, 1) %>%</span>
                      </div>
                      <progress
                        class="progress progress-primary w-full h-4"
                        value={stats.progress}
                        max="100"
                        style={"background-color: #{project.color}40;"}
                      ></progress>
                      <div class="text-sm opacity-70 mt-1">
                        ✅ <%= stats.completed %>/<%= stats.total %> tasks done
                      </div>
                    </div>

                    <!-- Next Action -->
                    <%= if next_action do %>
                      <div class="alert alert-info mt-4">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-5 h-5">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                        </svg>
                        <div>
                          <div class="text-xs opacity-70">Next Action</div>
                          <div class="font-bold"><%= next_action.title %></div>
                        </div>
                      </div>
                    <% else %>
                      <%= if stats.total > 0 && stats.completed < stats.total do %>
                        <div class="alert alert-warning mt-4">
                          <div>
                            <div class="text-xs">⚠️ No next action set</div>
                            <div class="text-sm">Click to mark a task as your focus</div>
                          </div>
                        </div>
                      <% end %>
                    <% end %>
                  </div>

                  <!-- Actions -->
                  <div class="dropdown dropdown-end">
                    <label tabindex="0" class="btn btn-ghost btn-sm btn-circle" onclick="event.stopPropagation()">
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="w-5 h-5 stroke-current">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"></path>
                      </svg>
                    </label>
                    <ul tabindex="0" class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52" onclick="event.stopPropagation()">
                      <li><a phx-click="edit_project" phx-value-id={project.id} onclick="event.stopPropagation()">Edit</a></li>
                      <li><a phx-click="archive_project" phx-value-id={project.id} onclick="event.stopPropagation()">Archive</a></li>
                      <li><a phx-click="delete_project" phx-value-id={project.id} onclick="event.stopPropagation()" class="text-error">Delete</a></li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
          <% end %>

          <%= if length(@projects) == 0 do %>
            <div class="alert alert-info">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <div>
                <h3 class="font-bold">No projects yet</h3>
                <div class="text-xs">Click "Add Project" to get started on your life reboot journey!</div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Project Modal -->
        <%= if @show_project_modal do %>
          <div class="modal modal-open">
            <div class="modal-box">
              <h3 class="font-bold text-lg mb-4">
                <%= if @editing_project, do: "Edit Project", else: "New Project" %>
              </h3>

              <.form for={@project_form} phx-submit="save_project">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Name</span>
                  </label>
                  <input type="text" name="project[name]" class="input input-bordered" placeholder="e.g., Apartment" required />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Emoji (optional)</span>
                  </label>
                  <input type="text" name="project[emoji]" class="input input-bordered" placeholder="🏠" />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Timeline (months)</span>
                  </label>
                  <input type="number" name="project[timeline_months]" class="input input-bordered" placeholder="3" min="1" />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Color</span>
                  </label>
                  <input type="color" name="project[color]" class="input input-bordered h-12" value="#3B82F6" />
                </div>

                <div class="modal-action">
                  <button type="button" class="btn" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary">Save</button>
                </div>
              </.form>
            </div>
            <div class="modal-backdrop" phx-click="close_modal"></div>
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
