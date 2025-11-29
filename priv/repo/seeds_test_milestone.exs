# Test script to unlock Unicorn milestone
alias Rzeczywiscie.Repo
alias Rzeczywiscie.PixelCanvas.GlobalMilestone
alias Rzeczywiscie.PixelCanvas.UserPixelStats

# Unlock the Unicorn milestone
case Repo.get_by(GlobalMilestone, milestone_type: "pixels_1000") do
  nil ->
    %GlobalMilestone{}
    |> GlobalMilestone.changeset(%{
      milestone_type: "pixels_1000",
      threshold: 1000,
      reward_type: "unicorn",
      unlocked_at: DateTime.utc_now(),
      total_pixels_when_unlocked: 111
    })
    |> Repo.insert!()
    
    IO.puts("✅ Unicorn milestone unlocked!")
  
  _existing ->
    IO.puts("ℹ️ Unicorn milestone already unlocked")
end

# Award unicorn pixel to all users
user_stats = Repo.all(UserPixelStats)

Enum.each(user_stats, fn stats ->
  updated_specials = Map.update(
    stats.special_pixels_available || %{},
    "unicorn",
    1,
    &(&1 + 1)
  )
  
  stats
  |> UserPixelStats.changeset(%{special_pixels_available: updated_specials})
  |> Repo.update!()
end)

IO.puts("✅ Awarded unicorn pixel to #{length(user_stats)} users")

