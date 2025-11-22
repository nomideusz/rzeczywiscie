<script>
  import { onMount, onDestroy } from 'svelte'

  export let properties = []
  export let live

  let mapContainer
  let map
  let markers = []
  let google
  let browser = false
  let mapLoaded = false
  let loadError = null

  // Default center: Kraków, Małopolskie
  const DEFAULT_CENTER = { lat: 50.0647, lng: 19.9450 }
  const DEFAULT_ZOOM = 11

  // Get Google Maps API key from meta tag
  function getApiKey() {
    const meta = document.querySelector('meta[name="google-maps-api-key"]')
    const apiKey = meta ? meta.getAttribute('content') : ''
    console.log('API key from meta tag:', apiKey ? `${apiKey.substring(0, 10)}...` : 'EMPTY')
    console.log('Meta tag found:', !!meta)
    return apiKey
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

  // Get marker color based on AQI
  function getMarkerColor(aqi) {
    if (!aqi) return '#9CA3AF'        // Gray - No data
    if (aqi <= 50) return '#10B981'   // Green - Good
    if (aqi <= 100) return '#F59E0B'  // Yellow - Moderate
    if (aqi <= 150) return '#F97316'  // Orange - Unhealthy for sensitive
    if (aqi <= 200) return '#EF4444'  // Red - Unhealthy
    if (aqi <= 300) return '#A855F7'  // Purple - Very unhealthy
    return '#7C2D12'                   // Dark red - Hazardous
  }

  // Create info window content
  function createInfoWindowContent(property) {
    const aqiBadgeColor = property.aqi
      ? (property.aqi <= 50 ? '#10B981' : property.aqi <= 100 ? '#F59E0B' : '#EF4444')
      : '#9CA3AF'

    return `
      <div style="min-width: 250px; font-family: system-ui, sans-serif; padding: 8px;">
        <div style="font-weight: bold; font-size: 14px; margin-bottom: 8px; color: #1F2937;">
          ${property.title || 'N/A'}
        </div>
        <div style="margin-bottom: 4px; color: #6B7280; font-size: 13px;">
          📍 ${property.city || 'N/A'}${property.district ? ', ' + property.district : ''}
        </div>
        <div style="margin-bottom: 4px; color: #1F2937; font-size: 14px; font-weight: 600;">
          💰 ${formatPrice(property.price)}
        </div>
        ${property.area_sqm ? `<div style="margin-bottom: 4px; color: #6B7280; font-size: 13px;">📐 ${property.area_sqm} m²</div>` : ''}
        ${property.rooms ? `<div style="margin-bottom: 4px; color: #6B7280; font-size: 13px;">🛏️ ${property.rooms} rooms</div>` : ''}
        ${property.aqi ? `
          <div style="margin-bottom: 8px; margin-top: 8px;">
            <span style="
              background-color: ${aqiBadgeColor};
              color: white;
              padding: 4px 8px;
              border-radius: 4px;
              font-size: 12px;
              font-weight: 600;
            ">
              AQI: ${property.aqi} - ${property.aqi_category || 'N/A'}
            </span>
          </div>
        ` : ''}
        <div style="margin-top: 12px;">
          <a
            href="${property.url}"
            target="_blank"
            rel="noopener noreferrer"
            style="
              display: inline-block;
              background-color: #3B82F6;
              color: white;
              padding: 6px 12px;
              border-radius: 4px;
              text-decoration: none;
              font-size: 12px;
              font-weight: 500;
            "
          >
            View Listing →
          </a>
        </div>
      </div>
    `
  }

  // Load Google Maps API
  async function loadGoogleMaps() {
    return new Promise((resolve, reject) => {
      if (window.google && window.google.maps) {
        resolve(window.google)
        return
      }

      const apiKey = getApiKey()
      if (!apiKey) {
        console.warn('Google Maps API key not found')
        resolve(null)
        return
      }

      const script = document.createElement('script')
      script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&libraries=marker`
      script.async = true
      script.defer = true
      script.onload = () => resolve(window.google)
      script.onerror = reject
      document.head.appendChild(script)
    })
  }

  // Initialize map (client-side only)
  onMount(async () => {
    console.log('PropertyMap onMount called')
    console.log('mapContainer exists:', !!mapContainer)
    console.log('window exists:', typeof window !== 'undefined')

    if (!mapContainer) {
      console.error('mapContainer not found')
      return
    }
    if (typeof window === 'undefined') {
      console.error('window is undefined')
      return
    }

    browser = true
    console.log('Browser flag set to true')

    try {
      console.log('Loading Google Maps...')
      google = await loadGoogleMaps()

      if (!google) {
        loadError = 'Google Maps API key not configured'
        console.error('Failed to load Google Maps - no API key')
        return
      }

      console.log('Google Maps loaded, creating map...')

      // Create map
      map = new google.maps.Map(mapContainer, {
        center: DEFAULT_CENTER,
        zoom: DEFAULT_ZOOM,
      })

      console.log('Map created successfully')

      // Add Air Quality heatmap overlay
      addAirQualityHeatmap()

      mapLoaded = true

      // Add markers
      updateMarkers()
    } catch (error) {
      console.error('Error loading Google Maps:', error)
      loadError = error.message || 'Failed to load map'
    }
  })

  // Add Air Quality heatmap overlay
  function addAirQualityHeatmap() {
    if (!map || !google) return

    const apiKey = getApiKey()
    if (!apiKey) {
      console.warn('Cannot add AQ heatmap: no API key')
      return
    }

    // Define custom tile layer for Air Quality heatmap
    const aqHeatmapType = new google.maps.ImageMapType({
      getTileUrl: function(coord, zoom) {
        // Air Quality API heatmap tiles endpoint
        // Using UAQI (Universal Air Quality Index) which works globally
        return `https://airquality.googleapis.com/v1/mapTypes/UAQI/heatmapTiles/${zoom}/${coord.x}/${coord.y}?key=${apiKey}`
      },
      tileSize: new google.maps.Size(256, 256),
      name: 'Air Quality',
      opacity: 0.6, // Make it semi-transparent so we can see the map underneath
    })

    // Add heatmap as an overlay
    map.overlayMapTypes.push(aqHeatmapType)

    console.log('Air Quality heatmap overlay added')
  }

  // Update markers when properties change
  $: if (map && google && properties && browser) {
    updateMarkers()
  }

  function updateMarkers() {
    if (!map || !google) return

    // Clear existing markers
    markers.forEach(marker => marker.setMap(null))
    markers = []

    // Filter properties with valid coordinates
    const validProperties = properties.filter(p => p.latitude && p.longitude)

    if (validProperties.length === 0) return

    const bounds = new google.maps.LatLngBounds()
    const infoWindow = new google.maps.InfoWindow()

    // Add markers for each property
    validProperties.forEach(property => {
      const position = { lat: property.latitude, lng: property.longitude }
      const color = getMarkerColor(property.aqi)

      // Create custom marker with colored pin
      const marker = new google.maps.Marker({
        position,
        map,
        title: property.title,
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 8,
          fillColor: color,
          fillOpacity: 1,
          strokeColor: '#FFFFFF',
          strokeWeight: 2,
        }
      })

      // Add click listener for info window
      marker.addListener('click', () => {
        infoWindow.setContent(createInfoWindowContent(property))
        infoWindow.open(map, marker)
      })

      markers.push(marker)
      bounds.extend(position)
    })

    // Fit map to show all markers
    if (validProperties.length > 0) {
      map.fitBounds(bounds)

      // Don't zoom in too much for a single property
      const listener = google.maps.event.addListener(map, 'idle', () => {
        if (map.getZoom() > 14) map.setZoom(14)
        google.maps.event.removeListener(listener)
      })
    }
  }

  // Cleanup on destroy
  onDestroy(() => {
    markers.forEach(marker => marker.setMap(null))
    markers = []
  })
