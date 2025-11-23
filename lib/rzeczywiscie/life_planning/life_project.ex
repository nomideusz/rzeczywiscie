defmodule Rzeczywiscie.LifePlanning.LifeProject do
  use Ecto.Schema
  import Ecto.Changeset

  schema "life_projects" do
    field :name, :string
    field :emoji, :string
    field :timeline_months, :integer
    field :color, :string
    field :order, :integer, default: 0
    field :archived, :boolean, default: false

    has_many :tasks, Rzeczywiscie.LifePlanning.Task, foreign_key: :project_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(life_project, attrs) do
    life_project
    |> cast(attrs, [:name, :emoji, :timeline_months, :color, :order, :archived])
    |> validate_required([:name])
    |> validate_number(:timeline_months, greater_than: 0)
    |> validate_number(:order, greater_than_or_equal_to: 0)
  end
end
