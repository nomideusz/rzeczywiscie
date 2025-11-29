# Quick script to give yourself a unicorn pixel for testing
# Run with: mix run priv/repo/give_unicorn.exs

alias Rzeczywiscie.Repo
alias Rzeczywiscie.PixelCanvas.UserPixelStats
alias Rzeczywiscie.PixelCanvas.GlobalMilestone

# Get your user_id (replace with your actual device fingerprint hash)
# You can find it in the browser console or just use a placeholder for testing
user_id = "test_user_123"

IO.puts("Giving unicorn pixel to user: #{user_id}")

# Create or update user stats to have 1 unicorn available
case Repo.get_by(UserPixelStats, user_id: user_id) do
  nil ->
    %UserPixelStats{}
    |> UserPixelStats.changeset(%{
      user_id: user_id,
      pixels_placed: 0,
      special_pixels_available: %{"unicorn" => 1}
    })
    |> Repo.insert()
    IO.puts("✓ Created stats for #{user_id} with 1 unicorn")

  stats ->
    current_specials = stats.special_pixels_available || %{}
    updated_specials = Map.put(current_specials, "unicorn", 1)
    
    stats
    |> UserPixelStats.changeset(%{special_pixels_available: updated_specials})
    |> Repo.update()
    IO.puts("✓ Updated #{user_id} to have 1 unicorn")
end

# Also mark the milestone as unlocked (optional, just for visual confirmation)
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
    |> Repo.insert()
    IO.puts("✓ Marked Unicorn milestone as unlocked")
  
  _milestone ->
    IO.puts("✓ Unicorn milestone already unlocked")
end

IO.puts("\n🦄 You now have 1 Unicorn pixel available!")
IO.puts("Refresh the page to see it in the UI.")

