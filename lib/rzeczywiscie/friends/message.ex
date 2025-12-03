defmodule Rzeczywiscie.Friends.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_messages" do
    field :user_id, :string
    field :user_color, :string
    field :content, :string

    belongs_to :room, Rzeczywiscie.Friends.Room

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:user_id, :user_color, :content, :room_id])
    |> validate_required([:user_id, :user_color, :content, :room_id])
    |> validate_length(:content, min: 1, max: 500)
  end
end

