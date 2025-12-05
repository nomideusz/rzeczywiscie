defmodule Rzeczywiscie.Friends.TextCard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_text_cards" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :content, :string
    field :background_color, :string, default: "#1a1a2e"
    field :text_color, :string, default: "#ffffff"
    field :font_style, :string, default: "normal"
    field :position, :integer

    belongs_to :room, Rzeczywiscie.Friends.Room

    timestamps()
  end

  @doc false
  def changeset(text_card, attrs) do
    text_card
    |> cast(attrs, [:user_id, :user_color, :user_name, :content, :background_color, :text_color, :font_style, :position, :room_id])
    |> validate_required([:user_id, :content])
    |> validate_length(:content, min: 1, max: 500)
    |> validate_length(:user_name, max: 20)
  end
end

