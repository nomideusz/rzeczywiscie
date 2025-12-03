defmodule Rzeczywiscie.Repo.Migrations.AddUserNameToFriends do
  use Ecto.Migration

  def change do
    alter table(:friends_messages) do
      add :user_name, :string
    end

    alter table(:friends_photos) do
      add :user_name, :string
    end
  end
end

