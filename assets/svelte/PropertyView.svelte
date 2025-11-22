<script>
  import PropertyTable from './PropertyTable.svelte'
  import PropertyMap from './PropertyMap.svelte'

  export let properties = []
  export let map_properties = []
  export let pagination = { page: 1, page_size: 50, total_count: 0, total_pages: 1 }
  export let stats = { total_count: 0, with_coords: 0, with_aqi: 0 }
  export let live

  let currentView = 'table' // 'table' or 'map'

  function switchView(view) {
    currentView = view
  }

  function triggerGeocode() {
    if (confirm('Start geocoding? This will add coordinates to up to 50 properties using Google Geocoding API.')) {
      live.pushEvent('trigger_geocoding', {})
    }
  }
</script>

<div class="container mx-auto p-4">
  <!-- Header with view toggle -->
  <div class="mb-6">
    <div class="flex justify-between items-center mb-4">
      <h1 class="text-3xl font-bold">Real Estate Listings - Małopolskie</h1>

      <!-- View Toggle and Actions -->
      <div class="flex gap-2">
        <button
          onclick={triggerGeocode}
          class="btn btn-accent btn-sm"
          title="Add coordinates to properties without geocoding"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          Geocode Now
        </button>

        <div class="btn-group">
          <button
            class="btn btn-sm {currentView === 'table' ? 'btn-active' : ''}"
            onclick={() => switchView('table')}
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M3 14h18m-9-4v8m-7 0h14a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            Table
          </button>
          <button
            class="btn btn-sm {currentView === 'map' ? 'btn-active' : ''}"
            onclick={() => switchView('map')}
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
            </svg>
            Map
          </button>
        </div>
      </div>
    </div>

    <!-- Stats -->
    <div class="stats shadow mb-4 w-full">
      <div class="stat">
        <div class="stat-title">Total Listings</div>
        <div class="stat-value text-primary">{stats.total_count}</div>
        <div class="stat-desc">Showing {properties.length} on page {pagination.page}</div>
      </div>
      <div class="stat">
        <div class="stat-title">With Coordinates</div>
        <div class="stat-value text-secondary">{stats.with_coords}</div>
        <div class="stat-desc">Ready for mapping</div>
      </div>
      <div class="stat">
        <div class="stat-title">With AQI Data</div>
        <div class="stat-value text-accent">{stats.with_aqi}</div>
        <div class="stat-desc">Air quality analyzed</div>
      </div>
    </div>
  </div>

  <!-- View Content -->
  {#if currentView === 'table'}
    <PropertyTable {properties} {pagination} {live} />
  {:else}
    <PropertyMap properties={map_properties} {live} />
  {/if}
</div>
