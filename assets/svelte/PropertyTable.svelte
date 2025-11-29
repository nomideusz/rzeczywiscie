<script>
  import { createEventDispatcher } from 'svelte'

  export let properties = []
  export let pagination = { page: 1, page_size: 50, total_count: 0, total_pages: 1 }
  export let live
  export let user_id = null
  export let viewMode = 'table' // 'table' or 'cards'

  const dispatch = createEventDispatcher()

  let sortColumn = 'inserted_at'
  let sortDirection = 'desc'
  let filterSearch = ''
  let filterCity = ''
  let filterMinPrice = ''
  let filterMaxPrice = ''
  let filterMinArea = ''
  let filterMaxArea = ''
  let filterRooms = ''
  let filterSource = ''
  let filterTransactionType = ''
  let filterPropertyType = ''

  // UI state for collapsible filters
  let filtersExpanded = false

  // Computed: Check if any filters are active
  $: hasActiveFilters = !!(
    filterSearch || filterCity || filterMinPrice || filterMaxPrice ||
    filterMinArea || filterMaxArea || filterRooms || filterSource ||
    filterTransactionType || filterPropertyType
  )

  // Computed: Count active filters
  $: activeFilterCount = [
    filterSearch, filterCity, filterMinPrice, filterMaxPrice, filterMinArea,
    filterMaxArea, filterRooms, filterSource, filterTransactionType, filterPropertyType
  ].filter(Boolean).length

  // Check if listing is new (added in last 24 hours)
  function isNew(dateString) {
    if (!dateString) return false
    const date = new Date(dateString)
    const now = new Date()
    const diff = now - date
    const hours = diff / (1000 * 60 * 60)
    return hours < 24
  }


  // Listen for favorite updates from server (instant UI update)
  if (live && live.handleEvent) {
    live.handleEvent('favorite-updated', ({ property_id, is_favorited }) => {
      properties = properties.map(p =>
        p.id === property_id ? { ...p, is_favorited } : p
      )
    })
  }

  // Debounce timer for filters
  let debounceTimer

  // Reactive: auto-apply filters with debounce
  $: {
    if (live && live.pushEvent) {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        applyFilters()
      }, 500)
    }
    filterSearch, filterCity, filterMinPrice, filterMaxPrice, filterMinArea, filterMaxArea,
    filterRooms, filterSource, filterTransactionType, filterPropertyType
  }

  // Format functions
  function formatPrice(price) {
    if (!price) return '—'
    return new Intl.NumberFormat('pl-PL', {
      style: 'decimal',
      maximumFractionDigits: 0
    }).format(price) + ' zł'
  }

  function formatArea(area) {
    if (!area) return '—'
    const numArea = typeof area === 'number' ? area : parseFloat(area)
    if (isNaN(numArea)) return '—'
    return `${numArea.toFixed(0)} m²`
  }

  function formatPricePerSqm(price, area) {
    if (!price || !area) return '—'
    const numPrice = typeof price === 'number' ? price : parseFloat(price)
    const numArea = typeof area === 'number' ? area : parseFloat(area)
    if (isNaN(numPrice) || isNaN(numArea) || numArea === 0) return '—'
    return new Intl.NumberFormat('pl-PL', {
      style: 'decimal',
      maximumFractionDigits: 0
    }).format(numPrice / numArea) + ' zł/m²'
  }

  function formatDate(dateString) {
    if (!dateString) return '—'
    const date = new Date(dateString)
    const now = new Date()
    const diff = now - date
    const minutes = Math.floor(diff / (1000 * 60))
    const hours = Math.floor(diff / (1000 * 60 * 60))
    const days = Math.floor(diff / (1000 * 60 * 60 * 24))

    if (minutes < 60) return 'now'
    if (hours < 24) return `${hours}h`
    if (days < 7) return `${days}d`
    return date.toLocaleDateString('pl-PL', { day: 'numeric', month: 'short' })
  }

  function getAqiColor(category) {
    if (!category) return ''
    const cat = category.toLowerCase()
    if (cat === 'good') return 'text-success'
    if (cat === 'moderate') return 'text-warning'
    if (cat.includes('unhealthy')) return 'text-error'
    return ''
  }

  function getTransactionBg(type) {
    if (type === 'sprzedaż') return 'bg-info/20 text-info'
    if (type === 'wynajem') return 'bg-warning/20 text-warning'
    return 'bg-base-300 opacity-50'
  }

  // Handlers
  function handleSort(column) {
    if (sortColumn === column) {
      sortDirection = sortDirection === 'asc' ? 'desc' : 'asc'
    } else {
      sortColumn = column
      sortDirection = 'desc'
    }
    live.pushEvent('sort_changed', { column: sortColumn, direction: sortDirection })
  }

  function applyFilters() {
    const filters = {}
    if (filterSearch) filters.search = filterSearch
    if (filterCity) filters.city = filterCity
    if (filterMinPrice) filters.min_price = parseFloat(filterMinPrice)
    if (filterMaxPrice) filters.max_price = parseFloat(filterMaxPrice)
    if (filterMinArea) filters.min_area = parseFloat(filterMinArea)
    if (filterMaxArea) filters.max_area = parseFloat(filterMaxArea)
    if (filterRooms) filters.rooms = parseInt(filterRooms)
    if (filterSource) filters.source = filterSource
    if (filterTransactionType) filters.transaction_type = filterTransactionType
    if (filterPropertyType) filters.property_type = filterPropertyType
    live.pushEvent('filters_changed', filters)
  }

  function resetFilters() {
    filterSearch = ''
    filterCity = ''
    filterMinPrice = ''
    filterMaxPrice = ''
    filterMinArea = ''
    filterMaxArea = ''
    filterRooms = ''
    filterSource = ''
    filterTransactionType = ''
    filterPropertyType = ''
    applyFilters()
  }

  function goToPage(page) {
    if (page >= 1 && page <= pagination.total_pages) {
      live.pushEvent('page_changed', { page })
    }
  }

  function toggleFavorite(propertyId) {
    live.pushEvent('toggle_favorite', { property_id: propertyId })
  }

  function viewOnMap(propertyId) {
    dispatch('viewOnMap', { propertyId })
  }

  // Image preview state
  let previewImage = null
  let previewX = 0
  let previewY = 0
  let failedImages = new Set()

  function showPreview(e, imageUrl) {
    // Don't show preview for failed images
    if (failedImages.has(imageUrl)) return
    previewImage = imageUrl
    updatePreviewPosition(e)
  }

  function updatePreviewPosition(e) {
    // Position preview to the right of cursor, but keep it in viewport
    const padding = 20
    const previewWidth = 320
    const previewHeight = 240

    let x = e.clientX + padding
    let y = e.clientY - previewHeight / 2

    // Keep in viewport
    if (x + previewWidth > window.innerWidth) {
      x = e.clientX - previewWidth - padding
    }
    if (y < padding) {
      y = padding
    }
    if (y + previewHeight > window.innerHeight - padding) {
      y = window.innerHeight - previewHeight - padding
    }

    previewX = x
    previewY = y
  }

  function hidePreview() {
    previewImage = null
  }

  function handleImageError(e, imageUrl) {
    failedImages.add(imageUrl)
    failedImages = failedImages // Trigger reactivity
    e.target.parentElement.style.display = 'none'
  }
