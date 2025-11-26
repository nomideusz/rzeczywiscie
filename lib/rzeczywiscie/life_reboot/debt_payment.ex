defmodule Rzeczywiscie.LifeReboot.DebtPayment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "debt_payments" do
    field :amount, :decimal
    field :paid_at, :utc_datetime
    field :payment_type, :string, default: "regular"
    field :source, :string
    field :notes, :string
    field :celebration_shown, :boolean, default: false

    belongs_to :debt, Rzeczywiscie.LifeReboot.Debt

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:debt_id, :amount, :paid_at, :payment_type, :source, :notes, :celebration_shown])
    |> validate_required([:debt_id, :amount, :paid_at])
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:payment_type, ["regular", "extra", "windfall"])
    |> foreign_key_constraint(:debt_id)
  end

  @doc """
  Returns celebration message based on payment type and amount
  """
  def celebration_message(%__MODULE__{} = payment) do
    amount = Decimal.to_float(payment.amount)

    cond do
      payment.payment_type == "windfall" ->
        "🎉 WINDFALL! You put #{format_currency(amount)} toward your debt! Amazing!"
      payment.payment_type == "extra" ->
        "⭐ Extra payment of #{format_currency(amount)}! You're crushing it!"
      amount >= 500 ->
        "💪 Big payment! #{format_currency(amount)} gone from your debt!"
      amount >= 100 ->
        "✨ Nice! #{format_currency(amount)} paid!"
      true ->
        "👍 Every payment counts! #{format_currency(amount)} closer to freedom!"
    end
  end

  defp format_currency(amount) do
    "#{:erlang.float_to_binary(amount, decimals: 2)} zł"
  end
end

