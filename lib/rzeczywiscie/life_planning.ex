defmodule Rzeczywiscie.LifePlanning do
  @moduledoc """
  The LifePlanning context - manages life projects, tasks, and daily check-ins.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.LifePlanning.{LifeProject, Task, DailyCheckin}

  @topic "life_planning"

  ## Projects

  @doc """
  Subscribe to life planning updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Rzeczywiscie.PubSub, @topic)
  end

  @doc """
  Broadcast life planning updates to all subscribed clients.
  """
  def broadcast_update(data, event) do
    Phoenix.PubSub.broadcast(
      Rzeczywiscie.PubSub,
      @topic,
      {event, data}
    )
  end

  @doc """
  Returns the list of life_projects, ordered by order field.
  """
  def list_projects(include_archived \\ false) do
    query =
      from p in LifeProject,
        order_by: [asc: p.order, asc: p.id]

    query =
      if include_archived do
        query
      else
        where(query, [p], p.archived == false)
      end

    Repo.all(query)
  end

  @doc """
  Gets a single life_project.
  Raises `Ecto.NoResultsError` if the Life project does not exist.
  """
  def get_project!(id), do: Repo.get!(LifeProject, id)

  @doc """
  Gets a single life_project with preloaded tasks.
  """
  def get_project_with_tasks!(id) do
    LifeProject
    |> Repo.get!(id)
    |> Repo.preload(tasks: from(t in Task, order_by: [asc: t.order, asc: t.id]))
  end

  @doc """
  Creates a life_project.
  """
  def create_project(attrs \\ %{}) do
    %LifeProject{}
    |> LifeProject.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, project} -> broadcast_update(project, :project_created)
      _ -> :ok
    end)
  end

  @doc """
  Updates a life_project.
  """
  def update_project(%LifeProject{} = life_project, attrs) do
    life_project
    |> LifeProject.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, project} -> broadcast_update(project, :project_updated)
      _ -> :ok
    end)
  end

  @doc """
  Deletes a life_project.
  """
  def delete_project(%LifeProject{} = life_project) do
    Repo.delete(life_project)
    |> tap(fn
      {:ok, project} -> broadcast_update(project, :project_deleted)
      _ -> :ok
    end)
  end

  @doc """
  Archives a life_project.
  """
  def archive_project(%LifeProject{} = life_project) do
    update_project(life_project, %{archived: true})
  end

  @doc """
  Unarchives a life_project.
  """
  def unarchive_project(%LifeProject{} = life_project) do
    update_project(life_project, %{archived: false})
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking life_project changes.
  """
  def change_project(%LifeProject{} = life_project, attrs \\ %{}) do
    LifeProject.changeset(life_project, attrs)
  end

  ## Tasks

  @doc """
  Returns the list of tasks for a project.
  """
  def list_tasks(project_id) do
    Task
    |> where([t], t.project_id == ^project_id)
    |> order_by([asc: :order, asc: :id])
    |> Repo.all()
  end

  @doc """
  Gets a single task.
  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, task} -> broadcast_update(task, :task_created)
      _ -> :ok
    end)
  end

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, task} -> broadcast_update(task, :task_updated)
      _ -> :ok
    end)
  end

  @doc """
  Deletes a task.
  """
  def delete_task(%Task{} = task) do
    Repo.delete(task)
    |> tap(fn
      {:ok, task} -> broadcast_update(task, :task_deleted)
      _ -> :ok
    end)
  end

  @doc """
  Toggles a task completion status.
  """
  def toggle_task(%Task{} = task) do
    changeset =
      if task.completed do
        Task.incomplete_changeset(task)
      else
        Task.complete_changeset(task)
      end

    Repo.update(changeset)
    |> tap(fn
      {:ok, task} -> broadcast_update(task, :task_toggled)
      _ -> :ok
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  ## Progress calculations

  @doc """
  Calculates the progress percentage for a project.
  Returns a float between 0 and 100.
  """
  def calculate_project_progress(project_id) do
    query =
      from t in Task,
        where: t.project_id == ^project_id,
        select: %{
          total: count(t.id),
          completed: count(fragment("CASE WHEN ? THEN 1 END", t.completed))
        }

    case Repo.one(query) do
      %{total: 0} -> 0.0
      %{total: total, completed: completed} -> completed / total * 100
    end
  end

  @doc """
  Gets project statistics (total tasks, completed tasks, progress).
  """
  def get_project_stats(project_id) do
    query =
      from t in Task,
        where: t.project_id == ^project_id,
        select: %{
          total: count(t.id),
          completed: count(fragment("CASE WHEN ? THEN 1 END", t.completed))
        }

    stats = Repo.one(query) || %{total: 0, completed: 0}
    progress = if stats.total == 0, do: 0.0, else: stats.completed / stats.total * 100

    Map.put(stats, :progress, progress)
  end

  @doc """
  Gets overall progress across all non-archived projects.
  """
  def get_overall_progress do
    query =
      from p in LifeProject,
        left_join: t in assoc(p, :tasks),
        where: p.archived == false,
        group_by: p.id,
        select: %{
          project_id: p.id,
          total: count(t.id),
          completed: count(fragment("CASE WHEN ? THEN 1 END", t.completed))
        }

    stats = Repo.all(query)

    total_tasks = Enum.sum(Enum.map(stats, & &1.total))
    completed_tasks = Enum.sum(Enum.map(stats, & &1.completed))

    progress = if total_tasks == 0, do: 0.0, else: completed_tasks / total_tasks * 100

    %{
      total_tasks: total_tasks,
      completed_tasks: completed_tasks,
      progress: progress
    }
  end

  @doc """
  Get the next action task for a project (task marked as is_next_action).
  """
  def get_next_action(project_id) do
    Task
    |> where([t], t.project_id == ^project_id and t.is_next_action == true and t.completed == false)
    |> limit(1)
    |> Repo.one()
  end

  ## Daily Check-ins

  @doc """
  Returns the list of daily_checkins, ordered by date descending.
  """
  def list_checkins(limit \\ 30) do
    DailyCheckin
    |> order_by([desc: :date])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single daily_checkin by date.
  """
  def get_checkin_by_date(date) do
    Repo.get_by(DailyCheckin, date: date)
  end

  @doc """
  Gets today's check-in.
  """
  def get_today_checkin do
    get_checkin_by_date(Date.utc_today())
  end

  @doc """
  Creates a daily_checkin.
  """
  def create_checkin(attrs \\ %{}) do
    %DailyCheckin{}
    |> DailyCheckin.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, checkin} -> broadcast_update(checkin, :checkin_created)
      _ -> :ok
    end)
  end

  @doc """
  Updates a daily_checkin.
  """
  def update_checkin(%DailyCheckin{} = daily_checkin, attrs) do
    daily_checkin
    |> DailyCheckin.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, checkin} -> broadcast_update(checkin, :checkin_updated)
      _ -> :ok
    end)
  end

  @doc """
  Creates or updates today's check-in.
  """
  def upsert_today_checkin(attrs) do
    case get_today_checkin() do
      nil -> create_checkin(Map.put(attrs, :date, Date.utc_today()))
      checkin -> update_checkin(checkin, attrs)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking daily_checkin changes.
  """
  def change_checkin(%DailyCheckin{} = daily_checkin, attrs \\ %{}) do
    DailyCheckin.changeset(daily_checkin, attrs)
  end

  @doc """
  Calculates the current streak of consecutive check-ins.
  Returns the number of consecutive days with check-ins, starting from today.
  """
  def calculate_streak do
    checkins =
      DailyCheckin
      |> order_by([desc: :date])
      |> select([c], c.date)
      |> Repo.all()

    case checkins do
      [] ->
        0

      dates ->
        today = Date.utc_today()

        dates
        |> Enum.reduce_while({0, today}, fn date, {streak, expected_date} ->
          if Date.compare(date, expected_date) == :eq do
            {:cont, {streak + 1, Date.add(expected_date, -1)}}
          else
            {:halt, {streak, expected_date}}
          end
        end)
        |> elem(0)
    end
  end
end
