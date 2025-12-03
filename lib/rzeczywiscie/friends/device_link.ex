defmodule Rzeczywiscie.Friends.DeviceLink do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_device_links" do
    field :device_fingerprint, :string
    field :master_user_id, :string

    timestamps()
  end

  @doc false
  def changeset(device_link, attrs) do
    device_link
    |> cast(attrs, [:device_fingerprint, :master_user_id])
    |> validate_required([:device_fingerprint, :master_user_id])
    |> unique_constraint(:device_fingerprint)
  end
end

