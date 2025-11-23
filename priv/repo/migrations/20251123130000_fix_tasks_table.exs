defmodule Rzeczywiscie.Repo.Migrations.FixTasksTable do
  use Ecto.Migration

  def up do
    # Check if tasks table exists but is missing columns
    # This handles cases where the table was created incorrectly

    # First, try to add missing columns if they don't exist
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='tasks' AND column_name='completed'
      ) THEN
        ALTER TABLE tasks ADD COLUMN completed boolean DEFAULT false;
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='tasks' AND column_name='completed_at'
      ) THEN
        ALTER TABLE tasks ADD COLUMN completed_at timestamp(0);
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='tasks' AND column_name='is_next_action'
      ) THEN
        ALTER TABLE tasks ADD COLUMN is_next_action boolean DEFAULT false;
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='tasks' AND column_name='order'
      ) THEN
        ALTER TABLE tasks ADD COLUMN "order" integer DEFAULT 0;
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='tasks' AND column_name='phase'
      ) THEN
        ALTER TABLE tasks ADD COLUMN phase varchar(255);
      END IF;
    END $$;
    """

    # Add missing indexes if they don't exist
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename='tasks' AND indexname='tasks_completed_index'
      ) THEN
        CREATE INDEX tasks_completed_index ON tasks (completed);
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename='tasks' AND indexname='tasks_is_next_action_index'
      ) THEN
        CREATE INDEX tasks_is_next_action_index ON tasks (is_next_action);
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE tablename='tasks' AND indexname='tasks_project_id_order_index'
      ) THEN
        CREATE INDEX tasks_project_id_order_index ON tasks (project_id, "order");
      END IF;
    END $$;
    """
  end

  def down do
    # Don't remove columns on rollback to preserve data
    :ok
  end
end
