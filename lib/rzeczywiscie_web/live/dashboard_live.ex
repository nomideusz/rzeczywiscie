defmodule RzeczywiscieWeb.DashboardLive do
  use RzeczywiscieWeb, :live_view
  import RzeczywiscieWeb.Layouts

  alias Rzeczywiscie.LifeTracker

  def render(assigns) do
    ~H"""
    <.app flash={@flash}>
      <div class="container mx-auto px-4 py-8">
        <div class="mb-8">
          <h1 class="text-4xl font-bold mb-2">Forward Motion</h1>
          <p class="text-gray-600">Your life transition tracker</p>
        </div>

        <!-- Stats Overview -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <div class="stat bg-base-200 rounded-lg p-4">
            <div class="stat-title">Overall Progress</div>
            <div class="stat-value text-primary"><%= @stats.overall_progress %>%</div>
            <div class="stat-desc"><%= @stats.completed_tasks %>/<%= @stats.total_tasks %> tasks done</div>
          </div>

          <div class="stat bg-base-200 rounded-lg p-4">
            <div class="stat-title">Active Projects</div>
            <div class="stat-value"><%= @stats.active_projects %></div>
            <div class="stat-desc">out of <%= @stats.total_projects %> total</div>
          </div>

          <div class="stat bg-base-200 rounded-lg p-4">
            <div class="stat-title">Current Streak</div>
            <div class="stat-value text-accent"><%= @stats.streak %></div>
            <div class="stat-desc">days in a row</div>
          </div>

          <div class="stat bg-base-200 rounded-lg p-4">
            <div class="stat-title">Today's Progress</div>
            <div class="stat-value"><%= @today_count %></div>
            <div class="stat-desc">tasks completed</div>
          </div>
        </div>

        <!-- Projects Grid -->
        <.svelte
          name="ProjectDashboard"
          props={%{
            projects: @projects,
            stats: @stats
          }}
          socket={@socket}
        />
      </div>
    </.app>
    """
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      LifeTracker.subscribe()
    end

    projects = LifeTracker.list_projects()
    |> Enum.map(&project_with_tasks/1)

    stats = LifeTracker.get_dashboard_stats()
    {:ok, today_log} = LifeTracker.get_or_create_todays_log()

    {:ok,
     socket
     |> assign(:projects, projects)
     |> assign(:stats, stats)
     |> assign(:today_count, today_log.tasks_completed_count)}
  end

  def handle_event("toggle_task", %{"task_id" => task_id}, socket) do
    task = LifeTracker.get_task!(task_id)

    new_status = case task.status do
      "completed" -> "not_started"
      _ -> "completed"
    end

    case LifeTracker.update_task(task, %{status: new_status}) do
      {:ok, _updated_task} ->
        if new_status == "completed" do
          LifeTracker.increment_todays_count()
        end

        # Reload data
        projects = LifeTracker.list_projects()
        |> Enum.map(&project_with_tasks/1)

        stats = LifeTracker.get_dashboard_stats()
        {:ok, today_log} = LifeTracker.get_or_create_todays_log()

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:stats, stats)
         |> assign(:today_count, today_log.tasks_completed_count)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  def handle_event("update_task_status", %{"task_id" => task_id, "status" => status}, socket) do
    task = LifeTracker.get_task!(task_id)

    case LifeTracker.update_task(task, %{status: status}) do
      {:ok, _updated_task} ->
        if status == "completed" do
          LifeTracker.increment_todays_count()
        end

        # Reload data
        projects = LifeTracker.list_projects()
        |> Enum.map(&project_with_tasks/1)

        stats = LifeTracker.get_dashboard_stats()
        {:ok, today_log} = LifeTracker.get_or_create_todays_log()

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:stats, stats)
         |> assign(:today_count, today_log.tasks_completed_count)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  def handle_event("create_task", %{"project_id" => project_id, "title" => title}, socket) do
    case LifeTracker.create_task(%{
      project_id: String.to_integer(project_id),
      title: title,
      status: "not_started"
    }) do
      {:ok, _task} ->
        # Reload data
        projects = LifeTracker.list_projects()
        |> Enum.map(&project_with_tasks/1)

        stats = LifeTracker.get_dashboard_stats()

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> assign(:stats, stats)
         |> put_flash(:info, "Task created!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create task")}
    end
  end

  # PubSub handlers
  def handle_info({:task_updated, _task}, socket) do
    projects = LifeTracker.list_projects()
    |> Enum.map(&project_with_tasks/1)

    stats = LifeTracker.get_dashboard_stats()

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> assign(:stats, stats)}
  end

  def handle_info({:task_created, _task}, socket) do
    projects = LifeTracker.list_projects()
    |> Enum.map(&project_with_tasks/1)

    stats = LifeTracker.get_dashboard_stats()

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> assign(:stats, stats)}
  end

  def handle_info({:project_updated, _project}, socket) do
    projects = LifeTracker.list_projects()
    |> Enum.map(&project_with_tasks/1)

    stats = LifeTracker.get_dashboard_stats()

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> assign(:stats, stats)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Helper functions
  defp project_with_tasks(project) do
    tasks = LifeTracker.list_tasks(project.id)

    Map.put(project, :tasks, tasks)
  end
end
