# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Rzeczywiscie.Repo.insert!(%Rzeczywiscie.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Rzeczywiscie.Repo
alias Rzeczywiscie.LifeTracker.{Project, Task}

# Clear existing life tracker data
Repo.delete_all(Task)
Repo.delete_all(Project)

IO.puts("Seeding Life Tracker projects...")

# Project 1: Apartment
apartment = Repo.insert!(%Project{
  title: "🏠 Apartment Decision",
  description: "Decide whether to sell or rent the apartment, then execute the plan",
  color: "#3b82f6",
  status: "active",
  progress_pct: 0,
  order: 1,
  target_date: ~D[2026-03-01]
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Research rental market rates in the area",
  phase: "Decision",
  status: "not_started",
  order: 1,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Research selling prices for similar apartments",
  phase: "Decision",
  status: "not_started",
  order: 2,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Calculate financial impact of selling vs renting",
  phase: "Decision",
  status: "not_started",
  order: 3,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Make final decision: sell or rent",
  phase: "Decision",
  status: "not_started",
  order: 4,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Deep clean living room and bedroom",
  phase: "Preparation",
  status: "not_started",
  order: 5,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Deep clean kitchen and bathroom",
  phase: "Preparation",
  status: "not_started",
  order: 6,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Declutter and organize all rooms",
  phase: "Preparation",
  status: "not_started",
  order: 7,
  estimated_days: 4
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Make minor repairs (fix broken items, touch up paint)",
  phase: "Preparation",
  status: "not_started",
  order: 8,
  estimated_days: 5
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Take professional photos",
  phase: "Listing",
  status: "not_started",
  order: 9,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: apartment.id,
  title: "Contact real estate agent or prepare listing",
  phase: "Listing",
  status: "not_started",
  order: 10,
  estimated_days: 2
})

# Project 2: Cats
cats = Repo.insert!(%Project{
  title: "🐱 Find Home for Cats",
  description: "Find loving, safe homes for the cats before moving",
  color: "#f59e0b",
  status: "active",
  progress_pct: 0,
  order: 2,
  target_date: ~D[2026-02-15]
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "List cats' personalities, needs, and medical history",
  phase: "Planning",
  status: "not_started",
  order: 1,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Take good photos of each cat",
  phase: "Planning",
  status: "not_started",
  order: 2,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Research reputable adoption organizations",
  phase: "Planning",
  status: "not_started",
  order: 3,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Ask friends/family if they can adopt",
  phase: "Outreach",
  status: "not_started",
  order: 4,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Post adoption listings online (local groups, forums)",
  phase: "Outreach",
  status: "not_started",
  order: 5,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Contact local shelters and rescue organizations",
  phase: "Outreach",
  status: "not_started",
  order: 6,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Screen potential adopters (home visits, interviews)",
  phase: "Placement",
  status: "not_started",
  order: 7,
  estimated_days: 7
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Arrange trial periods with potential families",
  phase: "Placement",
  status: "not_started",
  order: 8,
  estimated_days: 5
})

Repo.insert!(%Task{
  project_id: cats.id,
  title: "Finalize adoptions and say goodbye",
  phase: "Placement",
  status: "not_started",
  order: 9,
  estimated_days: 2
})

# Project 3: Job
job = Repo.insert!(%Project{
  title: "💼 Job Transition",
  description: "Plan exit from current job and prepare for next opportunity",
  color: "#10b981",
  status: "active",
  progress_pct: 0,
  order: 3,
  target_date: ~D[2026-04-01]
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Review employment contract (notice period, obligations)",
  phase: "Planning",
  status: "not_started",
  order: 1,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Calculate financial runway (savings needed before quitting)",
  phase: "Planning",
  status: "not_started",
  order: 2,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Update CV/resume with recent accomplishments",
  phase: "Preparation",
  status: "not_started",
  order: 3,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Update LinkedIn profile and portfolio",
  phase: "Preparation",
  status: "not_started",
  order: 4,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Research job markets in target countries",
  phase: "Research",
  status: "not_started",
  order: 5,
  estimated_days: 5
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Reach out to professional network about opportunities",
  phase: "Networking",
  status: "not_started",
  order: 6,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Decide on resignation date",
  phase: "Exit",
  status: "not_started",
  order: 7,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Draft resignation letter",
  phase: "Exit",
  status: "not_started",
  order: 8,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Submit resignation",
  phase: "Exit",
  status: "not_started",
  order: 9,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: job.id,
  title: "Complete knowledge transfer and handover",
  phase: "Exit",
  status: "not_started",
  order: 10,
  estimated_days: 14
})

# Project 4: Moving Out of Poland
moving = Repo.insert!(%Project{
  title: "✈️ Move Out of Poland",
  description: "Research destinations, handle visa/immigration, and plan relocation",
  color: "#8b5cf6",
  status: "active",
  progress_pct: 0,
  order: 4,
  target_date: ~D[2026-06-01]
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "List target countries and key criteria (job market, language, culture, cost)",
  phase: "Research",
  status: "not_started",
  order: 1,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Research visa/work permit requirements for each country",
  phase: "Research",
  status: "not_started",
  order: 2,
  estimated_days: 5
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Research cost of living and quality of life",
  phase: "Research",
  status: "not_started",
  order: 3,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Narrow down to top 2-3 destinations",
  phase: "Decision",
  status: "not_started",
  order: 4,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Make final country selection",
  phase: "Decision",
  status: "not_started",
  order: 5,
  estimated_days: 1
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Gather required documents (birth certificate, diplomas, etc.)",
  phase: "Documentation",
  status: "not_started",
  order: 6,
  estimated_days: 5
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Get documents translated and notarized if needed",
  phase: "Documentation",
  status: "not_started",
  order: 7,
  estimated_days: 7
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Apply for visa/work permit",
  phase: "Visa",
  status: "not_started",
  order: 8,
  estimated_days: 14
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Book temporary accommodation for first month",
  phase: "Logistics",
  status: "not_started",
  order: 9,
  estimated_days: 3
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Research shipping options for belongings",
  phase: "Logistics",
  status: "not_started",
  order: 10,
  estimated_days: 2
})

Repo.insert!(%Task{
  project_id: moving.id,
  title: "Book flight",
  phase: "Logistics",
  status: "not_started",
  order: 11,
  estimated_days: 1
})

IO.puts("✅ Seeded 4 projects with #{Repo.aggregate(Task, :count)} tasks total!")
IO.puts("")
IO.puts("Projects created:")
IO.puts("  1. 🏠 Apartment Decision - #{Enum.count(Repo.all(from t in Task, where: t.project_id == ^apartment.id))} tasks")
IO.puts("  2. 🐱 Find Home for Cats - #{Enum.count(Repo.all(from t in Task, where: t.project_id == ^cats.id))} tasks")
IO.puts("  3. 💼 Job Transition - #{Enum.count(Repo.all(from t in Task, where: t.project_id == ^job.id))} tasks")
IO.puts("  4. ✈️ Move Out of Poland - #{Enum.count(Repo.all(from t in Task, where: t.project_id == ^moving.id))} tasks")
IO.puts("")
IO.puts("Visit http://localhost:4001/forward to see your dashboard!")
