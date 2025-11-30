<script>
  import PropertyTable from './PropertyTable.svelte'
  import PropertyMap from './PropertyMap.svelte'

  export let properties = []
  export let map_properties = []
  export let pagination = { page: 1, page_size: 50, total_count: 0, total_pages: 1 }
  export let stats = { total_count: 0, with_coords: 0, with_aqi: 0 }
  export let user_id = null
  export let live

  let currentView = 'table' // 'table', 'cards', or 'map'
  let selectedPropertyId = null // Property to highlight on map

  function switchView(view) {
    currentView = view
    // Notify server about view change (triggers lazy loading of map data)
    if (live && live.pushEvent) {
      live.pushEvent('view_changed', { view })
    }
  }

  function handleViewOnMap(event) {
    const propertyId = event.detail.propertyId
    selectedPropertyId = propertyId
    switchView('map')
  }

  function triggerGeocode() {
    if (confirm('Start geocoding? This will add coordinates to up to 50 properties using Google Geocoding API.')) {
      live.pushEvent('trigger_geocoding', {})
    }
  }

  // Calculate percentages for stats
  $: coordsPercent = stats.total_count > 0 ? Math.round((stats.with_coords / stats.total_count) * 100) : 0
  $: aqiPercent = stats.total_count > 0 ? Math.round((stats.with_aqi / stats.total_count) * 100) : 0
</script>

<div class="min-h-screen bg-base-200">
  <!-- Page Header -->
  <div class="bg-base-100 border-b-4 border-base-content">
    <div class="container mx-auto px-4 py-6">
      <!-- Navigation -->
      <nav class="flex gap-1 flex-wrap">
        <a href="/real-estate" class="px-3 py-2 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100">
          Properties
        </a>
        <a href="/favorites" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
          Favorites
        </a>
        <a href="/stats" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
          Stats
        </a>
        <a href="/hot-deals" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-warning text-warning hover:bg-warning hover:text-warning-content transition-colors">
          🔥 Hot Deals
        </a>
        <a href="/admin" class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-content hover:text-base-100 transition-colors">
          Admin
        </a>
      </nav>

      <!-- Title Row -->
      <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4 mt-4">
        <div>
          <h1 class="text-2xl md:text-3xl font-black uppercase tracking-tight">
            Properties
          </h1>
          <p class="text-sm font-bold uppercase tracking-wide opacity-60">
            Małopolskie Region
          </p>
        </div>

        <!-- View Toggle & Actions -->
        <div class="flex flex-wrap gap-2">
          <button
            onclick={triggerGeocode}
            class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-2 border-success text-success hover:bg-success hover:text-success-content transition-colors cursor-pointer"
          >
            📍 Geocode
          </button>

          <div class="flex border-2 border-base-content">
            <button
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide transition-colors cursor-pointer {currentView === 'table' ? 'bg-base-content text-base-100' : 'hover:bg-base-content hover:text-base-100'}"
              onclick={() => switchView('table')}
            >
              Table
            </button>
            <button
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-l-2 border-base-content transition-colors cursor-pointer {currentView === 'cards' ? 'bg-base-content text-base-100' : 'hover:bg-base-content hover:text-base-100'}"
              onclick={() => switchView('cards')}
            >
              Cards
            </button>
            <button
              class="px-4 py-2 text-xs font-bold uppercase tracking-wide border-l-2 border-base-content transition-colors cursor-pointer {currentView === 'map' ? 'bg-base-content text-base-100' : 'hover:bg-base-content hover:text-base-100'}"
              onclick={() => switchView('map')}
            >
              Map
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Stats Bar -->
  <div class="bg-base-100 border-b-2 border-base-content">
    <div class="container mx-auto">
      <div class="grid grid-cols-3 divide-x-2 divide-base-content">
        <!-- Total Listings -->
        <div class="py-2 px-3">
          <div class="text-xl font-black text-primary">{stats.total_count.toLocaleString()}</div>
          <div class="text-[10px] font-bold uppercase tracking-wide opacity-60">Total · p.{pagination.page}/{pagination.total_pages}</div>
        </div>

        <!-- With Coordinates -->
        <div class="py-2 px-3">
          <div class="text-xl font-black text-secondary">{stats.with_coords.toLocaleString()}</div>
          <div class="flex items-center gap-2">
            <span class="text-[10px] font-bold uppercase tracking-wide opacity-60">Geocoded</span>
            <div class="flex-1 h-1 bg-base-300 max-w-16">
              <div class="h-1 bg-secondary" style="width: {coordsPercent}%"></div>
            </div>
            <span class="text-[10px] font-bold opacity-60">{coordsPercent}%</span>
          </div>
        </div>

        <!-- With AQI -->
        <div class="py-2 px-3">
          <div class="text-xl font-black text-accent">{stats.with_aqi.toLocaleString()}</div>
          <div class="flex items-center gap-2">
            <span class="text-[10px] font-bold uppercase tracking-wide opacity-60">AQI</span>
            <div class="flex-1 h-1 bg-base-300 max-w-16">
              <div class="h-1 bg-accent" style="width: {aqiPercent}%"></div>
            </div>
            <span class="text-[10px] font-bold opacity-60">{aqiPercent}%</span>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Main Content -->
  <div class="container mx-auto px-4 py-6">
    {#if currentView === 'table'}
      <PropertyTable {properties} {pagination} {user_id} {live} viewMode="table" on:viewOnMap={handleViewOnMap} />
    {:else if currentView === 'cards'}
      <PropertyTable {properties} {pagination} {user_id} {live} viewMode="cards" on:viewOnMap={handleViewOnMap} />
    {:else}
      <PropertyMap properties={map_properties} {live} {selectedPropertyId} />
    {/if}
  </div>
</div>
