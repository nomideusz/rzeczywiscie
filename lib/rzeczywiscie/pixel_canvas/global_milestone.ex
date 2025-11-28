defmodule Rzeczywiscie.PixelCanvas.GlobalMilestone do
  use Ecto.Schema
  import Ecto.Changeset

  schema "global_milestones" do
    field :milestone_type, :string
    field :threshold, :integer
    field :reward_type, :string
    field :unlocked_at, :utc_datetime
    field :total_pixels_when_unlocked, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:milestone_type, :threshold, :reward_type, :unlocked_at, :total_pixels_when_unlocked])
    |> validate_required([:milestone_type, :threshold, :reward_type])
    |> unique_constraint(:milestone_type)
  end
end

