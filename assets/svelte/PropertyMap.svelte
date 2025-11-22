<script>
  import { onMount, onDestroy } from 'svelte'
  import L from 'leaflet'
  import 'leaflet.markercluster'

  export let properties = []
  export let live

  let mapContainer
  let map
  let markerClusterGroup

  // Default center: Kraków, Małopolskie
  const DEFAULT_CENTER = [50.0647, 19.9450]
  const DEFAULT_ZOOM = 11

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
    if (!aqi) return 'gray'
    if (aqi <= 50) return 'green'      // Good
    if (aqi <= 100) return 'yellow'    // Moderate
    if (aqi <= 150) return 'orange'    // Unhealthy for sensitive
    if (aqi <= 200) return 'red'       // Unhealthy
    if (aqi <= 300) return 'purple'    // Very unhealthy
    return 'darkred'                   // Hazardous
  }

  // Create custom marker icon
  function createMarkerIcon(color) {
    return L.divIcon({
      className: 'custom-marker',
      html: `<div style="
        background-color: ${color};
        width: 24px;
        height: 24px;
        border-radius: 50%;
        border: 2px solid white;
        box-shadow: 0 2px 5px rgba(0,0,0,0.3);
      "></div>`,
      iconSize: [24, 24],
      iconAnchor: [12, 12],
      popupAnchor: [0, -12]
    })
  }

  // Create popup content
  function createPopupContent(property) {
    const aqiBadgeColor = property.aqi
      ? (property.aqi <= 50 ? '#10b981' : property.aqi <= 100 ? '#f59e0b' : '#ef4444')
      : '#9ca3af'

    return `
      <div style="min-width: 250px; font-family: system-ui, sans-serif;">
        <div style="font-weight: bold; font-size: 14px; margin-bottom: 8px; color: #1f2937;">
          ${property.title || 'N/A'}
        </div>
        <div style="margin-bottom: 4px; color: #4b5563; font-size: 13px;">
          📍 ${property.city || 'N/A'}${property.district ? ', ' + property.district : ''}
        </div>
        <div style="margin-bottom: 4px; color: #1f2937; font-size: 14px; font-weight: 600;">
          💰 ${formatPrice(property.price)}
        </div>
        ${property.area_sqm ? `<div style="margin-bottom: 4px; color: #4b5563; font-size: 13px;">📐 ${property.area_sqm} m²</div>` : ''}
        ${property.rooms ? `<div style="margin-bottom: 4px; color: #4b5563; font-size: 13px;">🛏️ ${property.rooms} rooms</div>` : ''}
        ${property.aqi ? `
          <div style="margin-bottom: 8px; margin-top: 8px;">
            <span style="
              background-color: ${aqiBadgeColor};
              color: white;
              padding: 2px 8px;
              border-radius: 4px;
              font-size: 12px;
              font-weight: 600;
            ">
              AQI: ${property.aqi} - ${property.aqi_category || 'N/A'}
            </span>
          </div>
        ` : ''}
        <div style="margin-top: 8px;">
          <a
            href="${property.url}"
            target="_blank"
            rel="noopener noreferrer"
            style="
              display: inline-block;
              background-color: #3b82f6;
              color: white;
              padding: 4px 12px;
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

  // Initialize map
  onMount(() => {
    if (!mapContainer) return

    // Create map
    map = L.map(mapContainer, {
      center: DEFAULT_CENTER,
      zoom: DEFAULT_ZOOM,
      scrollWheelZoom: true
    })

    // Add OpenStreetMap tile layer
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors',
      maxZoom: 19
    }).addTo(map)

    // Create marker cluster group
    markerClusterGroup = L.markerClusterGroup({
      maxClusterRadius: 50,
      spiderfyOnMaxZoom: true,
      showCoverageOnHover: false,
      zoomToBoundsOnClick: true
    })

    map.addLayer(markerClusterGroup)

    // Add markers
    updateMarkers()

    // Fix Leaflet icon paths
    delete L.Icon.Default.prototype._getIconUrl
    L.Icon.Default.mergeOptions({
      iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
      iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
      shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png'
    })
  })

  // Update markers when properties change
  $: if (map && markerClusterGroup && properties) {
    updateMarkers()
  }

  function updateMarkers() {
    if (!markerClusterGroup) return

    // Clear existing markers
    markerClusterGroup.clearLayers()

    // Filter properties with valid coordinates
    const validProperties = properties.filter(p => p.latitude && p.longitude)

    if (validProperties.length === 0) return

    // Add markers for each property
    validProperties.forEach(property => {
      const marker = L.marker(
        [property.latitude, property.longitude],
        { icon: createMarkerIcon(getMarkerColor(property.aqi)) }
      )

      marker.bindPopup(createPopupContent(property))
      markerClusterGroup.addLayer(marker)
    })

    // Fit map to show all markers
    if (validProperties.length > 0) {
      const bounds = markerClusterGroup.getBounds()
      if (bounds.isValid()) {
        map.fitBounds(bounds, { padding: [50, 50], maxZoom: 14 })
      }
    }
  }

  // Cleanup on destroy
  onDestroy(() => {
    if (map) {
      map.remove()
      map = null
    }
  })
</script>

<div class="map-wrapper">
  <div bind:this={mapContainer} class="map-container"></div>

  {#if properties.filter(p => p.latitude && p.longitude).length === 0}
    <div class="map-overlay">
      <div class="alert alert-info shadow-lg">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
        <div>
          <h3 class="font-bold">No geocoded properties</h3>
          <div class="text-xs">Properties need coordinates to appear on the map. The geocoding worker runs hourly.</div>
        </div>
      </div>
    </div>
  {/if}

  <!-- Legend -->
  <div class="map-legend">
    <div class="legend-title">Air Quality Index</div>
    <div class="legend-item">
      <span class="legend-dot" style="background-color: green;"></span>
      <span>Good (0-50)</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background-color: yellow;"></span>
      <span>Moderate (51-100)</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background-color: orange;"></span>
      <span>Unhealthy* (101-150)</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background-color: red;"></span>
      <span>Unhealthy (151-200)</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background-color: gray;"></span>
      <span>No AQI data</span>
    </div>
  </div>
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
    margin-bottom: 8px;
    color: #1f2937;
  }

  .legend-item {
    display: flex;
    align-items: center;
    margin-bottom: 4px;
    color: #4b5563;
  }

  .legend-dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-right: 8px;
    border: 1px solid white;
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
