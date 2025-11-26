defmodule Rzeczywiscie.Repo.Migrations.CreateMoodLogs do
  use Ecto.Migration

  def change do
    # Quick mood/energy check-ins throughout the day
    create table(:mood_logs) do
      add :logged_at, :utc_datetime, null: false
      add :mood, :integer, null: false           # 1-5 scale
      add :energy, :integer                      # 1-5 scale
      add :anxiety, :integer                     # 1-5 scale
      add :focus, :integer                       # 1-5 scale

      # Context flags (quick taps)
      add :took_meds, :boolean
      add :slept_well, :boolean
      add :ate_today, :boolean
      add :exercised, :boolean
      add :went_outside, :boolean
      add :talked_to_someone, :boolean
      add :worked_on_goals, :boolean

      # Job-specific
      add :job_dread, :integer                   # 1-10 how much do you dread work today?
      add :at_work, :boolean

      # Financial
      add :spent_money_impulsively, :boolean
      add :worried_about_money, :boolean

      add :notes, :text
      add :gratitude, :text                      # One thing you're grateful for

      timestamps(type: :utc_datetime)
    end

    create index(:mood_logs, [:logged_at])

    # Honest daily check-in (replaces generic one)
    create table(:honest_checkins) do
      add :date, :date, null: false
      add :completed_at, :utc_datetime

      # Medication honesty
      add :meds_taken_as_prescribed, :boolean
      add :meds_notes, :text

      # Job situation
      add :job_dread_level, :integer             # 1-10
      add :applied_to_jobs, :integer, default: 0
      add :job_search_minutes, :integer, default: 0
      add :job_notes, :text

      # Financial honesty
      add :unnecessary_spending, :decimal, precision: 10, scale: 2
      add :debt_payment_made, :boolean
      add :money_notes, :text

      # Social/isolation
      add :talked_to_friend, :boolean
      add :left_apartment, :boolean
      add :loneliness_level, :integer            # 1-10

      # Cat care (accountability anchor)
      add :fed_cats, :boolean
      add :played_with_cats, :boolean

      # Wins and struggles
      add :small_win, :text
      add :biggest_struggle, :text
      add :tomorrow_intention, :text

      # Overall
      add :overall_day_rating, :integer          # 1-10
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:honest_checkins, [:date])
    create index(:honest_checkins, [:completed_at])
  end
end
