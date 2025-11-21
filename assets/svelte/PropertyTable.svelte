<script>
  export let properties = []
  export let live

  let sortColumn = 'inserted_at'
  let sortDirection = 'desc'
  let filterCity = ''
  let filterMinPrice = ''
  let filterMaxPrice = ''
  let filterMinArea = ''
  let filterMaxArea = ''
  let filterSource = ''

  // Format price
  function formatPrice(price) {
    if (!price) return 'N/A'
    return new Intl.NumberFormat('pl-PL', {
      style: 'currency',
      currency: 'PLN',
      maximumFractionDigits: 0
    }).format(price)
  }

  // Format area
  function formatArea(area) {
    if (!area) return 'N/A'
    return `${area} m²`
  }

  // Format date
  function formatDate(dateString) {
    if (!dateString) return 'N/A'
    const date = new Date(dateString)
    return new Intl.DateTimeFormat('pl-PL', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    }).format(date)
  }

  // Handle sort
  function handleSort(column) {
    if (sortColumn === column) {
      sortDirection = sortDirection === 'asc' ? 'desc' : 'asc'
    } else {
      sortColumn = column
      sortDirection = 'desc'
    }

    live.pushEvent('sort_changed', {
      column: sortColumn,
      direction: sortDirection
    })
  }

  // Handle filter apply
  function applyFilters() {
    const filters = {}

    if (filterCity) filters.city = filterCity
    if (filterMinPrice) filters.min_price = parseFloat(filterMinPrice)
    if (filterMaxPrice) filters.max_price = parseFloat(filterMaxPrice)
    if (filterMinArea) filters.min_area = parseFloat(filterMinArea)
    if (filterMaxArea) filters.max_area = parseFloat(filterMaxArea)
    if (filterSource) filters.source = filterSource

    live.pushEvent('filters_changed', filters)
  }

  // Reset filters
  function resetFilters() {
    filterCity = ''
    filterMinPrice = ''
    filterMaxPrice = ''
    filterMinArea = ''
    filterMaxArea = ''
    filterSource = ''
    applyFilters()
  }

  // Manual refresh
  function refreshData() {
    live.pushEvent('refresh_data', {})
  }

  // Trigger manual scrape
  function triggerScrape() {
    if (confirm('Start manual scrape? This will fetch new listings from OLX.')) {
      live.pushEvent('trigger_scrape', {})
    }
  }
</script>

<div class="container mx-auto p-4">
  <div class="mb-6">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-3xl font-bold">Real Estate Listings - Małopolskie</h1>
      <div class="flex gap-2">
        <button
          onclick={refreshData}
          class="btn btn-primary btn-sm"
        >
          Refresh
        </button>
        <button
          onclick={triggerScrape}
          class="btn btn-secondary btn-sm"
        >
          Manual Scrape
        </button>
      </div>
    </div>

    <!-- Filters -->
    <div class="card bg-base-200 shadow-xl mb-4">
      <div class="card-body">
        <h2 class="card-title">Filters</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-4">
          <div class="form-control">
            <label class="label" for="filter-city">
              <span class="label-text">City</span>
            </label>
            <input
              id="filter-city"
              type="text"
              placeholder="Kraków"
              class="input input-bordered input-sm"
              bind:value={filterCity}
            />
          </div>

          <div class="form-control">
            <label class="label" for="filter-min-price">
              <span class="label-text">Min Price</span>
            </label>
            <input
              id="filter-min-price"
              type="number"
              placeholder="100000"
              class="input input-bordered input-sm"
              bind:value={filterMinPrice}
            />
          </div>

          <div class="form-control">
            <label class="label" for="filter-max-price">
              <span class="label-text">Max Price</span>
            </label>
            <input
              id="filter-max-price"
              type="number"
              placeholder="500000"
              class="input input-bordered input-sm"
              bind:value={filterMaxPrice}
            />
          </div>

          <div class="form-control">
            <label class="label" for="filter-min-area">
              <span class="label-text">Min Area (m²)</span>
            </label>
            <input
              id="filter-min-area"
              type="number"
              placeholder="30"
              class="input input-bordered input-sm"
              bind:value={filterMinArea}
            />
          </div>

          <div class="form-control">
            <label class="label" for="filter-max-area">
              <span class="label-text">Max Area (m²)</span>
            </label>
            <input
              id="filter-max-area"
              type="number"
              placeholder="100"
              class="input input-bordered input-sm"
              bind:value={filterMaxArea}
            />
          </div>

          <div class="form-control">
            <label class="label" for="filter-source">
              <span class="label-text">Source</span>
            </label>
            <select
              id="filter-source"
              class="select select-bordered select-sm"
              bind:value={filterSource}
            >
              <option value="">All</option>
              <option value="olx">OLX</option>
              <option value="otodom">Otodom</option>
              <option value="gratka">Gratka</option>
            </select>
          </div>
        </div>

        <div class="card-actions justify-end mt-4">
          <button onclick={resetFilters} class="btn btn-ghost btn-sm">Reset</button>
          <button onclick={applyFilters} class="btn btn-primary btn-sm">Apply Filters</button>
        </div>
      </div>
    </div>

    <!-- Stats -->
    <div class="stats shadow mb-4 w-full">
      <div class="stat">
        <div class="stat-title">Total Listings</div>
        <div class="stat-value text-primary">{properties.length}</div>
      </div>
    </div>
  </div>

  <!-- Table -->
  <div class="overflow-x-auto">
    <table class="table table-zebra table-sm w-full">
      <thead>
        <tr>
          <th>
            <button onclick={() => handleSort('source')} class="btn btn-ghost btn-xs">
              Source {sortColumn === 'source' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>
            <button onclick={() => handleSort('title')} class="btn btn-ghost btn-xs">
              Title {sortColumn === 'title' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>
            <button onclick={() => handleSort('city')} class="btn btn-ghost btn-xs">
              Location {sortColumn === 'city' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>
            <button onclick={() => handleSort('price')} class="btn btn-ghost btn-xs">
              Price {sortColumn === 'price' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>
            <button onclick={() => handleSort('area_sqm')} class="btn btn-ghost btn-xs">
              Area {sortColumn === 'area_sqm' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>Rooms</th>
          <th>
            <button onclick={() => handleSort('inserted_at')} class="btn btn-ghost btn-xs">
              Added {sortColumn === 'inserted_at' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
            </button>
          </th>
          <th>Link</th>
        </tr>
      </thead>
      <tbody>
        {#each properties as property (property.id)}
          <tr class="hover">
            <td>
              <span class="badge badge-sm {property.source === 'olx' ? 'badge-primary' : 'badge-secondary'}">
                {property.source.toUpperCase()}
              </span>
            </td>
            <td class="max-w-xs truncate" title={property.title}>
              {property.title}
            </td>
            <td>
              {property.city || 'N/A'}
              {#if property.district}
                <br/><span class="text-xs opacity-70">{property.district}</span>
              {/if}
            </td>
            <td class="font-semibold">{formatPrice(property.price)}</td>
            <td>{formatArea(property.area_sqm)}</td>
            <td>{property.rooms || 'N/A'}</td>
            <td class="text-xs">{formatDate(property.inserted_at)}</td>
            <td>
              <a
                href={property.url}
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-ghost btn-xs"
              >
                View
              </a>
            </td>
          </tr>
        {:else}
          <tr>
            <td colspan="8" class="text-center py-8">
              <p class="text-lg">No properties found</p>
              <p class="text-sm opacity-70">Try adjusting your filters or trigger a manual scrape</p>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
</div>
