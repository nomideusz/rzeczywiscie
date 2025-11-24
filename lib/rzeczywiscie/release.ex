defmodule Rzeczywiscie.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :rzeczywiscie

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    # First ensure migrations are run
    IO.puts("Ensuring migrations are up to date...")
    migrate()

    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(
      List.first(repos()),
      fn _repo ->
        # Run the life planning seed script
        seed_script = Path.join([:code.priv_dir(@app), "repo", "seeds_life_planning.exs"])
        if File.exists?(seed_script) do
          IO.puts("Running seed script: #{seed_script}")
          Code.eval_file(seed_script)
        else
          IO.puts("Seed script not found: #{seed_script}")
        end
      end
    )
  end

  def fix_tasks_migration do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(
      List.first(repos()),
      fn repo ->
        IO.puts("Marking migration 20251123120001 as complete...")
        repo.query!(
          "INSERT INTO schema_migrations (version, inserted_at) VALUES (20251123120001, NOW()) ON CONFLICT DO NOTHING"
        )
        IO.puts("✓ Migration marked as complete")
        IO.puts("Now run: Rzeczywiscie.Release.seed()")
      end
    )
  end

  def clean_life_planning_tables do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(
      List.first(repos()),
      fn repo ->
        IO.puts("Dropping life planning tables...")
        repo.query!("DROP TABLE IF EXISTS tasks CASCADE")
        repo.query!("DROP TABLE IF EXISTS life_projects CASCADE")
        repo.query!("DROP TABLE IF EXISTS daily_checkins CASCADE")

        IO.puts("Removing migration records...")
        repo.query!("DELETE FROM schema_migrations WHERE version >= '20251123120000' AND version <= '20251123130000'")

        IO.puts("✓ Cleanup complete")
        IO.puts("Now run: Rzeczywiscie.Release.seed()")
      end
    )
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
