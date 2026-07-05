defmodule Rzeczywiscie.Repo.Migrations.SimplifyPixelCanvas do
  use Ecto.Migration

  def up do
    # Fresh start: wipe the board and drop the gamification layer
    # (unicorns, mega/massive pixels, per-user progression, milestones)
    execute "DELETE FROM pixels"

    alter table(:pixels) do
      remove :is_massive
      remove :pixel_tier
      remove :is_special
      remove :special_type
      remove :claimer_name
      remove :claimer_color
      remove :parent_pixel_id
    end

    drop table(:user_pixel_stats)
    drop table(:global_milestones)
  end

  def down do
    raise "irreversible: gamification tables and pixel history were dropped"
  end
end
