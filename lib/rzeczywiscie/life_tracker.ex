defmodule Rzeczywiscie.LifeTracker do
  @moduledoc """
  The LifeTracker context - manages life transition projects, tasks, and progress tracking.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.LifeTracker.{Project, Task, DailyLog, Milestone}

  @topic "life_tracker"

  @doc """
  Subscribe to life tracker updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast updates to all subscribed clients.
  """
  def broadcast(data, event) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {event, data}
    )
  end

  # Projects

  @doc """
  List all projects ordered by order field.
  """
  def list_projects do
    Project
    |> order_by([p], asc: p.order)
    |> Repo.all()
  end

  @doc """
  Get a single project with its tasks.
  """
  def get_project!(id) do
    Project
    |> Repo.get!(id)
    |> Repo.preload(tasks: from(t in Task, order_by: [asc: t.order]))
  end

  @doc """
  Get a project with tasks, optionally filtering tasks by phase.
  """
  def get_project_with_tasks!(id, opts \\ []) do
    query = from(t in Task, order_by: [asc: t.order])

    query = if phase = opts[:phase] do
      where(query, [t], t.phase == ^phase)
    else
      query
    end

    Project
    |> Repo.get!(id)
    |> Repo.preload(tasks: query)
  end

  @doc """
  Create a project.
  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
    |> broadcast_if_ok(:project_created)
  end

  @doc """
  Update a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
    |> broadcast_if_ok(:project_updated)
  end

  @doc """
  Delete a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
    |> broadcast_if_ok(:project_deleted)
  end

  @doc """
  Recalculate and update project progress based on completed tasks.
  """
  def recalculate_project_progress(%Project{} = project) do
    tasks = Repo.preload(project, :tasks).tasks

    progress = if Enum.empty?(tasks) do
      0
    else
      completed = Enum.count(tasks, &(&1.status == "completed"))
      round(completed / length(tasks) * 100)
    end

    update_project(project, %{progress_pct: progress})
  end

  # Tasks

  @doc """
  List all tasks for a project.
  """
  def list_tasks(project_id) do
    Task
    |> where([t], t.project_id == ^project_id)
    |> order_by([t], asc: t.order)
    |> Repo.all()
  end

  @doc """
  List tasks by status.
  """
  def list_tasks_by_status(status) do
    Task
    |> where([t], t.status == ^status)
    |> order_by([t], [asc: t.project_id, asc: t.order])
    |> Repo.all()
    |> Repo.preload(:project)
  end

  @doc """
  Get a single task.
  """
  def get_task!(id) do
    Repo.get!(Task, id)
  end

  @doc """
  Create a task.
  """
  def create_task(attrs \\ %{}) do
    result = %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()

    case result do
      {:ok, task} ->
        # Recalculate project progress
        project = get_project!(task.project_id)
        recalculate_project_progress(project)
        broadcast({:task_created, task}, :task_created)
        {:ok, task}
      error -> error
    end
  end

  @doc """
  Update a task.
  """
  def update_task(%Task{} = task, attrs) do
    result = task
    |> Task.changeset(attrs)
    |> Repo.update()

    case result do
      {:ok, updated_task} ->
        # If status changed to completed, set completed_at
        updated_task = if updated_task.status == "completed" and is_nil(updated_task.completed_at) do
          {:ok, task_with_date} = Repo.update(Task.changeset(updated_task, %{completed_at: DateTime.utc_now()}))
          task_with_date
        else
          updated_task
        end

        # Recalculate project progress
        project = get_project!(updated_task.project_id)
        recalculate_project_progress(project)
        broadcast({:task_updated, updated_task}, :task_updated)
        {:ok, updated_task}
      error -> error
    end
  end

  @doc """
  Delete a task.
  """
  def delete_task(%Task{} = task) do
    project_id = task.project_id
    result = Repo.delete(task)

    case result do
      {:ok, deleted_task} ->
        # Recalculate project progress
        project = get_project!(project_id)
        recalculate_project_progress(project)
        broadcast({:task_deleted, deleted_task}, :task_deleted)
        {:ok, deleted_task}
      error -> error
    end
  end

  # Daily Logs

  @doc """
  Get or create today's log.
  """
  def get_or_create_todays_log do
    today = Date.utc_today()

    case Repo.get_by(DailyLog, date: today) do
      nil -> create_daily_log(%{date: today})
      log -> {:ok, log}
    end
  end

  @doc """
  Get daily log for a specific date.
  """
  def get_daily_log(date) do
    Repo.get_by(DailyLog, date: date)
  end

  @doc """
  List recent daily logs.
  """
  def list_recent_logs(limit \\ 30) do
    DailyLog
    |> order_by([l], desc: l.date)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Create a daily log.
  """
  def create_daily_log(attrs \\ %{}) do
    %DailyLog{}
    |> DailyLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a daily log.
  """
  def update_daily_log(%DailyLog{} = log, attrs) do
    log
    |> DailyLog.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Calculate current streak (consecutive days with progress).
  """
  def calculate_streak do
    logs = list_recent_logs(365)

    logs
    |> Enum.sort_by(& &1.date, {:desc, Date})
    |> Enum.reduce_while({0, Date.utc_today()}, fn log, {streak, expected_date} ->
      cond do
        Date.compare(log.date, expected_date) == :eq and log.tasks_completed_count > 0 ->
          {:cont, {streak + 1, Date.add(expected_date, -1)}}

        Date.compare(log.date, Date.add(expected_date, -1)) == :eq and log.tasks_completed_count > 0 ->
          {:cont, {streak + 1, Date.add(expected_date, -1)}}

        true ->
          {:halt, {streak, expected_date}}
      end
    end)
    |> elem(0)
  end

  @doc """
  Increment today's task completion count.
  """
  def increment_todays_count do
    {:ok, log} = get_or_create_todays_log()
    update_daily_log(log, %{tasks_completed_count: log.tasks_completed_count + 1})
  end

  # Milestones

  @doc """
  List milestones for a project.
  """
  def list_milestones(project_id) do
    Milestone
    |> where([m], m.project_id == ^project_id)
    |> order_by([m], asc: m.target_date)
    |> Repo.all()
  end

  @doc """
  Create a milestone.
  """
  def create_milestone(attrs \\ %{}) do
    %Milestone{}
    |> Milestone.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a milestone.
  """
  def update_milestone(%Milestone{} = milestone, attrs) do
    milestone
    |> Milestone.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a milestone.
  """
  def delete_milestone(%Milestone{} = milestone) do
    Repo.delete(milestone)
  end

  # Dashboard stats

  @doc """
  Get dashboard statistics.
  """
  def get_dashboard_stats do
    projects = list_projects()
    total_tasks = Repo.aggregate(Task, :count)
    completed_tasks = Task |> where([t], t.status == "completed") |> Repo.aggregate(:count)

    overall_progress = if total_tasks > 0 do
      round(completed_tasks / total_tasks * 100)
    else
      0
    end

    %{
      total_projects: length(projects),
      active_projects: Enum.count(projects, &(&1.status == "active")),
      total_tasks: total_tasks,
      completed_tasks: completed_tasks,
      overall_progress: overall_progress,
      streak: calculate_streak()
    }
  end

  # Helpers

  defp broadcast_if_ok({:ok, result}, event) do
    broadcast(result, event)
    {:ok, result}
  end

  defp broadcast_if_ok(error, _event), do: error
end
