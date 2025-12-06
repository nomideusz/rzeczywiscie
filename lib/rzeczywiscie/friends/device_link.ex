defmodule Rzeczywiscie.Friends.DeviceLink do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_device_links" do
    field :device_fingerprint, :string
    field :browser_id, :string           # localStorage UUID - unique per browser
    field :master_user_id, :string       # Linked identity - same for linked browsers
    field :user_name, :string
    field :link_code, :string            # Temporary 4-digit code for linking
    field :link_code_expires_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:device_fingerprint, :browser_id, :master_user_id, :user_name])
    |> validate_required([:browser_id, :master_user_id])
    |> validate_length(:user_name, max: 20)
    |> unique_constraint(:browser_id)
  end

  @doc """
  Changeset for updating just the user_name.
  """
  def name_changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:user_name])
    |> validate_length(:user_name, max: 20)
  end

  @doc """
  Changeset for link code operations.
  """
  def link_code_changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:link_code, :link_code_expires_at])
  end

  @doc """
  Changeset for linking to another account.
  """
  def link_changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:master_user_id, :user_name])
  end
end
