defmodule Rzeczywiscie.LifeTracker.Milestone do
  use Ecto.Schema
  import Ecto.Changeset

  schema "milestones" do
    field :title, :string
    field :description, :string
    field :date_achieved, :date
    field :target_date, :date

    belongs_to :project, Rzeczywiscie.LifeTracker.Project

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:project_id, :title, :description, :date_achieved, :target_date])
    |> validate_required([:title])
    |> foreign_key_constraint(:project_id)
  end
end
