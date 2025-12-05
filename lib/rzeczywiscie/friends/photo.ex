defmodule Rzeczywiscie.Friends.Photo do
  use Ecto.Schema
  import Ecto.Changeset

  schema "friends_photos" do
    field :user_id, :string
    field :user_color, :string
    field :user_name, :string
    field :image_data, :string
    field :thumbnail_data, :string
    field :content_type, :string, default: "image/jpeg"
    field :file_size, :integer
    field :position, :integer
    field :description, :string

    belongs_to :room, Rzeczywiscie.Friends.Room

    timestamps()
  end

  @doc false
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:user_id, :user_color, :user_name, :image_data, :thumbnail_data, :content_type, :file_size, :room_id, :position, :description])
    |> validate_required([:user_id, :user_color, :image_data])
    |> validate_length(:user_name, max: 20)
    |> validate_length(:description, max: 200)
  end
end

