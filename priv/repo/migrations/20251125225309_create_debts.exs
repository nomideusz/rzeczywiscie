defmodule Rzeczywiscie.Repo.Migrations.CreateDebts do
  use Ecto.Migration

  def change do
    create table(:debts) do
      add :name, :string, null: false           # "Credit Card", "Personal Loan", etc.
      add :creditor, :string                    # Who you owe
      add :original_amount, :decimal, precision: 12, scale: 2, null: false
      add :current_amount, :decimal, precision: 12, scale: 2, null: false
      add :minimum_payment, :decimal, precision: 10, scale: 2
      add :interest_rate, :decimal, precision: 5, scale: 2  # APR %
      add :due_day, :integer                    # Day of month payment is due
      add :currency, :string, default: "PLN"
      add :color, :string, default: "#EF4444"  # For visualization
      add :emoji, :string, default: "💳"
      add :priority, :integer, default: 0      # For debt snowball ordering
      add :paid_off, :boolean, default: false
      add :paid_off_at, :utc_datetime
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:debts, [:paid_off])
    create index(:debts, [:priority])

    # Track individual payments
    create table(:debt_payments) do
      add :debt_id, references(:debts, on_delete: :delete_all), null: false
      add :amount, :decimal, precision: 10, scale: 2, null: false
      add :paid_at, :utc_datetime, null: false
      add :payment_type, :string, default: "regular"  # regular, extra, windfall
      add :source, :string                     # Where did the money come from?
      add :notes, :text
      add :celebration_shown, :boolean, default: false  # Did we celebrate this?

      timestamps(type: :utc_datetime)
    end

    create index(:debt_payments, [:debt_id])
    create index(:debt_payments, [:paid_at])
  end
end
