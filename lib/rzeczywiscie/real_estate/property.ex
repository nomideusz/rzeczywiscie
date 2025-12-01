defmodule Rzeczywiscie.RealEstate.Property do
  use Ecto.Schema
  import Ecto.Changeset

  schema "properties" do
    field :source, :string
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :price, :decimal
    field :currency, :string
    field :area_sqm, :decimal
    field :rooms, :integer
    field :floor, :integer

    # Property classification
    field :transaction_type, :string  # "sprzedaż", "wynajem"
    field :property_type, :string     # "mieszkanie", "dom", "pokój", "garaż", etc.

    # Location
    field :city, :string
    field :district, :string
    field :street, :string
    field :postal_code, :string
    field :voivodeship, :string

    # Coordinates
    field :latitude, :decimal
    field :longitude, :decimal

    # URLs and metadata
    field :url, :string
    field :image_url, :string
    field :raw_data, :map

    # Status
    field :active, :boolean, default: true
    field :last_seen_at, :utc_datetime
    
    # LLM analysis results (basic)
    field :llm_urgency, :integer, default: 0
    field :llm_condition, :string
    field :llm_motivation, :string
    field :llm_red_flags, {:array, :string}, default: []
    field :llm_positive_signals, {:array, :string}, default: []
    field :llm_score, :integer, default: 0
    field :llm_analyzed_at, :utc_datetime
    
    # LLM analysis results (enhanced)
    field :llm_investment_score, :integer  # 0-10, AI's overall investment rating
    field :llm_summary, :string  # AI-generated 1-2 sentence summary
    field :llm_hidden_costs, {:array, :string}, default: []
    field :llm_negotiation_hints, {:array, :string}, default: []
    field :llm_monthly_fee, :integer  # Czynsz in PLN
    field :llm_year_built, :integer
    field :llm_floor_info, :string  # e.g. "3/5" (floor/total floors)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(property, attrs) do
    property
    |> cast(attrs, [
      :source,
      :external_id,
      :title,
      :description,
      :price,
      :currency,
      :area_sqm,
      :rooms,
      :floor,
      :transaction_type,
      :property_type,
      :city,
      :district,
      :street,
      :postal_code,
      :voivodeship,
      :latitude,
      :longitude,
      :url,
      :image_url,
      :raw_data,
      :active,
      :last_seen_at,
      :llm_urgency,
      :llm_condition,
      :llm_motivation,
      :llm_red_flags,
      :llm_positive_signals,
      :llm_score,
      :llm_analyzed_at,
      # Enhanced LLM fields
      :llm_investment_score,
      :llm_summary,
      :llm_hidden_costs,
      :llm_negotiation_hints,
      :llm_monthly_fee,
      :llm_year_built,
      :llm_floor_info
    ])
    |> validate_required([:source, :external_id, :title, :url])
    |> validate_inclusion(:source, ["olx", "otodom", "gratka"])
    |> validate_inclusion(:transaction_type, ["sprzedaż", "wynajem", nil])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:area_sqm, greater_than: 0)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> unique_constraint([:source, :external_id])
    |> unique_constraint(:url, name: :properties_url_index)
  end
  
  @doc """
  Changeset for updating LLM analysis results only.
  """
  def llm_changeset(property, attrs) do
    property
    |> cast(attrs, [
      :llm_urgency,
      :llm_condition,
      :llm_motivation,
      :llm_red_flags,
      :llm_positive_signals,
      :llm_score,
      :llm_analyzed_at,
      # Enhanced fields
      :llm_investment_score,
      :llm_summary,
      :llm_hidden_costs,
      :llm_negotiation_hints,
      :llm_monthly_fee,
      :llm_year_built,
      :llm_floor_info
    ])
    |> validate_number(:llm_urgency, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:llm_investment_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_inclusion(:llm_condition, ["unknown", "needs_renovation", "to_finish", "good", "renovated", "new", nil])
    |> validate_inclusion(:llm_motivation, ["unknown", "standard", "motivated", "very_motivated", nil])
  end
end
