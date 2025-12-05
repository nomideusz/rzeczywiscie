defmodule Rzeczywiscie.Friends.TextCard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_text_cards" do
    field :user_id, :string
    field :user_color, :string
    field :content, :string
    field :background_color, :string, default: "#1a1a2e"
    field :text_color, :string, default: "#ffffff"
    field :font_style, :string, default: "normal"
    field :position, :integer

    timestamps()
  end

  @font_styles ~w(normal serif mono handwritten bold)

  @doc false
  def changeset(text_card, attrs) do
    text_card
    |> cast(attrs, [:user_id, :user_color, :content, :background_color, :text_color, :font_style, :position])
    |> validate_required([:user_id, :content])
    |> validate_length(:content, min: 1, max: 500)
    |> validate_inclusion(:font_style, @font_styles)
  end

  def font_styles, do: @font_styles
end

