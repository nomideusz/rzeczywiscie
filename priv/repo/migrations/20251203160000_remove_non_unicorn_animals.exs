defmodule Rzeczywiscie.Repo.Migrations.RemoveNonUnicornAnimals do
  use Ecto.Migration

  def up do
    # Delete all special pixels that are not unicorns
    # (chicken, pegasus, whale were temporarily added but frontend was reverted)
    execute """
    DELETE FROM pixels 
    WHERE is_special = true 
    AND (special_type NOT LIKE 'unicorn%' OR special_type IS NULL)
    """
  end

  def down do
    # Cannot restore deleted data
    :ok
  end
end

