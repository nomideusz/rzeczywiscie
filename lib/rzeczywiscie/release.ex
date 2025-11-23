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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
