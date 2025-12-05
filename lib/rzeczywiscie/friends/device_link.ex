defmodule Rzeczywiscie.Friends.DeviceLink do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_device_links" do
    field :device_fingerprint, :string
    field :master_user_id, :string
    field :user_name, :string

    timestamps()
  end

  @doc false
  def changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:device_fingerprint, :master_user_id, :user_name])
    |> validate_required([:device_fingerprint])
    |> validate_length(:user_name, max: 20)
    |> unique_constraint(:device_fingerprint)
  end

  @doc """
  Changeset for updating just the user_name.
  """
  def name_changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:user_name])
    |> validate_length(:user_name, max: 20)
  end
end

