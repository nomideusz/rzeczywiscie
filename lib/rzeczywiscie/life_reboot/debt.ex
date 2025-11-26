defmodule Rzeczywiscie.LifeReboot.Debt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "debts" do
    field :name, :string
    field :creditor, :string
    field :original_amount, :decimal
    field :current_amount, :decimal
    field :minimum_payment, :decimal
    field :interest_rate, :decimal
    field :due_day, :integer
    field :currency, :string, default: "PLN"
    field :color, :string, default: "#EF4444"
    field :emoji, :string, default: "💳"
    field :priority, :integer, default: 0
    field :paid_off, :boolean, default: false
    field :paid_off_at, :utc_datetime
    field :notes, :string

    has_many :payments, Rzeczywiscie.LifeReboot.DebtPayment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(debt, attrs) do
    debt
    |> cast(attrs, [
      :name, :creditor, :original_amount, :current_amount, :minimum_payment,
      :interest_rate, :due_day, :currency, :color, :emoji, :priority,
      :paid_off, :paid_off_at, :notes
    ])
    |> validate_required([:name, :original_amount, :current_amount])
    |> validate_number(:original_amount, greater_than: 0)
    |> validate_number(:current_amount, greater_than_or_equal_to: 0)
    |> validate_number(:due_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
  end

  @doc """
  Calculate progress percentage (how much paid off)
  """
  def progress_percent(%__MODULE__{} = debt) do
    if Decimal.compare(debt.original_amount, Decimal.new(0)) == :gt do
      paid = Decimal.sub(debt.original_amount, debt.current_amount)
      Decimal.div(paid, debt.original_amount)
      |> Decimal.mult(100)
      |> Decimal.round(1)
      |> Decimal.to_float()
    else
      0.0
    end
  end

  @doc """
  Calculate remaining percentage
  """
  def remaining_percent(%__MODULE__{} = debt) do
    100.0 - progress_percent(debt)
  end

  @doc """
  Check if debt is close to being paid off (< 10% remaining)
  """
  def almost_done?(%__MODULE__{} = debt) do
    remaining_percent(debt) < 10.0
  end
end

