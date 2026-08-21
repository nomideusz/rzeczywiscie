defmodule Rzeczywiscie.Repo.Migrations.CreatePropertyAlerts do
  use Ecto.Migration

  def change do
    # Saved searches the owner wants to be emailed about. Criteria is the same
    # filter map the listing page uses, so an alert matches exactly what the
    # equivalent /real-estate filter shows.
    create table(:property_alerts) do
      add :name, :string, null: false
      add :criteria, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true
      # Highest property id at creation time. Everything at or below it is
      # backlog the alert must never mail. Ids are monotonic, so this is exact
      # where an inserted_at comparison would be ambiguous within a second.
      add :since_property_id, :bigint, null: false, default: 0
      add :last_run_at, :utc_datetime
      add :last_notified_at, :utc_datetime
      add :notified_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:property_alerts, [:enabled])

    # Ledger of what each alert has already reported. This is what makes the
    # worker idempotent: a re-run, a retry or an overlapping cron tick can
    # never send the same listing twice.
    create table(:property_alert_matches) do
      add :alert_id, references(:property_alerts, on_delete: :delete_all), null: false
      add :property_id, references(:properties, on_delete: :delete_all), null: false
      add :notified_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:property_alert_matches, [:alert_id, :property_id])
    create index(:property_alert_matches, [:property_id])
    create index(:property_alert_matches, [:alert_id, :notified_at])
  end
end
