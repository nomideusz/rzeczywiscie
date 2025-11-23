# Script for populating the database with initial life planning data
# Run: mix run priv/repo/seeds_life_planning.exs

alias Rzeczywiscie.LifePlanning

# Clear existing data (optional - comment out if you want to keep existing data)
# Rzeczywiscie.Repo.delete_all(Rzeczywiscie.LifePlanning.Task)
# Rzeczywiscie.Repo.delete_all(Rzeczywiscie.LifePlanning.LifeProject)
# Rzeczywiscie.Repo.delete_all(Rzeczywiscie.LifePlanning.DailyCheckin)

IO.puts("Creating life projects...")

# Project 1: Apartment
{:ok, apartment} = LifePlanning.create_project(%{
  name: "Apartment",
  emoji: "🏠",
  timeline_months: 3,
  color: "#3B82F6",
  order: 0
})

IO.puts("✓ Created: #{apartment.name}")

# Tasks for Apartment
apartment_tasks = [
  %{title: "Research market prices in my area", phase: "Phase 1: Decision", project_id: apartment.id, order: 0},
  %{title: "Calculate costs of selling vs renting", phase: "Phase 1: Decision", project_id: apartment.id, order: 1},
  %{title: "Talk to 2 friends who sold/rented recently", phase: "Phase 1: Decision", project_id: apartment.id, order: 2},
  %{title: "Make final decision: sell or rent", phase: "Phase 1: Decision", project_id: apartment.id, order: 3},
  %{title: "Deep clean living room", phase: "Phase 2: Preparation", project_id: apartment.id, order: 4, is_next_action: true},
  %{title: "Deep clean bedroom", phase: "Phase 2: Preparation", project_id: apartment.id, order: 5},
  %{title: "Deep clean kitchen and bathroom", phase: "Phase 2: Preparation", project_id: apartment.id, order: 6},
  %{title: "Fix broken cabinet door", phase: "Phase 2: Preparation", project_id: apartment.id, order: 7},
  %{title: "Take professional photos", phase: "Phase 2: Preparation", project_id: apartment.id, order: 8},
  %{title: "Choose and contact realtor", phase: "Phase 3: Listing", project_id: apartment.id, order: 9},
  %{title: "Set asking price", phase: "Phase 3: Listing", project_id: apartment.id, order: 10},
  %{title: "List property online", phase: "Phase 3: Listing", project_id: apartment.id, order: 11},
]

Enum.each(apartment_tasks, fn task_params ->
  LifePlanning.create_task(task_params)
end)

IO.puts("  ✓ Added #{length(apartment_tasks)} tasks")

# Project 2: Cats
{:ok, cats} = LifePlanning.create_project(%{
  name: "Cats - Find Good Homes",
  emoji: "🐱",
  timeline_months: 2,
  color: "#F59E0B",
  order: 1
})

IO.puts("✓ Created: #{cats.name}")

cats_tasks = [
  %{title: "Research local adoption agencies and shelters", phase: "Phase 1: Research", project_id: cats.id, order: 0, is_next_action: true},
  %{title: "Ask friends/family if anyone wants to adopt", phase: "Phase 1: Research", project_id: cats.id, order: 1},
  %{title: "Create detailed profiles for each cat (personality, needs, photos)", phase: "Phase 1: Research", project_id: cats.id, order: 2},
  %{title: "Post adoption ads on Facebook groups", phase: "Phase 2: Outreach", project_id: cats.id, order: 3},
  %{title: "Post on local adoption websites", phase: "Phase 2: Outreach", project_id: cats.id, order: 4},
  %{title: "Contact local animal rescue organizations", phase: "Phase 2: Outreach", project_id: cats.id, order: 5},
  %{title: "Screen potential adopters (first call)", phase: "Phase 3: Screening", project_id: cats.id, order: 6},
  %{title: "Arrange meet-and-greet with serious candidates", phase: "Phase 3: Screening", project_id: cats.id, order: 7},
  %{title: "Complete adoption paperwork and handover", phase: "Phase 3: Screening", project_id: cats.id, order: 8},
]

Enum.each(cats_tasks, fn task_params ->
  LifePlanning.create_task(task_params)
end)

