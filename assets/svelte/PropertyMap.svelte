<script>
  import { onMount, onDestroy } from 'svelte'

  export let properties = []
  export let live
  export let selectedPropertyId = null

  let mapContainer
  let map
  let markers = []
  let markersByPropertyId = {} // Map of property ID to marker
  let infoWindow = null
  let google
  let browser = false
  let mapLoaded = false
  let loadError = null
  let aqHeatmapLayer = null
  let showHeatmap = true

  // Listen for favorite updates from server (instant UI update)
  if (live && live.handleEvent) {
    live.handleEvent('favorite-updated', ({ property_id, is_favorited }) => {
      // Update the property in the local properties array
      properties = properties.map(p =>
        p.id === property_id ? { ...p, is_favorited } : p
      )
    })
  }

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
      <div style="min-width: 280px; max-width: 350px; font-family: system-ui, sans-serif; padding: 8px;">
        ${property.image_url ? `
          <div style="margin-bottom: 12px; margin: -8px -8px 12px -8px;">
            <img
              src="${property.image_url}"
              alt="${property.title || 'Property'}"
              style="
                width: 100%;
                height: auto;
                max-height: 250px;
                object-fit: cover;
                border-radius: 8px 8px 0 0;
                display: block;
              "
              onerror="this.parentElement.style.display='none'"
            />
          </div>
        ` : ''}
        <div style="padding: 0 8px;">
          <div style="font-weight: bold; font-size: 14px; margin-bottom: 8px; color: #1F2937; line-height: 1.4;">
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

    console.log('Adding Air Quality heatmap...')

    // Define custom tile layer for Air Quality heatmap
    aqHeatmapLayer = new google.maps.ImageMapType({
      getTileUrl: function(coord, zoom) {
        // Air Quality API heatmap tiles endpoint
        // Using US_AQI (works globally, including Europe)
        // Alternative: EUROPEAN_AQI for European-specific scale
        const tileUrl = `https://airquality.googleapis.com/v1/mapTypes/US_AQI/heatmapTiles/${zoom}/${coord.x}/${coord.y}?key=${apiKey}`

        // Log first few tile requests for debugging
        if (Math.random() < 0.1) { // Log ~10% of requests to avoid spam
          console.log('Requesting AQ tile:', { zoom, x: coord.x, y: coord.y })
          console.log('Tile URL (partial):', tileUrl.substring(0, 80) + '...')
        }

        return tileUrl
      },
      tileSize: new google.maps.Size(256, 256),
      name: 'Air Quality',
      opacity: 0.4, // More transparent so map is more visible
      minZoom: 0,
      maxZoom: 16,
    })

    // Add heatmap as an overlay
    map.overlayMapTypes.push(aqHeatmapLayer)

    console.log('✓ Air Quality heatmap overlay added to map')
    console.log('Current overlay count:', map.overlayMapTypes.getLength())

    // Test if a tile loads by creating an image element
    const testTileUrl = `https://airquality.googleapis.com/v1/mapTypes/US_AQI/heatmapTiles/11/1099/671?key=${apiKey}`
    const testImg = new Image()
    testImg.onload = () => {
      console.log('✓ Test AQ tile loaded successfully')
    }
    testImg.onerror = (e) => {
      console.error('✗ Test AQ tile failed to load:', e)
      console.error('This likely means:')
      console.error('1. Air Quality API is not enabled for your API key')
      console.error('2. API key lacks proper permissions')
      console.error('3. Billing is not set up')
      console.error('Visit: https://console.cloud.google.com/apis/library/airquality.googleapis.com')
    }
    testImg.src = testTileUrl
  }

  // Toggle heatmap visibility
  function toggleHeatmap() {
    showHeatmap = !showHeatmap
  }

  // Update heatmap visibility when toggle changes
  $: if (map && aqHeatmapLayer) {
    if (showHeatmap) {
      // Check if heatmap is already in overlays
      const index = map.overlayMapTypes.getArray().indexOf(aqHeatmapLayer)
      if (index === -1) {
        map.overlayMapTypes.push(aqHeatmapLayer)
      }
    } else {
      // Remove heatmap from overlays
      const index = map.overlayMapTypes.getArray().indexOf(aqHeatmapLayer)
      if (index !== -1) {
        map.overlayMapTypes.removeAt(index)
      }
    }
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
    markersByPropertyId = {}

    // Filter properties with valid coordinates
    const validProperties = properties.filter(p => p.latitude && p.longitude)

    if (validProperties.length === 0) return

    const bounds = new google.maps.LatLngBounds()

    // Create or reuse info window
    if (!infoWindow) {
      infoWindow = new google.maps.InfoWindow()
    }

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

        // Pan map to ensure popup is visible (with some offset for popup height)
        // Wait a bit for InfoWindow to render and get its size
        setTimeout(() => {
          const currentCenter = map.getCenter()
          const markerPosition = marker.getPosition()

          // Calculate offset to move map down slightly so popup fits above marker
          const scale = Math.pow(2, map.getZoom())
          const worldCoordinate = map.getProjection().fromLatLngToPoint(markerPosition)

          // Offset by ~150 pixels upward (adjust for popup height)
          const pixelOffset = new google.maps.Point(0, -150 / scale)
          const newCenter = map.getProjection().fromPointToLatLng(
            new google.maps.Point(
              worldCoordinate.x + pixelOffset.x,
              worldCoordinate.y + pixelOffset.y
            )
          )

          map.panTo(newCenter)
        }, 100)
      })

      markers.push(marker)
      markersByPropertyId[property.id] = marker
      bounds.extend(position)
    })

    // Fit map to show all markers (unless we're selecting a specific property)
    if (validProperties.length > 0 && !selectedPropertyId) {
      map.fitBounds(bounds)

      // Don't zoom in too much for a single property
      const listener = google.maps.event.addListener(map, 'idle', () => {
        if (map.getZoom() > 14) map.setZoom(14)
        google.maps.event.removeListener(listener)
      })
    }
  }

  // Reactive statement: Center on selected property when it changes
  $: if (map && google && selectedPropertyId && markersByPropertyId[selectedPropertyId]) {
    const marker = markersByPropertyId[selectedPropertyId]
    const property = properties.find(p => p.id === selectedPropertyId)

    if (marker && property) {
      // Center map on the selected property
      map.setCenter(marker.getPosition())
      map.setZoom(15) // Zoom in closer for individual property

      // Open the info window for this property
      infoWindow.setContent(createInfoWindowContent(property))
      infoWindow.open(map, marker)

      // Pan map to ensure popup is visible
      setTimeout(() => {
        const scale = Math.pow(2, map.getZoom())
        const worldCoordinate = map.getProjection().fromLatLngToPoint(marker.getPosition())
        const pixelOffset = new google.maps.Point(0, -150 / scale)
        const newCenter = map.getProjection().fromPointToLatLng(
          new google.maps.Point(
            worldCoordinate.x + pixelOffset.x,
            worldCoordinate.y + pixelOffset.y
          )
        )
        map.panTo(newCenter)
      }, 100)
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
        <div class="bg-base-100 border-2 border-error p-6 max-w-md">
          <h3 class="font-black uppercase tracking-wide text-error mb-2">Map Error</h3>
          <div class="text-sm mb-2">{loadError}</div>
          <div class="text-xs opacity-60">Make sure GOOGLE_MAPS_API_KEY is configured.</div>
        </div>
      {:else}
        <div class="text-center">
          <div class="inline-block w-8 h-8 border-4 border-base-content border-t-transparent rounded-full animate-spin"></div>
          <p class="mt-4 text-xs font-bold uppercase tracking-wide opacity-60">Loading map...</p>
        </div>
      {/if}
    </div>
  {/if}

  <!-- No Properties Overlay -->
  {#if browser && mapLoaded && properties.filter(p => p.latitude && p.longitude).length === 0}
    <div class="map-overlay">
      <div class="bg-base-100 border-2 border-base-content p-6 text-center">
        <div class="text-4xl mb-3">📍</div>
        <h3 class="font-black uppercase tracking-wide mb-2">No geocoded properties</h3>
        <div class="text-xs opacity-60">Properties need coordinates to appear on the map.</div>
        <div class="text-xs opacity-60">Click "Geocode" to add them.</div>
      </div>
    </div>
  {/if}

  <!-- Map Stats -->
  {#if browser && mapLoaded}
    <div class="map-stats">
      <div class="flex items-center gap-4">
        <div>
          <span class="font-black text-lg">{properties.filter(p => p.latitude && p.longitude).length}</span>
          <span class="text-[10px] font-bold uppercase tracking-wide opacity-60 ml-1">on map</span>
        </div>
        <div class="h-4 w-px bg-base-content/30"></div>
        <div>
          <span class="font-black text-lg">{properties.filter(p => p.aqi).length}</span>
          <span class="text-[10px] font-bold uppercase tracking-wide opacity-60 ml-1">with AQI</span>
        </div>
      </div>
    </div>

    <!-- Legend -->
    <div class="map-legend">
      <div class="legend-title">Air Quality Index</div>

      <!-- Heatmap Toggle -->
      <label class="heatmap-toggle">
        <input
          type="checkbox"
          bind:checked={showHeatmap}
        />
        <span>Show Heatmap Overlay</span>
      </label>

      <div class="legend-subtitle">Marker Colors</div>
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
        <span>Sensitive (101-150)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #EF4444;"></span>
        <span>Unhealthy (151-200)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #A855F7;"></span>
        <span>Very Unhealthy (201-300)</span>
      </div>
      <div class="legend-item">
        <span class="legend-dot" style="background-color: #9CA3AF;"></span>
        <span>No data</span>
      </div>
    </div>
  {/if}
</div>

<style>
  .map-wrapper {
    position: relative;
    width: 100%;
    height: 700px;
    border: 2px solid oklch(var(--bc));
    overflow: hidden;
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
    background-color: oklch(var(--b2));
    z-index: 2000;
  }

  .map-stats {
    position: absolute;
    top: 12px;
    left: 12px;
    background: oklch(var(--b1));
    border: 2px solid oklch(var(--bc));
    padding: 8px 12px;
    z-index: 1000;
    font-size: 12px;
  }

  .map-legend {
    position: absolute;
    bottom: 12px;
    right: 12px;
    background: oklch(var(--b1));
    border: 2px solid oklch(var(--bc));
    padding: 0;
    z-index: 1000;
    font-size: 11px;
    min-width: 180px;
  }

  .legend-title {
    font-weight: 800;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 8px 12px;
    background: oklch(var(--b2));
    border-bottom: 2px solid oklch(var(--bc));
  }

  .heatmap-toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    cursor: pointer;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    border-bottom: 1px solid oklch(var(--bc) / 0.2);
    transition: background 0.15s;
  }

  .heatmap-toggle:hover {
    background: oklch(var(--b2));
  }

  .heatmap-toggle input {
    width: 14px;
    height: 14px;
    accent-color: oklch(var(--p));
    cursor: pointer;
  }

  .legend-subtitle {
    font-weight: 700;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 6px 12px;
    opacity: 0.5;
    border-bottom: 1px solid oklch(var(--bc) / 0.2);
  }

  .legend-item {
    display: flex;
    align-items: center;
    padding: 4px 12px;
    font-size: 10px;
  }

  .legend-item:last-child {
    padding-bottom: 8px;
  }

  .legend-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    margin-right: 8px;
    border: 2px solid white;
    box-shadow: 0 1px 2px rgba(0,0,0,0.2);
    flex-shrink: 0;
  }

  /* Make map responsive */
  @media (max-width: 768px) {
    .map-wrapper {
      height: 500px;
    }

    .map-stats {
      top: 8px;
      left: 8px;
      padding: 6px 10px;
      font-size: 11px;
    }

    .map-legend {
      bottom: 8px;
      right: 8px;
      min-width: 160px;
    }
  }
</style>
