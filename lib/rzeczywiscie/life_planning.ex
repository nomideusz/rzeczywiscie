defmodule Rzeczywiscie.LifePlanning do
  @moduledoc """
  The LifePlanning context - manages life projects, tasks, and daily check-ins.
  """

  import Ecto.Query, warn: false
  alias Rzeczywiscie.Repo
  alias Rzeczywiscie.LifePlanning.{LifeProject, Task, DailyCheckin, WeeklyReview}

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
  Safe to call during seeding (will skip if PubSub not started).
  """
  def broadcast_update(data, event) do
    try do
      Phoenix.PubSub.broadcast(
        Rzeczywiscie.PubSub,
        @topic,
        {event, data}
      )
    rescue
      ArgumentError -> :ok  # PubSub not started (e.g., during seeding)
    end
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

  @doc """
  Get all tasks with deadlines that are due soon (within 7 days) or overdue.
  """
  def get_urgent_tasks do
    today = Date.utc_today()
    week_from_now = Date.add(today, 7)

    Task
    |> where([t], t.completed == false and not is_nil(t.deadline))
    |> where([t], t.deadline <= ^week_from_now)
    |> order_by([asc: :deadline])
    |> Repo.all()
  end

  @doc """
  Get overdue tasks (deadline has passed and not completed).
  """
  def get_overdue_tasks do
    today = Date.utc_today()

    Task
    |> where([t], t.completed == false and not is_nil(t.deadline))
    |> where([t], t.deadline < ^today)
    |> order_by([asc: :deadline])
    |> Repo.all()
  end

  @doc """
  Get tasks due today.
  """
  def get_today_tasks do
    today = Date.utc_today()

    Task
    |> where([t], t.completed == false and t.deadline == ^today)
    |> order_by([asc: :order])
    |> Repo.all()
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

  ## Weekly Reviews

  @doc """
  Returns the list of weekly_reviews, ordered by week_start_date descending.
  """
  def list_weekly_reviews(limit \\ 12) do
    WeeklyReview
    |> order_by([desc: :week_start_date])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single weekly_review by week_start_date.
  """
  def get_weekly_review_by_date(week_start_date) do
    Repo.get_by(WeeklyReview, week_start_date: week_start_date)
  end

  @doc """
  Gets this week's review.
  """
  def get_this_week_review do
    get_weekly_review_by_date(WeeklyReview.week_start(Date.utc_today()))
  end

  @doc """
  Creates a weekly_review.
  """
  def create_weekly_review(attrs \\ %{}) do
    %WeeklyReview{}
    |> WeeklyReview.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, review} -> broadcast_update(review, :weekly_review_created)
      _ -> :ok
    end)
  end

  @doc """
  Updates a weekly_review.
  """
  def update_weekly_review(%WeeklyReview{} = weekly_review, attrs) do
    weekly_review
    |> WeeklyReview.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, review} -> broadcast_update(review, :weekly_review_updated)
      _ -> :ok
    end)
  end

  @doc """
  Creates or updates this week's review.
  """
  def upsert_this_week_review(attrs) do
    week_start = WeeklyReview.week_start(Date.utc_today())

    case get_weekly_review_by_date(week_start) do
      nil -> create_weekly_review(Map.put(attrs, :week_start_date, week_start))
      review -> update_weekly_review(review, attrs)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking weekly_review changes.
  """
  def change_weekly_review(%WeeklyReview{} = weekly_review, attrs \\ %{}) do
    WeeklyReview.changeset(weekly_review, attrs)
  end

  @doc """
  Gets statistics for the current week.
  Returns tasks completed this week, projects with activity, etc.
  """
  def get_week_stats(week_start_date \\ nil) do
    week_start = week_start_date || WeeklyReview.week_start(Date.utc_today())
    week_end = Date.add(week_start, 6)

    # Get tasks completed this week
    completed_this_week =
      Task
      |> where([t], not is_nil(t.completed_at))
      |> where([t], fragment("DATE(?)", t.completed_at) >= ^week_start)
      |> where([t], fragment("DATE(?)", t.completed_at) <= ^week_end)
      |> Repo.all()

    # Get unique projects with activity
    active_project_ids =
      completed_this_week
      |> Enum.map(& &1.project_id)
      |> Enum.uniq()

    # Get stalled projects (no tasks completed in 2+ weeks)
    two_weeks_ago = Date.add(Date.utc_today(), -14)

    all_projects = list_projects()

    stalled_projects =
      all_projects
      |> Enum.filter(fn project ->
        tasks = list_tasks(project.id)
        has_incomplete = Enum.any?(tasks, fn t -> !t.completed end)

        last_completion =
          tasks
          |> Enum.filter(& &1.completed_at)
          |> Enum.map(& DateTime.to_date(&1.completed_at))
          |> Enum.max(Date, fn -> Date.add(Date.utc_today(), -365) end)

        has_incomplete && Date.compare(last_completion, two_weeks_ago) == :lt
      end)

    %{
      completed_tasks_count: length(completed_this_week),
      active_projects_count: length(active_project_ids),
      active_project_ids: active_project_ids,
      stalled_projects: stalled_projects,
      week_start: week_start,
      week_end: week_end
    }
  end

  ## Progress Analytics

  @doc """
  Gets completion trend data for the last N days.
  Returns a list of %{date, completed_count} maps.
  """
  def get_completion_trend(days_back \\ 30) do
    start_date = Date.add(Date.utc_today(), -days_back)

    Task
    |> where([t], not is_nil(t.completed_at))
    |> where([t], fragment("DATE(?)", t.completed_at) >= ^start_date)
    |> select([t], %{
      date: fragment("DATE(?)", t.completed_at),
      count: count(t.id)
    })
    |> group_by([t], fragment("DATE(?)", t.completed_at))
    |> order_by([asc: fragment("DATE(?)", :completed_at)])
    |> Repo.all()
  end

  @doc """
  Gets weekly completion stats for the last N weeks.
  Returns a list of %{week_start, completed_count} maps.
  """
  def get_weekly_completion_trend(weeks_back \\ 12) do
    start_date = Date.add(Date.utc_today(), -(weeks_back * 7))

    completed_tasks =
      Task
      |> where([t], not is_nil(t.completed_at))
      |> where([t], fragment("DATE(?)", t.completed_at) >= ^start_date)
      |> select([t], fragment("DATE(?)", t.completed_at))
      |> Repo.all()

    # Group by week
    completed_tasks
    |> Enum.group_by(fn date ->
      WeeklyReview.week_start(date)
    end)
    |> Enum.map(fn {week_start, dates} ->
      %{week_start: week_start, count: length(dates)}
    end)
    |> Enum.sort_by(& &1.week_start, Date)
  end

  @doc """
  Gets completion stats per project.
  Returns a list of %{project_name, emoji, completed_count, total_count, completion_rate}.
  """
  def get_project_completion_stats do
    projects = list_projects()

    projects
    |> Enum.map(fn project ->
      tasks = list_tasks(project.id)
      total = length(tasks)
      completed = Enum.count(tasks, & &1.completed)
      completion_rate = if total > 0, do: completed / total * 100, else: 0

      %{
        project_id: project.id,
        project_name: project.name,
        emoji: project.emoji || "📋",
        completed_count: completed,
        total_count: total,
        completion_rate: Float.round(completion_rate, 1)
      }
    end)
    |> Enum.sort_by(& &1.completion_rate, :desc)
  end

  @doc """
  Gets task completion velocity (average tasks completed per week).
  """
  def get_completion_velocity(weeks_back \\ 4) do
    start_date = Date.add(Date.utc_today(), -(weeks_back * 7))

    completed_count =
      Task
      |> where([t], not is_nil(t.completed_at))
      |> where([t], fragment("DATE(?)", t.completed_at) >= ^start_date)
      |> select([t], count(t.id))
      |> Repo.one()

    velocity = if weeks_back > 0, do: completed_count / weeks_back, else: 0
    Float.round(velocity, 1)
  end

  @doc """
  Gets productivity insights and statistics.
  """
  def get_productivity_insights do
    total_projects = length(list_projects())
    total_tasks = Repo.aggregate(Task, :count, :id)
    completed_tasks = Repo.one(from t in Task, where: t.completed == true, select: count(t.id))
    overdue_count = length(get_overdue_tasks())
    urgent_count = length(get_urgent_tasks())

    %{
      total_projects: total_projects,
      total_tasks: total_tasks,
      completed_tasks: completed_tasks,
      pending_tasks: total_tasks - completed_tasks,
      completion_rate: if(total_tasks > 0, do: Float.round(completed_tasks / total_tasks * 100, 1), else: 0),
      overdue_count: overdue_count,
      urgent_count: urgent_count,
      velocity: get_completion_velocity(4)
    }
  end
end
