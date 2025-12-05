defmodule Rzeczywiscie.Repo.Migrations.AddUserNameToTextCards do
  use Ecto.Migration

  def change do
    alter table(:friends_text_cards) do
      add :user_name, :string
    end
  end
end

