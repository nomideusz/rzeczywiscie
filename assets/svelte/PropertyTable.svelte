<script>
  export let properties = []
  export let pagination = { page: 1, page_size: 50, total_count: 0, total_pages: 1 }
  export let live

  let sortColumn = 'inserted_at'
  let sortDirection = 'desc'
  let filterCity = ''
  let filterMinPrice = ''
  let filterMaxPrice = ''
  let filterMinArea = ''
  let filterMaxArea = ''
  let filterSource = ''
  let filterTransactionType = ''
  let filterPropertyType = ''

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
    // Convert to number and round to 2 decimal places
    const numArea = typeof area === 'number' ? area : parseFloat(area)
    if (isNaN(numArea)) return 'N/A'
    return `${numArea.toFixed(2)} m²`
  }

  // Calculate price per square meter
  function formatPricePerSqm(price, area) {
    if (!price || !area) return 'N/A'
    const numPrice = typeof price === 'number' ? price : parseFloat(price)
    const numArea = typeof area === 'number' ? area : parseFloat(area)
    if (isNaN(numPrice) || isNaN(numArea) || numArea === 0) return 'N/A'

    const pricePerSqm = numPrice / numArea
    return new Intl.NumberFormat('pl-PL', {
      style: 'currency',
      currency: 'PLN',
      maximumFractionDigits: 0
    }).format(pricePerSqm)
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

  // Get AQI badge color
  function getAqiBadgeColor(category) {
    if (!category) return 'badge-ghost'
    const cat = category.toLowerCase()
    if (cat === 'good') return 'badge-success'
    if (cat === 'moderate') return 'badge-warning'
    if (cat.includes('unhealthy')) return 'badge-error'
    if (cat === 'hazardous') return 'badge-error'
    return 'badge-ghost'
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
    if (filterTransactionType) filters.transaction_type = filterTransactionType
    if (filterPropertyType) filters.property_type = filterPropertyType

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
    filterTransactionType = ''
    filterPropertyType = ''
    applyFilters()
  }

  // Pagination handlers
  function goToPage(page) {
    if (page >= 1 && page <= pagination.total_pages) {
      live.pushEvent('page_changed', { page })
    }
  }

  function nextPage() {
    goToPage(pagination.page + 1)
  }

  function prevPage() {
    goToPage(pagination.page - 1)
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

<div>
  <!-- Action Buttons -->
  <div class="flex justify-end gap-2 mb-4">
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

  <!-- Filters -->
    <div class="card bg-base-200 shadow-xl mb-4">
      <div class="card-body">
        <h2 class="card-title">Filters</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
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

          <div class="form-control">
            <label class="label" for="filter-transaction-type">
              <span class="label-text">Transaction Type</span>
            </label>
            <select
              id="filter-transaction-type"
              class="select select-bordered select-sm"
              bind:value={filterTransactionType}
            >
              <option value="">All</option>
              <option value="sprzedaż">Sprzedaż</option>
              <option value="wynajem">Wynajem</option>
            </select>
          </div>

          <div class="form-control">
            <label class="label" for="filter-property-type">
              <span class="label-text">Property Type</span>
            </label>
            <select
              id="filter-property-type"
              class="select select-bordered select-sm"
              bind:value={filterPropertyType}
            >
              <option value="">All</option>
              <option value="mieszkanie">Mieszkanie</option>
              <option value="dom">Dom</option>
              <option value="pokój">Pokój</option>
              <option value="garaż">Garaż</option>
              <option value="działka">Działka</option>
              <option value="lokal użytkowy">Lokal użytkowy</option>
              <option value="stancja">Stancja</option>
            </select>
          </div>
        </div>

        <div class="card-actions justify-end mt-4">
          <button onclick={resetFilters} class="btn btn-ghost btn-sm">Reset</button>
          <button onclick={applyFilters} class="btn btn-primary btn-sm">Apply Filters</button>
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
          <th>Type</th>
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
          <th>Price/m²</th>
          <th>
            <button onclick={() => handleSort('aqi')} class="btn btn-ghost btn-xs">
              Air Quality {sortColumn === 'aqi' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
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
            <td>
              <div class="text-xs">
                {#if property.transaction_type}
                  <span class="badge badge-xs {property.transaction_type === 'sprzedaż' ? 'badge-info' : 'badge-warning'}">
                    {property.transaction_type}
                  </span>
                {/if}
                {#if property.property_type}
                  <div class="opacity-70 mt-1">{property.property_type}</div>
                {/if}
              </div>
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
            <td class="text-sm opacity-80">{formatPricePerSqm(property.price, property.area_sqm)}</td>
            <td>
              {#if property.aqi}
                <div class="tooltip" data-tip="{property.aqi_category || 'N/A'} - {property.dominant_pollutant || ''}">
                  <span class="badge badge-sm {getAqiBadgeColor(property.aqi_category)}">
                    {property.aqi}
                  </span>
                </div>
              {:else if property.latitude && property.longitude}
                <span class="badge badge-sm badge-ghost">Pending</span>
              {:else}
                <span class="text-xs opacity-50">No coords</span>
              {/if}
            </td>
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
            <td colspan="11" class="text-center py-8">
              <p class="text-lg">No properties found</p>
              <p class="text-sm opacity-70">Try adjusting your filters or trigger a manual scrape</p>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>

  <!-- Pagination Controls -->
  {#if pagination.total_pages > 1}
    <div class="flex justify-between items-center mt-4">
      <div class="text-sm">
        Showing {((pagination.page - 1) * pagination.page_size) + 1} to {Math.min(pagination.page * pagination.page_size, pagination.total_count)} of {pagination.total_count} results
      </div>

      <div class="btn-group">
        <button
          class="btn btn-sm"
          onclick={prevPage}
          disabled={pagination.page === 1}
        >
          «
        </button>

        {#if pagination.page > 2}
          <button class="btn btn-sm" onclick={() => goToPage(1)}>1</button>
        {/if}

        {#if pagination.page > 3}
          <button class="btn btn-sm btn-disabled">...</button>
        {/if}

        {#if pagination.page > 1}
          <button class="btn btn-sm" onclick={() => goToPage(pagination.page - 1)}>
            {pagination.page - 1}
          </button>
        {/if}

        <button class="btn btn-sm btn-active">
          {pagination.page}
        </button>

        {#if pagination.page < pagination.total_pages}
          <button class="btn btn-sm" onclick={() => goToPage(pagination.page + 1)}>
            {pagination.page + 1}
          </button>
        {/if}

        {#if pagination.page < pagination.total_pages - 2}
          <button class="btn btn-sm btn-disabled">...</button>
        {/if}

        {#if pagination.page < pagination.total_pages - 1}
          <button class="btn btn-sm" onclick={() => goToPage(pagination.total_pages)}>
            {pagination.total_pages}
          </button>
        {/if}

        <button
          class="btn btn-sm"
          onclick={nextPage}
          disabled={pagination.page === pagination.total_pages}
        >
          »
        </button>
      </div>
    </div>
  {/if}
</div>