</script>

<div class="map-wrapper">
  <!-- Map Container - Always present in DOM -->
  <div bind:this={mapContainer} class="map-container"></div>

  <!-- Loading/Error State Overlay -->
  {#if !browser || !mapLoaded}
    <div class="map-overlay-full">
      {#if loadError}
        <div class="alert alert-error max-w-md">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <h3 class="font-bold">Map Error</h3>
            <div class="text-sm">{loadError}</div>
            <div class="text-xs mt-2">Make sure GOOGLE_MAPS_API_KEY is configured.</div>
          </div>
        </div>
      {:else}
        <div class="text-center">
          <div class="loading loading-spinner loading-lg"></div>
          <p class="mt-4 text-gray-600">Loading map...</p>
        </div>
      {/if}
    </div>
  {/if}

  <!-- No Properties Overlay -->
  {#if browser && mapLoaded && properties.filter(p => p.latitude && p.longitude).length === 0}
    <div class="map-overlay">
      <div class="alert alert-info shadow-lg">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <div>
          <h3 class="font-bold">No geocoded properties</h3>
          <div class="text-xs">Properties need coordinates to appear on the map. Click "Geocode Now" to add them.</div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Legend -->
  {#if browser && mapLoaded}
    <div class="map-legend">
      <div class="legend-title">Air Quality</div>
      <div class="text-xs opacity-70 mb-2">Heatmap shows regional AQ</div>
      <div class="legend-subtitle">Property Markers</div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #10B981;"></span>
        <span>Good (0-50)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #F59E0B;"></span>
        <span>Moderate (51-100)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #F97316;"></span>
        <span>Unhealthy* (101-150)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #EF4444;"></span>
        <span>Unhealthy (151-200)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #9CA3AF;"></span>
        <span>No AQI data</span>
      </div>
    </div>
  {/if}
</div>

<style>
  .map-wrapper {
    position: relative;
    width: 100%;
    height: 600px;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1);
  }

  .map-container {
    width: 100%;
    height: 100%;
  }

  .map-overlay {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    z-index: 1000;
    pointer-events: none;
  }

  .map-overlay .alert {
    pointer-events: auto;
  }

  .map-overlay-full {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: #f3f4f6;
    z-index: 2000;
  }

  .map-legend {
    position: absolute;
    bottom: 20px;
    right: 20px;
    background: white;
    padding: 12px;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    z-index: 1000;
    font-size: 12px;
  }

  .legend-title {
    font-weight: 600;
    margin-bottom: 4px;
    color: #1F2937;
  }

  .legend-subtitle {
    font-weight: 500;
    font-size: 11px;
    margin-top: 8px;
    margin-bottom: 4px;
    color: #4B5563;
  }

  .legend-item {
    display: flex;
    align-items: center;
    margin-bottom: 4px;
    color: #6B7280;
  }

  .legend-dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-right: 8px;
    border: 2px solid white;
    box-shadow: 0 1px 3px rgba(0,0,0,0.3);
  }

  /* Make map responsive */
  @media (max-width: 768px) {
    .map-wrapper {
      height: 400px;
    }

    .map-legend {
      bottom: 10px;
      right: 10px;
      font-size: 10px;
      padding: 8px;
    }

    .legend-dot {
      width: 10px;
      height: 10px;
    }
  }
</style>