</script>

<div>
  <!-- Filters Section - Redesigned -->
  <div class="bg-base-100 border-2 border-base-content mb-6">
    <!-- Row 1: Transaction & Property Type Toggles -->
    <div class="flex flex-wrap items-stretch border-b-2 border-base-content">
      <!-- Transaction Type -->
      <div class="flex items-center border-r-2 border-base-content">
        <span class="px-3 py-2 text-[10px] font-bold uppercase tracking-wide opacity-50 bg-base-200">Transaction</span>
        <button
          onclick={() => { filterTransactionType = ''; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterTransactionType === '' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          All
        </button>
        <button
          onclick={() => { filterTransactionType = 'sprzedaż'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterTransactionType === 'sprzedaż' ? 'bg-info text-info-content' : 'hover:bg-base-200'}"
        >
          Sprzedaż
        </button>
        <button
          onclick={() => { filterTransactionType = 'wynajem'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterTransactionType === 'wynajem' ? 'bg-warning text-warning-content' : 'hover:bg-base-200'}"
        >
          Wynajem
        </button>
      </div>

      <!-- Property Type -->
      <div class="flex items-center flex-1">
        <span class="px-3 py-2 text-[10px] font-bold uppercase tracking-wide opacity-50 bg-base-200">Type</span>
        <button
          onclick={() => { filterPropertyType = ''; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === '' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          All
        </button>
        <button
          onclick={() => { filterPropertyType = 'mieszkanie'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === 'mieszkanie' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          Mieszkanie
        </button>
        <button
          onclick={() => { filterPropertyType = 'dom'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === 'dom' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          Dom
        </button>
        <button
          onclick={() => { filterPropertyType = 'pokój'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === 'pokój' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          Pokój
        </button>
        <button
          onclick={() => { filterPropertyType = 'działka'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === 'działka' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          Działka
        </button>
        <button
          onclick={() => { filterPropertyType = 'lokal użytkowy'; applyFilters() }}
          class="px-3 py-2 text-xs font-bold transition-colors cursor-pointer border-l border-base-content/30 {filterPropertyType === 'lokal użytkowy' ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
        >
          Lokal
        </button>
      </div>

      <!-- Expand/Collapse -->
      <button
        onclick={() => filtersExpanded = !filtersExpanded}
        class="px-4 py-2 text-xs font-bold uppercase tracking-wide hover:bg-base-200 transition-colors cursor-pointer border-l-2 border-base-content flex items-center gap-2"
      >
        More
        <svg
          class="w-3 h-3 transition-transform {filtersExpanded ? 'rotate-180' : ''}"
          fill="none" stroke="currentColor" viewBox="0 0 24 24"
        >
          <path stroke-linecap="square" stroke-width="3" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
    </div>

    <!-- Row 2: Active Filters (always visible when filters applied) -->
    {#if hasActiveFilters}
      <div class="px-3 py-2 flex flex-wrap items-center gap-2 bg-base-200/50 border-b border-base-content/30">
        <span class="text-[10px] font-bold uppercase tracking-wide opacity-50">Active:</span>
        {#if filterSearch}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            "{filterSearch}"
            <button onclick={() => { filterSearch = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterCity}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            {filterCity}
            <button onclick={() => { filterCity = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterMinPrice || filterMaxPrice}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            {filterMinPrice || '0'}–{filterMaxPrice || '∞'} zł
            <button onclick={() => { filterMinPrice = ''; filterMaxPrice = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterMinArea || filterMaxArea}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            {filterMinArea || '0'}–{filterMaxArea || '∞'} m²
            <button onclick={() => { filterMinArea = ''; filterMaxArea = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterRooms}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            {filterRooms} rooms
            <button onclick={() => { filterRooms = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterSource}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-primary text-primary-content">
            {filterSource.toUpperCase()}
            <button onclick={() => { filterSource = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterTransactionType}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-info text-info-content">
            {filterTransactionType}
            <button onclick={() => { filterTransactionType = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        {#if filterPropertyType}
          <span class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] font-bold bg-secondary text-secondary-content">
            {filterPropertyType}
            <button onclick={() => { filterPropertyType = ''; applyFilters() }} class="hover:opacity-70 cursor-pointer">×</button>
          </span>
        {/if}
        <button
          onclick={resetFilters}
          class="ml-auto text-[10px] font-bold uppercase tracking-wide text-error hover:underline cursor-pointer"
        >
          Clear all
        </button>
      </div>
    {/if}

    <!-- Row 3: Expanded Filters -->
    {#if filtersExpanded}
      <div class="p-4">
        <!-- Search -->
        <div class="mb-4">
          <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-search">
            Search in title & description
          </label>
          <input
            id="filter-search"
            type="text"
            placeholder="balkon, garaż, widok..."
            class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
            bind:value={filterSearch}
          />
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
          <!-- City -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-city">
              City
            </label>
            <input
              id="filter-city"
              type="text"
              placeholder="Kraków..."
              class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
              bind:value={filterCity}
            />
          </div>

          <!-- Price Range -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60">
              Price (PLN)
            </label>
            <div class="flex gap-1">
              <input
                type="number"
                placeholder="Min"
                class="w-full px-2 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                bind:value={filterMinPrice}
              />
              <input
                type="number"
                placeholder="Max"
                class="w-full px-2 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                bind:value={filterMaxPrice}
              />
            </div>
          </div>

          <!-- Area Range -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60">
              Area (m²)
            </label>
            <div class="flex gap-1">
              <input
                type="number"
                placeholder="Min"
                class="w-full px-2 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                bind:value={filterMinArea}
              />
              <input
                type="number"
                placeholder="Max"
                class="w-full px-2 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                bind:value={filterMaxArea}
              />
            </div>
          </div>

          <!-- Rooms -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-rooms">
              Rooms
            </label>
            <select
              id="filter-rooms"
              class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
              bind:value={filterRooms}
            >
              <option value="">Any</option>
              <option value="1">1</option>
              <option value="2">2</option>
              <option value="3">3</option>
              <option value="4">4</option>
              <option value="5">5+</option>
            </select>
          </div>

          <!-- Source -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-source">
              Source
            </label>
            <select
              id="filter-source"
              class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
              bind:value={filterSource}
            >
              <option value="">All</option>
              <option value="olx">OLX</option>
              <option value="otodom">Otodom</option>
            </select>
          </div>

          <!-- Transaction Type -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-transaction">
              Transaction
            </label>
            <select
              id="filter-transaction"
              class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
              bind:value={filterTransactionType}
            >
              <option value="">All</option>
              <option value="sprzedaż">Sale</option>
              <option value="wynajem">Rent</option>
            </select>
          </div>

          <!-- Property Type -->
          <div>
            <label class="block text-xs font-bold uppercase tracking-wide mb-1 opacity-60" for="filter-property">
              Property
            </label>
            <select
              id="filter-property"
              class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
              bind:value={filterPropertyType}
            >
              <option value="">All</option>
              <option value="mieszkanie">Apartment</option>
              <option value="dom">House</option>
              <option value="pokój">Room</option>
              <option value="garaż">Garage</option>
              <option value="działka">Plot</option>
              <option value="lokal użytkowy">Commercial</option>
            </select>
          </div>
        </div>

        <div class="mt-3 text-xs opacity-50">
          Filters apply automatically as you type
        </div>
      </div>
    {/if}
  </div>

  <!-- Table View -->
  {#if viewMode === 'table'}
    <div class="bg-base-100 border-2 border-base-content overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-base-200 border-b-2 border-base-content">
            <tr>
              <th class="px-2 py-2 text-left text-[10px] font-bold uppercase tracking-wide w-16">
                <button onclick={() => handleSort('source')} class="hover:text-primary cursor-pointer">
                  Src {sortColumn === 'source' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-left text-[10px] font-bold uppercase tracking-wide w-20">Type</th>
              <th class="px-2 py-2 text-left text-[10px] font-bold uppercase tracking-wide">
                <button onclick={() => handleSort('title')} class="hover:text-primary cursor-pointer">
                  Property {sortColumn === 'title' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-right text-[10px] font-bold uppercase tracking-wide w-28">
                <button onclick={() => handleSort('price')} class="hover:text-primary cursor-pointer">
                  Price {sortColumn === 'price' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-right text-[10px] font-bold uppercase tracking-wide w-16">
                <button onclick={() => handleSort('area_sqm')} class="hover:text-primary cursor-pointer">
                  m² {sortColumn === 'area_sqm' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-right text-[10px] font-bold uppercase tracking-wide w-20">
                <button onclick={() => handleSort('price_per_sqm')} class="hover:text-primary cursor-pointer">
                  zł/m² {sortColumn === 'price_per_sqm' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-center text-[10px] font-bold uppercase tracking-wide w-10">AQI</th>
              <th class="px-2 py-2 text-right text-[10px] font-bold uppercase tracking-wide w-14">
                <button onclick={() => handleSort('inserted_at')} class="hover:text-primary cursor-pointer">
                  Age {sortColumn === 'inserted_at' ? (sortDirection === 'asc' ? '↑' : '↓') : ''}
                </button>
              </th>
              <th class="px-2 py-2 text-center text-[10px] font-bold uppercase tracking-wide w-20"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            {#each properties as property (property.id)}
              <tr class="hover:bg-base-200/50 transition-colors">
                <!-- Source -->
                <td class="px-2 py-1.5">
                  <span class="px-1.5 py-0.5 text-[9px] font-bold uppercase {property.source === 'olx' ? 'bg-primary/20 text-primary' : 'bg-secondary/20 text-secondary'}">
                    {property.source}
                  </span>
                </td>

                <!-- Type -->
                <td class="px-2 py-1.5">
                  <div class="flex flex-col">
                    <span class="text-[10px] font-bold uppercase {property.transaction_type === 'sprzedaż' ? 'text-info' : property.transaction_type === 'wynajem' ? 'text-warning' : 'opacity-40'}">
                      {property.transaction_type || '?'}
                    </span>
                    <span class="text-[10px] opacity-60 truncate max-w-[70px]" title={property.property_type}>
                      {property.property_type || '—'}
                    </span>
                  </div>
                </td>

                <!-- Property (Title + Location combined) -->
                <td class="px-2 py-1.5">
                  <div class="flex items-start gap-2">
                    <!-- Thumbnail -->
                    {#if property.image_url && !failedImages.has(property.image_url)}
                      <div
                        class="w-12 h-9 bg-base-300 overflow-hidden border border-base-content/20 cursor-zoom-in flex-shrink-0"
                        onmouseenter={(e) => showPreview(e, property.image_url)}
                        onmousemove={updatePreviewPosition}
                        onmouseleave={hidePreview}
                      >
                        <img
                          src={property.image_url}
                          alt=""
                          class="w-full h-full object-cover pointer-events-none"
                          loading="lazy"
                          onerror={(e) => handleImageError(e, property.image_url)}
                        />
                      </div>
                    {:else}
                      <div class="w-12 h-9 bg-base-300 flex-shrink-0 flex items-center justify-center text-[10px] opacity-30 border border-base-content/10">
                        —
                      </div>
                    {/if}
                    <!-- Title & Location -->
                    <div class="min-w-0 flex-1">
                      <div class="font-medium leading-tight line-clamp-2 text-[13px]" title={property.title}>
                        {#if isNew(property.inserted_at)}
                          <span class="inline-block px-1 py-0.5 text-[9px] font-black bg-success text-success-content mr-1 align-middle">NEW</span>
                        {/if}
                        {property.title}
                      </div>
                      <div class="text-[11px] opacity-60 mt-0.5">
                        {property.city || '—'}{property.district ? ` · ${property.district}` : ''}{property.rooms ? ` · ${property.rooms}p` : ''}
                      </div>
                    </div>
                  </div>
                </td>

                <!-- Price -->
                <td class="px-2 py-1.5 text-right">
                  <div class="font-bold text-[13px]">{formatPrice(property.price)}</div>
                </td>

                <!-- Area -->
                <td class="px-2 py-1.5 text-right text-[12px]">
                  {formatArea(property.area_sqm)}
                </td>

                <!-- Price per sqm -->
                <td class="px-2 py-1.5 text-right text-[11px] opacity-60">
                  {formatPricePerSqm(property.price, property.area_sqm)}
                </td>

                <!-- AQI -->
                <td class="px-2 py-1.5 text-center">
                  {#if property.aqi}
                    <span class="text-[11px] font-bold {getAqiColor(property.aqi_category)}" title={property.aqi_category}>
                      {property.aqi}
                    </span>
                  {:else}
                    <span class="text-[10px] opacity-20">—</span>
                  {/if}
                </td>

                <!-- Age -->
                <td class="px-2 py-1.5 text-right text-[11px] opacity-50">
                  {formatDate(property.inserted_at)}
                </td>

                <!-- Actions -->
                <td class="px-2 py-1.5">
                  <div class="flex items-center justify-end gap-0.5">
                    <button
                      onclick={() => toggleFavorite(property.id)}
                      class="p-1 hover:bg-base-300 transition-colors cursor-pointer"
                      title={property.is_favorited ? 'Remove from favorites' : 'Add to favorites'}
                    >
                      {property.is_favorited ? '❤️' : '🤍'}
                    </button>
                    {#if property.latitude && property.longitude}
                      <button
                        onclick={() => viewOnMap(property.id)}
                        class="p-1 hover:bg-base-300 transition-colors text-[12px] cursor-pointer"
                        title="View on map"
                      >
                        🗺
                      </button>
                    {/if}
                    <a
                      href={property.url}
                      target="_blank"
                      rel="noopener"
                      class="p-1 hover:bg-base-300 transition-colors text-[11px] font-bold cursor-pointer"
                      title="Open listing"
                    >
                      ↗
                    </a>
                  </div>
                </td>
              </tr>
            {:else}
              <tr>
                <td colspan="9" class="px-3 py-12 text-center">
                  <div class="text-lg font-bold uppercase tracking-wide opacity-40">No properties found</div>
                  <div class="text-sm opacity-40">Try adjusting your filters</div>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>

  <!-- Cards View -->
  {:else}
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {#each properties as property (property.id)}
        <div class="bg-base-100 border-2 border-base-content hover:border-primary transition-colors group">
          <!-- Image -->
          <div class="relative aspect-video overflow-hidden border-b-2 border-base-content {property.image_url ? '' : 'bg-base-300'}">
            {#if property.image_url}
              <img
                src={property.image_url}
                alt=""
                class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                loading="lazy"
              />
            {:else}
              <!-- Placeholder -->
              <div class="absolute inset-0 flex items-center justify-center">
                <span class="text-6xl opacity-20">🏠</span>
              </div>
            {/if}
            <!-- Badges -->
            <div class="absolute top-2 left-2 flex gap-1">
              <span class="px-2 py-0.5 text-[10px] font-bold uppercase bg-base-100 border border-base-content">
                {property.source}
              </span>
              {#if property.transaction_type}
                <span class="px-2 py-0.5 text-[10px] font-bold uppercase {getTransactionBg(property.transaction_type)}">
                  {property.transaction_type}
                </span>
              {/if}
            </div>
            <!-- Favorite -->
            <button
              onclick={() => toggleFavorite(property.id)}
              class="absolute top-2 right-2 text-xl cursor-pointer"
            >
              {property.is_favorited ? '❤️' : '🤍'}
            </button>
          </div>

          <!-- Content -->
          <div class="p-4">
            <!-- Title -->
            <h3 class="font-bold text-lg leading-tight mb-2 line-clamp-2" title={property.title}>
              {property.title}
            </h3>

            <!-- Location -->
            <div class="text-sm opacity-70 mb-3">
              📍 {property.city || '—'}{property.district ? `, ${property.district}` : ''}
            </div>

            <!-- Stats -->
            <div class="flex items-end justify-between mb-4">
              <div>
                <div class="text-2xl font-black text-primary">{formatPrice(property.price)}</div>
                <div class="text-xs opacity-60">{formatPricePerSqm(property.price, property.area_sqm)}</div>
              </div>
              <div class="text-right">
                <div class="text-lg font-bold">{formatArea(property.area_sqm)}</div>
                {#if property.rooms}
                  <div class="text-xs opacity-60">{property.rooms} rooms</div>
                {/if}
              </div>
            </div>

            <!-- Property Type -->
            {#if property.property_type}
              <div class="text-xs font-bold uppercase tracking-wide opacity-60 mb-3">
                {property.property_type}
              </div>
            {/if}

            <!-- Actions -->
            <div class="flex gap-2">
              <a
                href={property.url}
                target="_blank"
                rel="noopener"
                class="flex-1 px-4 py-2 text-center text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
              >
                View Listing ↗
              </a>
              {#if property.latitude && property.longitude}
                <button
                  onclick={() => viewOnMap(property.id)}
                  class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors"
                  title="View on map"
                >
                  🗺
                </button>
              {/if}
            </div>

            <!-- Meta -->
            <div class="flex items-center justify-between mt-3 pt-3 border-t border-base-300 text-xs opacity-50">
              <span>{formatDate(property.inserted_at)}</span>
              {#if property.aqi}
                <span class="font-bold {getAqiColor(property.aqi_category)}">AQI: {property.aqi}</span>
              {/if}
            </div>
          </div>
        </div>
      {:else}
        <div class="col-span-full py-12 text-center">
          <div class="text-lg font-bold uppercase tracking-wide opacity-40">No properties found</div>
          <div class="text-sm opacity-40">Try adjusting your filters</div>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Pagination -->
  {#if pagination.total_pages > 1}
    <div class="mt-6 flex flex-col sm:flex-row items-center justify-between gap-4">
      <div class="text-sm opacity-60">
        Showing {((pagination.page - 1) * pagination.page_size) + 1}–{Math.min(pagination.page * pagination.page_size, pagination.total_count)} of {pagination.total_count.toLocaleString()}
      </div>

      <div class="flex border-2 border-base-content">
        <button
          onclick={() => goToPage(pagination.page - 1)}
          disabled={pagination.page === 1}
          class="px-4 py-2 text-sm font-bold uppercase tracking-wide hover:bg-base-content hover:text-base-100 transition-colors disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer"
        >
          ←
        </button>

        {#if pagination.page > 2}
          <button onclick={() => goToPage(1)} class="px-3 py-2 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer">
            1
          </button>
        {/if}

        {#if pagination.page > 3}
          <span class="px-2 py-2 text-sm border-l-2 border-base-content opacity-50">...</span>
        {/if}

        {#if pagination.page > 1}
          <button onclick={() => goToPage(pagination.page - 1)} class="px-3 py-2 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer">
            {pagination.page - 1}
          </button>
        {/if}

        <span class="px-3 py-2 text-sm font-bold border-l-2 border-base-content bg-base-content text-base-100">
          {pagination.page}
        </span>

        {#if pagination.page < pagination.total_pages}
          <button onclick={() => goToPage(pagination.page + 1)} class="px-3 py-2 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer">
            {pagination.page + 1}
          </button>
        {/if}

        {#if pagination.page < pagination.total_pages - 2}
          <span class="px-2 py-2 text-sm border-l-2 border-base-content opacity-50">...</span>
        {/if}

        {#if pagination.page < pagination.total_pages - 1}
          <button onclick={() => goToPage(pagination.total_pages)} class="px-3 py-2 text-sm font-bold border-l-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer">
            {pagination.total_pages}
          </button>
        {/if}

        <button
          onclick={() => goToPage(pagination.page + 1)}
          disabled={pagination.page === pagination.total_pages}
          class="px-4 py-2 text-sm font-bold uppercase tracking-wide border-l-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors disabled:opacity-30 disabled:cursor-not-allowed cursor-pointer"
        >
          →
        </button>
      </div>
    </div>
  {/if}
</div>

<!-- Floating image preview (follows cursor) -->
{#if previewImage}
  <div
    class="fixed z-[9999] pointer-events-none bg-base-100 p-1 shadow-2xl border-2 border-base-content"
    style="left: {previewX}px; top: {previewY}px;"
  >
    <img
      src={previewImage}
      alt="Preview"
      class="max-w-[320px] max-h-[240px] object-contain"
    />
  </div>
{/if}
