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
    <.app flash={@flash}>
      <div class="container mx-auto p-4 max-w-6xl">
        <!-- Breadcrumb -->
        <div class="text-sm breadcrumbs mb-4">
          <ul>
            <li><a href="/life">Dashboard</a></li>
            <li><%= @project.name %></li>
          </ul>
        </div>

        <!-- Project Header -->
        <div class="card bg-gradient-to-r from-primary to-secondary text-primary-content shadow-xl mb-6">
          <div class="card-body">
            <h1 class="text-4xl font-bold">
              <span class="text-5xl mr-3"><%= @project.emoji || "📋" %></span>
              <%= @project.name %>
            </h1>

            <%= if @project.timeline_months do %>
              <p class="text-lg opacity-90">
                Timeline: ~<%= @project.timeline_months %> <%= if @project.timeline_months == 1, do: "month", else: "months" %>
              </p>
            <% end %>

            <div class="mt-4">
              <div class="flex justify-between text-sm mb-2">
                <span>Overall Progress</span>
                <span class="font-bold"><%= Float.round(@stats.progress, 1) %>%</span>
              </div>
              <progress
                class="progress progress-primary-content w-full h-6"
                value={@stats.progress}
                max="100"
              ></progress>
              <div class="mt-2">
                ✅ <%= @stats.completed %>/<%= @stats.total %> tasks completed
              </div>
            </div>
          </div>
        </div>

        <!-- Actions Bar -->
        <div class="flex justify-between items-center mb-6">
          <button class="btn btn-primary" phx-click="show_new_task_modal">
            + Add Task
          </button>

          <div class="flex gap-2">
            <button class="btn btn-ghost" phx-click="edit_project">
              Edit Project
            </button>
          </div>
        </div>

        <!-- Tasks by Phase -->
        <div class="space-y-6">
          <%= if length(@tasks) == 0 do %>
            <div class="alert alert-info">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <div>
                <h3 class="font-bold">No tasks yet</h3>
                <div class="text-xs">Break down this project into concrete, actionable tasks.</div>
              </div>
            </div>
          <% else %>
            <%= for phase <- @phases do %>
              <% phase_tasks = Enum.filter(@tasks, fn t -> (t.phase || "No Phase") == phase end) %>
              <% completed = Enum.count(phase_tasks, & &1.completed) %>
              <% total = length(phase_tasks) %>
              <% progress = if total > 0, do: completed / total * 100, else: 0 %>

              <div class="card bg-base-200 shadow-lg">
                <div class="card-body">
                  <div class="flex justify-between items-center mb-4">
                    <h2 class="card-title text-xl"><%= phase %></h2>
                    <div class="flex items-center gap-3">
                      <span class="text-sm opacity-70"><%= completed %>/<%= total %></span>
                      <progress class="progress progress-primary w-32" value={progress} max="100"></progress>
                    </div>
                  </div>

                  <div class="space-y-2">
                    <%= for task <- phase_tasks do %>
                      <div class={"flex items-start gap-3 p-3 rounded-lg transition-colors " <> if(task.completed, do: "bg-base-300 opacity-60", else: "bg-base-100")}>
                        <!-- Checkbox -->
                        <input
                          type="checkbox"
                          class="checkbox checkbox-primary mt-1"
                          checked={task.completed}
                          phx-click="toggle_task"
                          phx-value-id={task.id}
                        />

                        <!-- Task Content -->
                        <div class="flex-1">
                          <div class={"font-medium " <> if(task.completed, do: "line-through", else: "")}>
                            <%= task.title %>
                          </div>

                          <div class="flex gap-2 mt-1">
                            <%= if task.is_next_action && !task.completed do %>
                              <div class="badge badge-info badge-sm">Next Action</div>
                            <% end %>

                            <% urgency = Rzeczywiscie.LifePlanning.Task.urgency_level(task) %>
                            <%= if urgency do %>
                              <div class={"badge badge-sm " <> Rzeczywiscie.LifePlanning.Task.urgency_badge_class(urgency)}>
                                <%= Rzeczywiscie.LifePlanning.Task.urgency_text(urgency) %>
                              </div>
                            <% end %>

                            <%= if task.deadline && !task.completed do %>
                              <div class="text-xs opacity-70">
                                📅 <%= Calendar.strftime(task.deadline, "%b %d") %>
                              </div>
                            <% end %>
                          </div>
                        </div>

                        <!-- Actions -->
                        <div class="flex gap-1">
                          <%= if !task.is_next_action && !task.completed do %>
                            <button
                              class="btn btn-ghost btn-xs"
                              phx-click="set_next_action"
                              phx-value-id={task.id}
                              title="Set as next action"
                            >
                              ⭐
                            </button>
                          <% end %>

                          <button
                            class="btn btn-ghost btn-xs"
                            phx-click="edit_task"
                            phx-value-id={task.id}
                          >
                            ✏️
                          </button>

                          <button
                            class="btn btn-ghost btn-xs text-error"
                            phx-click="delete_task"
                            phx-value-id={task.id}
                            data-confirm="Are you sure?"
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

        <!-- Task Modal -->
        <%= if @show_task_modal do %>
          <div class="modal modal-open">
            <div class="modal-box">
              <h3 class="font-bold text-lg mb-4">
                <%= if @editing_task, do: "Edit Task", else: "New Task" %>
              </h3>

              <.form for={@task_form} phx-submit="save_task">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Task</span>
                  </label>
                  <textarea
                    name="task[title]"
                    class="textarea textarea-bordered h-24"
                    placeholder="What specific action do you need to take?"
                    required
                  ></textarea>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Phase (optional)</span>
                  </label>
                  <input
                    type="text"
                    name="task[phase]"
                    class="input input-bordered"
                    placeholder="e.g., Phase 1: Preparation"
                    list="phases"
                  />
                  <datalist id="phases">
                    <%= for phase <- @phases do %>
                      <option value={phase}><%= phase %></option>
                    <% end %>
                  </datalist>
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Deadline (optional)</span>
                  </label>
                  <input
                    type="date"
                    name="task[deadline]"
                    class="input input-bordered"
                    value={@editing_task && @editing_task.deadline}
                  />
                  <label class="label">
                    <span class="label-text-alt">Set a target date to create urgency</span>
                  </label>
                </div>

                <div class="form-control mb-4">
                  <label class="cursor-pointer label justify-start gap-3">
                    <input
                      type="checkbox"
                      name="task[is_next_action]"
                      class="checkbox checkbox-primary"
                      value="true"
                    />
                    <span class="label-text">Mark as Next Action</span>
                  </label>
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
