<script>
  export let properties = []
  export let pagination = { page: 1, page_size: 50, total_count: 0, total_pages: 1 }
  export let live
  export let user_id = null

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

  // UI state for collapsible filters
  let filtersExpanded = false

  // Computed: Check if any filters are active
  $: hasActiveFilters = !!(
    filterCity || filterMinPrice || filterMaxPrice ||
    filterMinArea || filterMaxArea || filterSource ||
    filterTransactionType || filterPropertyType
  )

  // Computed: Count active filters
  $: activeFilterCount = [
    filterCity, filterMinPrice, filterMaxPrice, filterMinArea,
    filterMaxArea, filterSource, filterTransactionType, filterPropertyType
  ].filter(Boolean).length

  // Listen for favorite updates from server (instant UI update)
  if (live && live.handleEvent) {
    live.handleEvent('favorite-updated', ({ property_id, is_favorited }) => {
      // Update the property in the local properties array
      properties = properties.map(p =>
        p.id === property_id ? { ...p, is_favorited } : p
      )
    })
  }

  // Debounce timer for filters (prevents query spam)
  let debounceTimer

  // Reactive statement: auto-apply filters with 500ms debounce when any filter changes
  $: {
    if (live && live.pushEvent) {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        applyFilters()
      }, 500)
    }
    // Dependencies that trigger this reactive statement:
    filterCity, filterMinPrice, filterMaxPrice, filterMinArea, filterMaxArea,
    filterSource, filterTransactionType, filterPropertyType
  }

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

  // Toggle favorite
  function toggleFavorite(propertyId) {
    live.pushEvent('toggle_favorite', { property_id: propertyId })
  }
</script>

