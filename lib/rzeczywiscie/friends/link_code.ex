defmodule Rzeczywiscie.Friends.LinkCode do
  use Ecto.Schema
  import Ecto.Changeset

  @code_length 6
  @code_validity_minutes 5

  schema "friends_link_codes" do
    field :code, :string
    field :user_id, :string
    field :expires_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(link_code, attrs) do
    link_code
    |> cast(attrs, [:code, :user_id, :expires_at])
    |> validate_required([:code, :user_id, :expires_at])
    |> unique_constraint(:code)
  end

  @doc """
  Generates a random alphanumeric code (uppercase, easy to type).
  """
  def generate_code do
    chars = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end

  @doc """
  Returns the expiration datetime for a new code.
  """
  def expiration_time do
    DateTime.utc_now()
    |> DateTime.add(@code_validity_minutes * 60, :second)
    |> DateTime.truncate(:second)
  end

  @doc """
  Returns code validity in minutes.
  """
  def validity_minutes, do: @code_validity_minutes
end

