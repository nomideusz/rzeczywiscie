# Give unicorn pixel to ALL users for testing
# Run with: mix run priv/repo/give_unicorn_all.exs

alias Rzeczywiscie.Repo
alias Rzeczywiscie.PixelCanvas.UserPixelStats
alias Rzeczywiscie.PixelCanvas.GlobalMilestone

IO.puts("Giving unicorn pixel to all users...")

# Get all user stats
users = Repo.all(UserPixelStats)

if users == [] do
  IO.puts("⚠️  No users found. Place at least one pixel first to create a user record.")
else
  Enum.each(users, fn stats ->
    current_specials = stats.special_pixels_available || %{}
    updated_specials = Map.put(current_specials, "unicorn", 1)
    
    stats
    |> UserPixelStats.changeset(%{special_pixels_available: updated_specials})
    |> Repo.update!()
    
    IO.puts("✓ Gave unicorn to user #{stats.user_id}")
  end)
end

# Mark the milestone as unlocked
case Repo.get_by(GlobalMilestone, milestone_type: "pixels_1000") do
  nil ->
    %GlobalMilestone{}
    |> GlobalMilestone.changeset(%{
      milestone_type: "pixels_1000",
      threshold: 1000,
      reward_type: "unicorn",
      unlocked_at: DateTime.utc_now(),
      total_pixels_when_unlocked: 1000
    })
    |> Repo.insert!()
    IO.puts("✓ Marked Unicorn milestone as unlocked")
  
  _milestone ->
    IO.puts("✓ Unicorn milestone already unlocked")
end

IO.puts("\n🦄 All users now have 1 Unicorn pixel available!")
IO.puts("Refresh the page to see it in the UI.")