IO.puts("  ✓ Added #{length(cats_tasks)} tasks")

# Project 3: Job
{:ok, job} = LifePlanning.create_project(%{
  name: "Job Transition",
  emoji: "💼",
  timeline_months: 4,
  color: "#10B981",
  order: 2
})

IO.puts("✓ Created: #{job.name}")

job_tasks = [
  %{title: "Update CV with recent accomplishments", phase: "Phase 1: Preparation", project_id: job.id, order: 0, is_next_action: true},
  %{title: "Update LinkedIn profile", phase: "Phase 1: Preparation", project_id: job.id, order: 1},
  %{title: "Identify 3-5 target companies or roles", phase: "Phase 1: Preparation", project_id: job.id, order: 2},
  %{title: "Research job markets in potential destination countries", phase: "Phase 2: Research", project_id: job.id, order: 3},
  %{title: "Network with people working abroad (LinkedIn, forums)", phase: "Phase 2: Research", project_id: job.id, order: 4},
  %{title: "Prepare cover letter template", phase: "Phase 2: Research", project_id: job.id, order: 5},
  %{title: "Start applying to remote jobs", phase: "Phase 3: Applications", project_id: job.id, order: 6},
  %{title: "Give notice to current employer (after securing new role)", phase: "Phase 4: Transition", project_id: job.id, order: 7},
  %{title: "Complete handover documentation at current job", phase: "Phase 4: Transition", project_id: job.id, order: 8},
]

Enum.each(job_tasks, fn task_params ->
  LifePlanning.create_task(task_params)
end)

IO.puts("  ✓ Added #{length(job_tasks)} tasks")

# Project 4: Moving
{:ok, moving} = LifePlanning.create_project(%{
  name: "Moving Out of Poland",
  emoji: "✈️",
  timeline_months: 6,
  color: "#8B5CF6",
  order: 3
})

IO.puts("✓ Created: #{moving.name}")

moving_tasks = [
  %{title: "Research visa requirements for target countries", phase: "Phase 1: Planning", project_id: moving.id, order: 0, is_next_action: true},
  %{title: "Shortlist 3-5 potential cities/countries", phase: "Phase 1: Planning", project_id: moving.id, order: 1},
  %{title: "Calculate cost of living in each location", phase: "Phase 1: Planning", project_id: moving.id, order: 2},
  %{title: "Make final decision on destination", phase: "Phase 1: Planning", project_id: moving.id, order: 3},
  %{title: "Apply for visa/work permit", phase: "Phase 2: Documentation", project_id: moving.id, order: 4},
  %{title: "Gather required documents (birth certificate, diplomas, etc.)", phase: "Phase 2: Documentation", project_id: moving.id, order: 5},
  %{title: "Get international driver's license", phase: "Phase 2: Documentation", project_id: moving.id, order: 6},
  %{title: "Research housing options in destination", phase: "Phase 3: Logistics", project_id: moving.id, order: 7},
  %{title: "Book temporary accommodation for first month", phase: "Phase 3: Logistics", project_id: moving.id, order: 8},
  %{title: "Book flight tickets", phase: "Phase 3: Logistics", project_id: moving.id, order: 9},
  %{title: "Cancel Polish services (internet, utilities, subscriptions)", phase: "Phase 4: Closing Out", project_id: moving.id, order: 10},
  %{title: "Transfer/close bank accounts", phase: "Phase 4: Closing Out", project_id: moving.id, order: 11},
  %{title: "Deregister from Polish residence", phase: "Phase 4: Closing Out", project_id: moving.id, order: 12},
  %{title: "Pack belongings / arrange shipping", phase: "Phase 4: Closing Out", project_id: moving.id, order: 13},
  %{title: "Say goodbye to friends and family", phase: "Phase 4: Closing Out", project_id: moving.id, order: 14},
]

Enum.each(moving_tasks, fn task_params ->
  LifePlanning.create_task(task_params)
end)

IO.puts("  ✓ Added #{length(moving_tasks)} tasks")

IO.puts("")
IO.puts("🎉 Successfully created 4 projects with tasks!")
IO.puts("")
IO.puts("Visit http://localhost:4001/life to see your Life Reboot Tracker!")
