# Property Duplicate Prevention

This document explains how the system prevents duplicate property listings in the database.

## Multi-Layer Duplicate Prevention

The system uses **three layers** of duplicate prevention:

### 1. Database-Level Constraints

Two unique indexes enforce uniqueness at the database level:

```elixir
# Prevents same external_id from same source (e.g., two OLX listings with ID "12345")
create unique_index(:properties, [:source, :external_id])

# Prevents same URL from being added multiple times (even from different sources)
create unique_index(:properties, [:url])
```

**Benefits:**
- Guaranteed by PostgreSQL - cannot be bypassed
- Prevents duplicates even if application logic fails
- Fast lookups using indexes

### 2. Schema-Level Validation

The `Property` changeset includes unique constraints:

```elixir
def changeset(property, attrs) do
  property
  # ... other validations ...
  |> unique_constraint([:source, :external_id])
  |> unique_constraint(:url, name: :properties_url_index)
end
```

**Benefits:**
- Returns friendly error messages when duplicates are detected
- Works with Ecto's `insert` and `update` operations
- Allows graceful error handling in the application

### 3. Application-Level Upsert Logic

The `upsert_property/1` function checks for existing properties before creating new ones:

```elixir
def upsert_property(attrs) do
  # Check for existing property by source+external_id OR by URL
  existing =
    get_property_by_external_id(attrs.source, attrs.external_id) ||
    get_property_by_url(attrs.url)

  case existing do
    nil ->
      create_property(attrs)
    property ->
      update_property(property, attrs)
  end
end
```

**Benefits:**
- Updates existing properties instead of creating duplicates
- Handles cross-source duplicates (same property on OLX and Otodom)
- Maintains `last_seen_at` timestamp for active listings
- No errors thrown - gracefully updates existing properties

## How Duplicates Are Handled

### Scenario 1: Same Property from Same Source

If a scraper tries to add a property that already exists from the same source:

1. `get_property_by_external_id` finds the existing property
2. Property is **updated** with new data
3. `last_seen_at` timestamp is refreshed
4. No duplicate is created ✓

### Scenario 2: Same Property from Different Sources

If a property appears on both OLX and Otodom with the same URL:

1. First source creates the property
2. Second source's URL check finds existing property
3. Property is **updated** (not duplicated)
4. The property keeps the original source but updates data ✓

### Scenario 3: Migration from Existing Duplicates

If duplicates already exist in the database (before URL constraint):

1. Run `Rzeczywiscie.RealEstate.find_duplicate_properties()` to list them
2. Run `Rzeczywiscie.RealEstate.remove_duplicate_properties()` to clean up
3. Migration will add URL unique constraint

**Example:**

```elixir
# In IEx console
iex> Rzeczywiscie.RealEstate.find_duplicate_properties()
[
  %{url: "https://...", property_ids: [123, 456, 789], count: 3},
  %{url: "https://...", property_ids: [111, 222], count: 2}
]

iex> Rzeczywiscie.RealEstate.remove_duplicate_properties()
{:ok, 3}  # Removed 3 duplicates, keeping oldest entries
```

## Running the Migration

To apply the URL unique constraint:

```bash
mix ecto.migrate
```

**Important:** If you have existing duplicates, the migration will fail. You must:

1. First run `remove_duplicate_properties()` to clean up
2. Then run the migration

Or, if you want to keep duplicates temporarily:

1. Comment out the unique_index line in the migration
2. Run the migration
3. Clean up duplicates manually
4. Create a new migration to add the constraint

## Scraper Integration

Both OLX and Otodom scrapers use `upsert_property`:

```elixir
# In scrapers
RealEstate.upsert_property(%{
  source: "olx",
  external_id: "12345",
  url: "https://www.olx.pl/...",
  title: "Mieszkanie...",
  # ... other fields
})
```

No changes needed to scrapers - they automatically benefit from duplicate prevention.

## Benefits

✓ **No manual duplicate checking needed** - handled automatically  
✓ **Cross-source deduplication** - same property from multiple sources is one record  
✓ **Data freshness** - updates keep property data current  
✓ **Database integrity** - constraints prevent corruption  
✓ **Active listing tracking** - `last_seen_at` shows when property was last scraped  

## Monitoring

To check for duplicates:

```elixir
# Count total duplicates
Rzeczywiscie.RealEstate.find_duplicate_properties() |> length()

# See duplicate details
Rzeczywiscie.RealEstate.find_duplicate_properties()
|> Enum.each(fn dup ->
  IO.puts("URL: #{dup.url}")
  IO.puts("Count: #{dup.count}")
  IO.puts("IDs: #{inspect(dup.property_ids)}")
  IO.puts("---")
end)
```

## Performance

- **Unique indexes** are used for fast lookups
- **Upsert operation** is O(1) lookup + O(1) update
- **No full table scans** needed
- **Minimal performance impact** on scrapers

## Admin Panel Integration

The admin panel (`/admin`) includes a one-click deduplication tool:

1. **Duplicate Counter** - Shows current duplicate count in stats bar
2. **Remove Duplicates Button** - One-click removal of all duplicates
3. **Real-time Feedback** - Shows how many duplicates were removed
4. **Safe Operation** - Always keeps the oldest (first inserted) property

### Using the Admin Panel

1. Navigate to `/admin`
2. Check the "Duplicates" stat in the top bar
3. If duplicates exist, click "Remove Duplicates" button
4. Wait for the task to complete
5. Stats will refresh automatically

### Type Backfilling

The admin panel also includes a "Backfill Types" button that:

- Infers missing transaction types (sale/rent) from URLs, titles, and descriptions
- Infers missing property types (apartment, house, room, etc.)
- Uses comprehensive pattern matching including:
  - URL paths and slugs
  - Title keywords
  - Description content
  - Common abbreviations
- Only updates properties that are missing type information
- Shows count of updated properties

## Future Enhancements

Potential improvements:

1. **Fuzzy matching** - detect similar properties with slightly different URLs
2. **Title similarity** - match by normalized title + price + location
3. **Automatic merging** - combine data from multiple sources
4. **Source priority** - prefer data from certain sources when updating
5. **Scheduled deduplication** - automatic daily cleanup

