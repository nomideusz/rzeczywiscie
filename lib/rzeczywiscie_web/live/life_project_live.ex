defmodule RzeczywiscieWeb.LifeProjectLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts
  alias Rzeczywiscie.LifePlanning

  require Logger

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      LifePlanning.subscribe()
    end

    project = LifePlanning.get_project_with_tasks!(id)

    socket =
      socket
      |> assign(:project, project)
      |> assign(:tasks, project.tasks)
      |> assign(:stats, LifePlanning.get_project_stats(project.id))
      |> assign(:show_task_modal, false)
      |> assign(:editing_task, nil)
      |> assign(:task_form, to_form(%{}, as: "task"))
      |> assign(:phases, get_phases(project.tasks))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app flash={@flash} current_path={@current_path}>
      <div class="container mx-auto px-2 sm:px-4 py-4 max-w-6xl pb-20 sm:pb-4">
        <!-- Breadcrumb -->
        <div class="text-xs sm:text-sm breadcrumbs mb-3 sm:mb-4">
          <ul>
            <li><a href="/life" class="hover:underline">Dashboard</a></li>
            <li class="truncate max-w-[200px] sm:max-w-none"><%= @project.name %></li>
          </ul>
        </div>

        <!-- Project Header -->
        <div class="card bg-gradient-to-r from-primary to-secondary text-primary-content shadow-xl mb-4 sm:mb-6 transition-all duration-300">
          <div class="card-body p-4 sm:p-6">
            <h1 class="text-2xl sm:text-3xl md:text-4xl font-bold break-words flex items-start gap-2 sm:gap-3">
              <span class="text-3xl sm:text-4xl md:text-5xl flex-shrink-0" aria-hidden="true"><%= @project.emoji || "📋" %></span>
              <span class="break-words"><%= @project.name %></span>
            </h1>

            <%= if @project.timeline_months do %>
              <p class="text-sm sm:text-base md:text-lg opacity-90 mt-2">
                Timeline: ~<%= @project.timeline_months %> <%= if @project.timeline_months == 1, do: "month", else: "months" %>
              </p>
            <% end %>

            <div class="mt-3 sm:mt-4">
              <div class="flex justify-between text-xs sm:text-sm mb-2">
                <span>Overall Progress</span>
                <span class="font-bold"><%= Float.round(@stats.progress, 1) %>%</span>
              </div>
              <progress
                class="progress progress-primary-content w-full h-5 sm:h-6"
                value={@stats.progress}
                max="100"
                aria-label={"Progress: #{Float.round(@stats.progress, 1)}%"}
                aria-valuenow={@stats.progress}
                aria-valuemin="0"
                aria-valuemax="100"
              ></progress>
              <div class="mt-2 text-sm sm:text-base">
                ✅ <%= @stats.completed %>/<%= @stats.total %> tasks completed
              </div>
            </div>
          </div>
        </div>

        <!-- Actions Bar -->
        <div class="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-3 mb-4 sm:mb-6">
          <button class="btn btn-primary hidden sm:inline-flex" phx-click="show_new_task_modal" aria-label="Add new task">
            + Add Task
          </button>

          <div class="flex gap-2 justify-end">
            <a href="/life" class="btn btn-ghost btn-sm sm:btn-md">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
              <span class="hidden sm:inline">Back</span>
            </a>
            <button class="btn btn-ghost btn-sm sm:btn-md" phx-click="edit_project">
              ✏️ <span class="hidden sm:inline">Edit Project</span>
            </button>
          </div>
        </div>

        <!-- Tasks by Phase -->
        <div class="space-y-4 sm:space-y-6">
          <%= if length(@tasks) == 0 do %>
            <div class="flex flex-col items-center justify-center py-12 px-4 text-center animate-in fade-in duration-700">
              <div class="text-6xl mb-4 animate-bounce">📝</div>
              <h3 class="text-2xl font-bold mb-2">Ready to Get Started?</h3>
              <p class="text-base opacity-70 mb-6 max-w-md">
                Break down this project into concrete, actionable tasks. Small steps lead to big wins!
              </p>
              <button
                class="btn btn-primary btn-lg"
                phx-click="show_new_task_modal"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                Add Your First Task
              </button>
            </div>
          <% else %>
            <%= for phase <- @phases do %>
              <% phase_tasks = Enum.filter(@tasks, fn t -> (t.phase || "No Phase") == phase end) %>
              <% completed = Enum.count(phase_tasks, & &1.completed) %>
              <% total = length(phase_tasks) %>
              <% progress = if total > 0, do: completed / total * 100, else: 0 %>

              <div class="card bg-base-200 shadow-lg transition-all duration-300">
                <div class="card-body p-3 sm:p-4 md:p-6">
                  <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 sm:gap-3 mb-3 sm:mb-4">
                    <h2 class="card-title text-lg sm:text-xl"><%= phase %></h2>
                    <div class="flex items-center gap-2 sm:gap-3 w-full sm:w-auto">
                      <span class="text-xs sm:text-sm opacity-70"><%= completed %>/<%= total %></span>
                      <progress class="progress progress-primary flex-1 sm:w-32 h-2 sm:h-3" value={progress} max="100" aria-label={"#{phase} progress: #{Float.round(progress, 0)}%"}></progress>
                    </div>
                  </div>

                  <div class="space-y-2">
                    <%= for task <- phase_tasks do %>
                      <div class={"flex items-start gap-2 sm:gap-3 p-2 sm:p-3 rounded-lg transition-all min-h-[60px] " <> if(task.completed, do: "bg-base-300 opacity-60", else: "bg-base-100 hover:shadow-md")}>
                        <!-- Checkbox -->
                        <input
                          type="checkbox"
                          class="checkbox checkbox-primary mt-1 flex-shrink-0 w-5 h-5 sm:w-6 sm:h-6"
                          checked={task.completed}
                          phx-click="toggle_task"
                          phx-value-id={task.id}
                          aria-label={"Mark task as " <> if(task.completed, do: "incomplete", else: "complete")}
                        />

                        <!-- Task Content -->
                        <div class="flex-1 min-w-0">
                          <div class={"text-sm sm:text-base font-medium break-words " <> if(task.completed, do: "line-through", else: "")}>
                            <%= task.title %>
                          </div>

                          <div class="flex flex-wrap gap-1 sm:gap-2 mt-1">
                            <%= if task.is_next_action && !task.completed do %>
                              <div class="badge badge-info badge-xs sm:badge-sm">Next Action</div>
                            <% end %>

                            <% urgency = Rzeczywiscie.LifePlanning.Task.urgency_level(task) %>
                            <%= if urgency do %>
                              <div class={"badge badge-xs sm:badge-sm whitespace-nowrap " <> Rzeczywiscie.LifePlanning.Task.urgency_badge_class(urgency)}>
                                <%= Rzeczywiscie.LifePlanning.Task.urgency_text(urgency) %>
                              </div>
                            <% end %>

                            <%= if task.deadline && !task.completed do %>
                              <div class="text-xs sm:text-sm opacity-70">
                                📅 <%= Calendar.strftime(task.deadline, "%b %d") %>
                              </div>
                            <% end %>
                          </div>
                        </div>

                        <!-- Actions -->
                        <div class="flex gap-0.5 sm:gap-1 flex-shrink-0">
                          <%= if !task.is_next_action && !task.completed do %>
                            <button
                              class="btn btn-ghost btn-xs sm:btn-sm"
                              phx-click="set_next_action"
                              phx-value-id={task.id}
                              aria-label="Set as next action"
                            >
                              ⭐
                            </button>
                          <% end %>

                          <button
                            class="btn btn-ghost btn-xs sm:btn-sm"
                            phx-click="edit_task"
                            phx-value-id={task.id}
                            aria-label="Edit task"
                          >
                            ✏️
                          </button>

                          <button
                            class="btn btn-ghost btn-xs sm:btn-sm text-error"
                            phx-click="delete_task"
                            phx-value-id={task.id}
                            data-confirm="Are you sure?"
                            aria-label="Delete task"
                          >
                            🗑️
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Floating Action Button (Mobile Only) -->
        <button
          class="fixed bottom-6 right-6 btn btn-primary btn-circle btn-lg shadow-2xl sm:hidden z-50 animate-in zoom-in duration-300"
          phx-click="show_new_task_modal"
          aria-label="Add new task"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
        </button>

        <!-- Task Modal -->
        <%= if @show_task_modal do %>
          <div class="modal modal-open animate-in fade-in zoom-in duration-200">
            <div class="modal-box max-w-md w-full mx-4">
              <h3 class="font-bold text-xl mb-4 flex items-center gap-2">
                <span class="text-2xl" aria-hidden="true"><%= if @editing_task, do: "✏️", else: "➕" %></span>
                <%= if @editing_task, do: "Edit Task", else: "New Task" %>
              </h3>

              <.form for={@task_form} phx-submit="save_task">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Task</span>
                    <span class="label-text-alt text-error">Required</span>
                  </label>
                  <textarea
                    name="task[title]"
                    class="textarea textarea-bordered textarea-lg sm:textarea-md h-24 text-base"
                    placeholder="What specific action do you need to take?"
                    required
                    autofocus
                    value={@editing_task && @editing_task.title}
                  ><%= if @editing_task, do: @editing_task.title, else: "" %></textarea>
                  <label class="label">
                    <span class="label-text-alt">Be specific and action-oriented</span>
                  </label>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Phase</span>
                    <span class="label-text-alt opacity-70">Optional</span>
                  </label>
                  <input
                    type="text"
                    name="task[phase]"
                    class="input input-bordered input-lg sm:input-md"
                    placeholder="e.g., Phase 1: Preparation"
                    list="phases"
                    value={@editing_task && @editing_task.phase}
                  />
                  <datalist id="phases">
                    <%= for phase <- @phases do %>
                      <option value={phase}><%= phase %></option>
                    <% end %>
                  </datalist>
                  <label class="label">
                    <span class="label-text-alt">Group related tasks together</span>
                  </label>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text font-medium">Deadline</span>
                    <span class="label-text-alt opacity-70">Optional</span>
                  </label>
                  <input
                    type="date"
                    name="task[deadline]"
                    class="input input-bordered input-lg sm:input-md"
                    value={@editing_task && @editing_task.deadline}
                  />
                  <label class="label">
                    <span class="label-text-alt">Create urgency with a target date</span>
                  </label>
                </div>

                <div class="form-control mb-6">
                  <label class="cursor-pointer label justify-start gap-3 p-3 bg-base-200 rounded-lg hover:bg-base-300 transition-colors">
                    <input
                      type="checkbox"
                      name="task[is_next_action]"
                      class="checkbox checkbox-primary checkbox-lg sm:checkbox-md"
                      value="true"
                      checked={@editing_task && @editing_task.is_next_action}
                    />
                    <div class="flex-1">
                      <span class="label-text font-medium">Mark as Next Action</span>
                      <div class="label-text-alt mt-1">Make this your immediate focus</div>
                    </div>
                  </label>
                </div>

                <div class="modal-action">
                  <button type="button" class="btn btn-lg sm:btn-md flex-1" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary btn-lg sm:btn-md flex-1">
                    <%= if @editing_task, do: "Update", else: "Create" %>
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
  def handle_event("show_new_task_modal", _, socket) do
    {:noreply,
      socket
      |> assign(:show_task_modal, true)
      |> assign(:editing_task, nil)
      |> assign(:task_form, to_form(%{}, as: "task"))
    }
  end

  @impl true
  def handle_event("edit_task", %{"id" => id}, socket) do
    task = LifePlanning.get_task!(id)

    {:noreply,
      socket
      |> assign(:show_task_modal, true)
      |> assign(:editing_task, task)
      |> assign(:task_form, to_form(Map.from_struct(task), as: "task"))
    }
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_task_modal, false)}
  end

  @impl true
  def handle_event("save_task", %{"task" => task_params}, socket) do
    # Ensure project_id is set
    task_params = Map.put(task_params, "project_id", socket.assigns.project.id)

    # Handle checkbox for is_next_action (when unchecked, it's not in the params)
    task_params =
      if Map.has_key?(task_params, "is_next_action") do
        task_params
      else
        Map.put(task_params, "is_next_action", false)
      end

    # If setting as next action, unset all other next actions for this project
    if task_params["is_next_action"] in ["true", true] do
      unset_all_next_actions(socket.assigns.project.id)
    end

    result =
      if socket.assigns.editing_task do
        LifePlanning.update_task(socket.assigns.editing_task, task_params)
      else
        # Set order to be last
        params_with_order = Map.put(task_params, "order", length(socket.assigns.tasks))
        LifePlanning.create_task(params_with_order)
      end

    case result do
      {:ok, _task} ->
        project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

        {:noreply,
          socket
          |> assign(:show_task_modal, false)
          |> assign(:project, project)
          |> assign(:tasks, project.tasks)
          |> assign(:stats, LifePlanning.get_project_stats(project.id))
          |> assign(:phases, get_phases(project.tasks))
          |> put_flash(:info, "Task saved successfully!")
        }

      {:error, changeset} ->
        {:noreply,
          socket
          |> assign(:task_form, to_form(changeset, as: "task"))
          |> put_flash(:error, "Error saving task")
        }
    end
  end

  @impl true
  def handle_event("toggle_task", %{"id" => id}, socket) do
    task = LifePlanning.get_task!(id)

    case LifePlanning.toggle_task(task) do
      {:ok, _task} ->
        project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

        {:noreply,
          socket
          |> assign(:project, project)
          |> assign(:tasks, project.tasks)
          |> assign(:stats, LifePlanning.get_project_stats(project.id))
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error updating task")}
    end
  end

  @impl true
  def handle_event("set_next_action", %{"id" => id}, socket) do
    # Unset all next actions for this project
    unset_all_next_actions(socket.assigns.project.id)

    # Set this task as next action
    task = LifePlanning.get_task!(id)

    case LifePlanning.update_task(task, %{is_next_action: true}) do
      {:ok, _task} ->
        project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

        {:noreply,
          socket
          |> assign(:tasks, project.tasks)
          |> put_flash(:info, "Next action updated!")
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error setting next action")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    task = LifePlanning.get_task!(id)

    case LifePlanning.delete_task(task) do
      {:ok, _} ->
        project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

        {:noreply,
          socket
          |> assign(:project, project)
          |> assign(:tasks, project.tasks)
          |> assign(:stats, LifePlanning.get_project_stats(project.id))
          |> assign(:phases, get_phases(project.tasks))
          |> put_flash(:info, "Task deleted")
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting task")}
    end
  end

  @impl true
  def handle_event("edit_project", _, socket) do
    {:noreply, push_navigate(socket, to: "/life")}
  end

  @impl true
  def handle_info({:task_created, task}, socket) do
    if task.project_id == socket.assigns.project.id do
      project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

      {:noreply,
        socket
        |> assign(:project, project)
        |> assign(:tasks, project.tasks)
        |> assign(:stats, LifePlanning.get_project_stats(project.id))
        |> assign(:phases, get_phases(project.tasks))
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:task_updated, task}, socket) do
    if task.project_id == socket.assigns.project.id do
      project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

      {:noreply,
        socket
        |> assign(:project, project)
        |> assign(:tasks, project.tasks)
        |> assign(:stats, LifePlanning.get_project_stats(project.id))
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:task_toggled, task}, socket) do
    if task.project_id == socket.assigns.project.id do
      project = LifePlanning.get_project_with_tasks!(socket.assigns.project.id)

      {:noreply,
        socket
        |> assign(:project, project)
        |> assign(:tasks, project.tasks)
        |> assign(:stats, LifePlanning.get_project_stats(project.id))
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helpers

  defp get_phases(tasks) do
    tasks
    |> Enum.map(& &1.phase || "No Phase")
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp unset_all_next_actions(project_id) do
    project_id
    |> LifePlanning.list_tasks()
    |> Enum.filter(& &1.is_next_action)
    |> Enum.each(fn task ->
      LifePlanning.update_task(task, %{is_next_action: false})
    end)
  end
end
