defmodule Rzeczywiscie.Repo.Migrations.CreateSocialConnections do
  use Ecto.Migration

  def change do
    # People you want to stay connected with
    create table(:social_contacts) do
      add :name, :string, null: false
      add :relationship, :string              # friend, family, colleague
      add :emoji, :string, default: "👤"
      add :contact_frequency_days, :integer, default: 14  # How often you want to connect
      add :preferred_contact_method, :string  # call, text, in_person, video
      add :notes, :text
      add :active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    # Log of actual interactions
    create table(:social_interactions) do
      add :contact_id, references(:social_contacts, on_delete: :nilify_all)
      add :interaction_type, :string, null: false  # call, text, in_person, video, voice_message
      add :duration_minutes, :integer              # How long did you talk?
      add :quality, :integer                       # 1-5 how meaningful was it?
      add :initiated_by_me, :boolean, default: true
      add :location, :string                       # Where? (home, cafe, their place)
      add :left_house, :boolean, default: false    # Did you leave your apartment?
      add :interacted_at, :utc_datetime, null: false
      add :notes, :text
      add :mood_before, :integer                   # 1-5
      add :mood_after, :integer                    # 1-5

      timestamps(type: :utc_datetime)
    end

    create index(:social_interactions, [:contact_id])
    create index(:social_interactions, [:interacted_at])
    create index(:social_interactions, [:left_house])

    # Cat care log (self-care indicator!)
    create table(:cat_care_logs) do
      add :cat_name, :string
      add :activity, :string, null: false  # fed, played, brushed, vet, cuddle
      add :logged_at, :utc_datetime, null: false
      add :duration_minutes, :integer
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:cat_care_logs, [:logged_at])
    create index(:cat_care_logs, [:cat_name])
  end
end