<div>
  <!-- Modern Collapsible Filters -->
  <div class="card bg-base-200 shadow-lg mb-4 border-2 {hasActiveFilters ? 'border-primary' : 'border-transparent'}">
    <div class="card-body p-4">
      <!-- Filter Header -->
      <div class="flex items-center justify-between">
        <button
          onclick={() => filtersExpanded = !filtersExpanded}
          class="flex items-center gap-2 hover:text-primary transition-colors flex-1"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
          </svg>
          <h2 class="text-lg font-bold">
            Filters
            {#if activeFilterCount > 0}
              <span class="badge badge-primary badge-sm ml-2">{activeFilterCount}</span>
            {/if}
          </h2>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4 transition-transform {filtersExpanded ? 'rotate-180' : ''}"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>

        {#if hasActiveFilters}
          <button
            onclick={resetFilters}
            class="btn btn-ghost btn-sm gap-2"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
            Clear all
          </button>
        {/if}
      </div>

      <!-- Active Filters Badges (Always Visible) -->
      {#if hasActiveFilters && !filtersExpanded}
        <div class="flex flex-wrap gap-2 mt-3">
          {#if filterCity}
            <div class="badge badge-primary gap-2">
              City: {filterCity}
              <button onclick={() => filterCity = ''} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
          {#if filterMinPrice || filterMaxPrice}
            <div class="badge badge-primary gap-2">
              Price: {filterMinPrice || '0'} - {filterMaxPrice || '∞'}
              <button onclick={() => { filterMinPrice = ''; filterMaxPrice = ''; }} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
          {#if filterMinArea || filterMaxArea}
            <div class="badge badge-primary gap-2">
              Area: {filterMinArea || '0'} - {filterMaxArea || '∞'} m²
              <button onclick={() => { filterMinArea = ''; filterMaxArea = ''; }} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
          {#if filterSource}
            <div class="badge badge-primary gap-2">
              Source: {filterSource.toUpperCase()}
              <button onclick={() => filterSource = ''} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
          {#if filterTransactionType}
            <div class="badge badge-primary gap-2">
              {filterTransactionType}
              <button onclick={() => filterTransactionType = ''} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
          {#if filterPropertyType}
            <div class="badge badge-primary gap-2">
              {filterPropertyType}
              <button onclick={() => filterPropertyType = ''} class="hover:text-error">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          {/if}
        </div>
      {/if}

      <!-- Expandable Filter Inputs -->
      {#if filtersExpanded}
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3 mt-4 animate-fadeIn">
          <!-- City -->
          <div class="form-control">
            <label class="label py-1" for="filter-city">
              <span class="label-text text-xs font-semibold">🏙️ City</span>
            </label>
            <input
              id="filter-city"
              type="text"
              placeholder="e.g. Kraków"
              class="input input-bordered input-sm"
              bind:value={filterCity}
            />
          </div>

          <!-- Min Price -->
          <div class="form-control">
            <label class="label py-1" for="filter-min-price">
              <span class="label-text text-xs font-semibold">💰 Min Price (PLN)</span>
            </label>
            <input
              id="filter-min-price"
              type="number"
              placeholder="100,000"
              class="input input-bordered input-sm"
              bind:value={filterMinPrice}
            />
          </div>

          <!-- Max Price -->
          <div class="form-control">
            <label class="label py-1" for="filter-max-price">
              <span class="label-text text-xs font-semibold">💰 Max Price (PLN)</span>
            </label>
            <input
              id="filter-max-price"
              type="number"
              placeholder="500,000"
              class="input input-bordered input-sm"
              bind:value={filterMaxPrice}
            />
          </div>

          <!-- Min Area -->
          <div class="form-control">
            <label class="label py-1" for="filter-min-area">
              <span class="label-text text-xs font-semibold">📐 Min Area (m²)</span>
            </label>
            <input
              id="filter-min-area"
              type="number"
              placeholder="30"
              class="input input-bordered input-sm"
              bind:value={filterMinArea}
            />
          </div>

          <!-- Max Area -->
          <div class="form-control">
            <label class="label py-1" for="filter-max-area">
              <span class="label-text text-xs font-semibold">📐 Max Area (m²)</span>
            </label>
            <input
              id="filter-max-area"
              type="number"
              placeholder="100"
              class="input input-bordered input-sm"
              bind:value={filterMaxArea}
            />
          </div>

          <!-- Source -->
          <div class="form-control">
            <label class="label py-1" for="filter-source">
              <span class="label-text text-xs font-semibold">🌐 Source</span>
            </label>
            <select
              id="filter-source"
              class="select select-bordered select-sm"
              bind:value={filterSource}
            >
              <option value="">All Sources</option>
              <option value="olx">OLX</option>
              <option value="otodom">Otodom</option>
              <option value="gratka">Gratka</option>
            </select>
          </div>

          <!-- Transaction Type -->
          <div class="form-control">
            <label class="label py-1" for="filter-transaction-type">
              <span class="label-text text-xs font-semibold">🏷️ Transaction</span>
            </label>
            <select
              id="filter-transaction-type"
              class="select select-bordered select-sm"
              bind:value={filterTransactionType}
            >
              <option value="">All Types</option>
              <option value="sprzedaż">Sprzedaż</option>
              <option value="wynajem">Wynajem</option>
            </select>
          </div>

          <!-- Property Type -->
          <div class="form-control">
            <label class="label py-1" for="filter-property-type">
              <span class="label-text text-xs font-semibold">🏠 Property Type</span>
            </label>
            <select
              id="filter-property-type"
              class="select select-bordered select-sm"
              bind:value={filterPropertyType}
            >
              <option value="">All Properties</option>
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

        <!-- Info Text -->
        <div class="alert alert-info mt-3 py-2">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-5 h-5">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <span class="text-xs">Filters apply automatically as you type (500ms delay)</span>
        </div>
      {/if}
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
          <th>Favorite</th>
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
                {:else}
                  <span class="badge badge-xs badge-ghost opacity-50" title="Transaction type unknown">
                    ?
                  </span>
                {/if}
                {#if property.property_type}
                  <div class="opacity-70 mt-1">{property.property_type}</div>
                {:else}
                  <div class="opacity-50 mt-1 text-[10px]" title="Property type unknown">Unknown</div>
                {/if}
              </div>
            </td>
            <td class="max-w-xs">
              <div class="flex items-center gap-2">
                {#if property.image_url}
                  <div class="dropdown dropdown-hover dropdown-right">
                    <div tabindex="0" role="button" class="cursor-pointer text-primary">
                      📷
                    </div>
                    <div tabindex="0" class="dropdown-content z-[1] card card-compact w-64 p-2 shadow bg-base-100">
                      <div class="card-body">
                        <img
                          src={property.image_url}
                          alt={property.title}
                          class="w-full h-auto rounded-lg"
                          loading="lazy"
                          onerror={(e) => {
                            e.target.onerror = null;
                            e.target.src = 'data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 width=%27200%27 height=%27150%27%3E%3Crect fill=%27%23ddd%27 width=%27200%27 height=%27150%27/%3E%3Ctext x=%2750%25%27 y=%2750%25%27 dominant-baseline=%27middle%27 text-anchor=%27middle%27 fill=%27%23999%27%3ENo Image%3C/text%3E%3C/svg%3E';
                          }}
                        />
                      </div>
                    </div>
                  </div>
                {/if}
                <span class="truncate" title={property.title}>{property.title}</span>
              </div>
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
            <td>
              <button
                onclick={() => toggleFavorite(property.id)}
                class="btn btn-ghost btn-xs"
                title={property.is_favorited ? 'Remove from favorites' : 'Add to favorites'}
              >
                {#if property.is_favorited}
                  <span class="text-red-500">❤️</span>
                {:else}
                  <span class="opacity-50">🤍</span>
                {/if}
              </button>
            </td>
          </tr>
        {:else}
          <tr>
            <td colspan="12" class="text-center py-8">
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
