defmodule Rzeczywiscie.Repo.Migrations.CreateFriendsTextCards do
  use Ecto.Migration

  def change do
    create table(:friends_text_cards) do
      add :user_id, :string, null: false
      add :user_color, :string
      add :content, :text, null: false
      add :background_color, :string, default: "#1a1a2e"
      add :text_color, :string, default: "#ffffff"
      add :font_style, :string, default: "normal"
      add :position, :integer

      timestamps()
    end

    create index(:friends_text_cards, [:user_id, :position])
  end
end

