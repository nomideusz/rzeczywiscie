// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {getHooks} from "live_svelte"
import * as Components from "../svelte/**/*.svelte"

// Generate device fingerprint based on stable hardware characteristics
// This creates the same ID across different browsers on the same physical device
// ONLY uses values that are guaranteed to be identical across all browsers
function generateDeviceFingerprint() {
    // These values come from the OS, not the browser:
    const components = [
        screen.width,                    // Physical screen width (OS-level)
        screen.height,                   // Physical screen height (OS-level)
        screen.colorDepth,               // Color depth (OS-level)
        new Date().getTimezoneOffset(),  // Timezone offset (OS-level)
        screen.availWidth,               // Available width minus taskbar (OS-level)
        screen.availHeight               // Available height minus taskbar (OS-level)
    ]
    
    const fingerprint = components.join('|')
    
    // Simple hash function (FNV-1a variant)
    let hash = 2166136261 // FNV offset basis
    for (let i = 0; i < fingerprint.length; i++) {
        hash ^= fingerprint.charCodeAt(i)
        hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24)
    }
    
    // Convert to positive hex string
    return (hash >>> 0).toString(16)
}

// Generate or retrieve browser UUID (unique per browser, stored in localStorage)
function getBrowserId() {
    const storageKey = 'friends_browser_id'
    let browserId = localStorage.getItem(storageKey)
    
    if (!browserId) {
        // Generate a new UUID
        browserId = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            const r = Math.random() * 16 | 0
            const v = c === 'x' ? r : (r & 0x3 | 0x8)
            return v.toString(16)
        })
        localStorage.setItem(storageKey, browserId)
    }
    
    return browserId
}

// Generate a high-quality thumbnail as base64 data URL
function generateThumbnail(file, maxSize = 600) {
    return new Promise((resolve) => {
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(null)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img
            
            // Resize to thumbnail size
            if (width > height) {
                height = Math.round((height * maxSize) / width)
                width = maxSize
            } else {
                width = Math.round((width * maxSize) / height)
                height = maxSize
            }

            canvas.width = width
            canvas.height = height
            
            // Use better image smoothing
            ctx.imageSmoothingEnabled = true
            ctx.imageSmoothingQuality = 'high'
            ctx.drawImage(img, 0, 0, width, height)

            // Convert to base64 data URL with high quality
            const dataUrl = canvas.toDataURL('image/jpeg', 0.85)
            URL.revokeObjectURL(img.src)
            resolve(dataUrl)
        }

        img.onerror = () => resolve(null)
        img.src = URL.createObjectURL(file)
    })
}

// Optimize image before upload - resize to max dimension while preserving aspect ratio
function optimizeImage(file, maxSize = 1200) {
    return new Promise((resolve) => {
        // Skip non-images or GIFs (preserve animation)
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(file)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img
            
            // Only resize if larger than maxSize
            if (width > maxSize || height > maxSize) {
                if (width > height) {
                    height = Math.round((height * maxSize) / width)
                    width = maxSize
                } else {
                    width = Math.round((width * maxSize) / height)
                    height = maxSize
                }
            }

            canvas.width = width
            canvas.height = height
            ctx.drawImage(img, 0, 0, width, height)

            // Convert to blob with quality compression
            canvas.toBlob((blob) => {
                if (blob) {
                    // Create a new file with the optimized blob
                    const optimizedFile = new File([blob], file.name, {
                        type: 'image/jpeg',
                        lastModified: Date.now()
                    })
                    resolve(optimizedFile)
                } else {
                    resolve(file)
                }
            }, 'image/jpeg', 0.85)
        }

        img.onerror = () => resolve(file)
        img.src = URL.createObjectURL(file)
    })
}

const Hooks = {
    ...getHooks(Components),
    FlashAutoClose: {
        mounted() {
            // Auto-dismiss flash messages after 4 seconds
            this.timeout = setTimeout(() => {
                this.el.click() // Trigger the phx-click event to dismiss
            }, 4000)
        },
        destroyed() {
            if (this.timeout) {
                clearTimeout(this.timeout)
            }
        }
    },
    ScrollToBottom: {
        mounted() {
            this.scrollToBottom()
            // Watch for new messages
            this.observer = new MutationObserver(() => this.scrollToBottom())
            this.observer.observe(this.el, { childList: true, subtree: true })
        },
        scrollToBottom() {
            this.el.scrollTop = this.el.scrollHeight
        },
        destroyed() {
            if (this.observer) this.observer.disconnect()
        }
    },
    DeviceFingerprint: {
        mounted() {
            // Get browser UUID and device fingerprint
            const browserId = getBrowserId()
            const deviceFingerprint = generateDeviceFingerprint()
            this.pushEvent("set_user_id", { 
                browser_id: browserId,
                device_fingerprint: deviceFingerprint,
                // For backwards compatibility, also send combined user_id
                user_id: browserId
            })
        }
    },
    FriendsApp: {
        mounted() {
            // Get browser UUID (unique per browser, stored in localStorage)
            this.browserId = getBrowserId()
            // Get device fingerprint (same across browsers on same device)
            this.deviceFingerprint = generateDeviceFingerprint()
            
            // Check if we need to restore modal state after reconnect
            const savedModal = sessionStorage.getItem('friends_open_modal')
            const savedInput = sessionStorage.getItem('friends_modal_input')
            
            // Send both IDs to server for registration, plus any saved modal state
            this.pushEvent("set_user_id", { 
                browser_id: this.browserId,
                device_fingerprint: this.deviceFingerprint,
                restore_modal: savedModal,
                restore_input: savedInput
            })
            
            // Clear saved modal state after sending
            sessionStorage.removeItem('friends_open_modal')
            sessionStorage.removeItem('friends_modal_input')
            
            // Listen for save_user_name event from server
            this.handleEvent("save_user_name", ({ name }) => {
                // Username is managed server-side now, just log it
                console.log('Username updated:', name)
            })
            
            // Listen for same_device_detected event (suggest linking)
            this.handleEvent("same_device_detected", ({ existing_name }) => {
                console.log('Same device detected with existing account:', existing_name)
                // UI will show linking option
            })
            
            // Listen for browser_linked event
            this.handleEvent("browser_linked", ({ master_user_id, user_name }) => {
                console.log('Browser linked to account:', master_user_id, 'as', user_name)
            })
            
            // Listen for modal state changes to save them
            this.handleEvent("modal_opened", ({ modal, input }) => {
                sessionStorage.setItem('friends_open_modal', modal)
                if (input) sessionStorage.setItem('friends_modal_input', input)
            })
            
            this.handleEvent("modal_closed", () => {
                sessionStorage.removeItem('friends_open_modal')
                sessionStorage.removeItem('friends_modal_input')
            })
            
            // Intercept file input to optimize images before upload
            this.setupImageOptimization()
        },
        
        setupImageOptimization() {
            // Find the file input in the upload form
            const form = this.el.querySelector('#upload-form')
            if (!form) return
            
            const fileInput = form.querySelector('input[type="file"]')
            if (!fileInput) return
            
            // Store pending thumbnail
            this.pendingThumbnail = null
            
            // Listen for photo_uploaded event to associate thumbnail
            this.handleEvent("photo_uploaded", ({ photo_id }) => {
                if (this.pendingThumbnail && photo_id) {
                    this.pushEvent("set_thumbnail", { 
                        photo_id: photo_id, 
                        thumbnail: this.pendingThumbnail 
                    })
                    this.pendingThumbnail = null
                }
            })
            
            // Create a hidden optimized file input
            fileInput.addEventListener('change', async (e) => {
                const files = e.target.files
                if (!files || files.length === 0) return
                
                const file = files[0]
                
                // Check if it's an image that needs optimization
                if (file.type.startsWith('image/') && file.type !== 'image/gif') {
                    // Generate thumbnail first (in parallel with optimization)
                    const [thumbnail, optimized] = await Promise.all([
                        generateThumbnail(file, 600),
                        optimizeImage(file, 1200)
                    ])
                    
                    // Store thumbnail for when upload completes
                    this.pendingThumbnail = thumbnail
                    
                    const originalSize = file.size
                    
                    // Only use optimized if it's actually smaller
                    if (optimized.size < originalSize) {
                        // Create a new DataTransfer to replace the files
                        const dt = new DataTransfer()
                        dt.items.add(optimized)
                        fileInput.files = dt.files
                        
                        console.log(`Image optimized: ${Math.round(originalSize/1024)}KB → ${Math.round(optimized.size/1024)}KB`)
                    }
                }
            })
        }
    },
    PhotoGrid: {
        mounted() {
            this.setupPhotoObserver()
        },
        updated() {
            this.setupPhotoObserver()
        },
        setupPhotoObserver() {
            // Find all images that haven't been processed yet
            const images = this.el.querySelectorAll('img.photo-image:not(.processed)')
            
            images.forEach(img => {
                img.classList.add('processed')
                
                // If already loaded, show immediately
                if (img.complete && img.naturalHeight !== 0) {
                    img.classList.add('loaded')
                    this.hideSkeleton(img)
                } else {
                    // Wait for load
                    img.addEventListener('load', () => {
                        img.classList.add('loaded')
                        this.hideSkeleton(img)
                    }, { once: true })
                    
                    img.addEventListener('error', () => {
                        img.classList.add('loaded')
                        this.hideSkeleton(img)
                    }, { once: true })
                }
            })
        },
        hideSkeleton(img) {
            const skeleton = img.parentElement?.querySelector('.photo-skeleton')
            if (skeleton) {
                skeleton.style.display = 'none'
            }
        }
    },
    ModalScrollLock: {
        mounted() {
            // Prevent background scrolling when modal is open
            document.body.style.overflow = 'hidden'
        },
        destroyed() {
            // Restore scrolling when modal closes
            document.body.style.overflow = ''
        }
    },
    UserPhotosApp: {
        mounted() {
            // Get browser UUID and device fingerprint
            this.browserId = getBrowserId()
            this.deviceFingerprint = generateDeviceFingerprint()
            
            // Send to server
            this.pushEvent("set_user_id", { 
                browser_id: this.browserId,
                device_fingerprint: this.deviceFingerprint
            })
            
            // Setup thumbnail generation for uploads
            this.setupThumbnailGeneration()
        },
        
        setupThumbnailGeneration() {
            const form = this.el.querySelector('#board-upload-form')
            if (!form) return
            
            const fileInput = form.querySelector('input[type="file"]')
            if (!fileInput) return
            
            this.pendingThumbnail = null
            
            // Listen for photo_uploaded event
            this.handleEvent("photo_uploaded", ({ photo_id }) => {
                if (this.pendingThumbnail && photo_id) {
                    this.pushEvent("set_thumbnail", {
                        photo_id: photo_id,
                        thumbnail: this.pendingThumbnail
                    })
                    this.pendingThumbnail = null
                }
            })
            
            fileInput.addEventListener('change', async (e) => {
                const files = e.target.files
                if (!files || files.length === 0) return
                
                const file = files[0]
                if (file.type.startsWith('image/') && file.type !== 'image/gif') {
                    // Generate thumbnail and optimized image in parallel
                    const [thumbnail, optimized] = await Promise.all([
                        generateThumbnail(file, 600),
                        optimizeImage(file, 1200)
                    ])
                    
                    this.pendingThumbnail = thumbnail
                    
                    const originalSize = file.size
                    if (optimized.size < originalSize) {
                        const dt = new DataTransfer()
                        dt.items.add(optimized)
                        fileInput.files = dt.files
                    }
                }
            })
        }
    },
    SortablePhotos: {
        mounted() {
            this.draggedItem = null
            this.placeholder = null
            this.initSortable()
        },
        updated() {
            // Re-apply event listeners after DOM updates
            this.cleanupListeners()
            this.initSortable()
        },
        destroyed() {
            this.cleanupListeners()
        },
        cleanupListeners() {
            if (this.listeners) {
                this.listeners.forEach(({ el, event, handler }) => {
                    el.removeEventListener(event, handler)
                })
            }
            this.listeners = []
        },
        initSortable() {
            const grid = this.el
            const hook = this
            this.listeners = []
            
            const addListener = (el, event, handler) => {
                el.addEventListener(event, handler)
                this.listeners.push({ el, event, handler })
            }
            
            const items = () => [...grid.querySelectorAll('.photo-item')]
            
            const getItemAtPoint = (x, y) => {
                const elements = document.elementsFromPoint(x, y)
                return elements.find(el => el.classList.contains('photo-item') && el !== hook.draggedItem)
            }
            
            const saveOrder = () => {
                const newOrder = items().map(i => i.dataset.id)
                hook.pushEvent('reorder-photos', { order: newOrder })
            }
            
            items().forEach(item => {
                // Mouse events
                addListener(item, 'mousedown', (e) => {
                    if (grid.dataset.reordering !== 'true') return
                    if (e.button !== 0) return // Only left click
                    
                    e.preventDefault()
                    hook.startDrag(item, e.clientX, e.clientY)
                })
                
                // Touch events
                addListener(item, 'touchstart', (e) => {
                    if (grid.dataset.reordering !== 'true') return
                    
                    const touch = e.touches[0]
                    hook.startDrag(item, touch.clientX, touch.clientY)
                }, { passive: true })
            })
            
            // Global move/end events
            addListener(document, 'mousemove', (e) => {
                if (!hook.draggedItem) return
                hook.onDrag(e.clientX, e.clientY, getItemAtPoint)
            })
            
            addListener(document, 'touchmove', (e) => {
                if (!hook.draggedItem) return
                const touch = e.touches[0]
                hook.onDrag(touch.clientX, touch.clientY, getItemAtPoint)
            }, { passive: true })
            
            addListener(document, 'mouseup', () => {
                if (hook.draggedItem) {
                    hook.endDrag(saveOrder)
                }
            })
            
            addListener(document, 'touchend', () => {
                if (hook.draggedItem) {
                    hook.endDrag(saveOrder)
                }
            })
        },
        startDrag(item, x, y) {
            this.draggedItem = item
            this.startX = x
            this.startY = y
            this.initialRect = item.getBoundingClientRect()
            
            // Style the dragged item
            item.style.position = 'fixed'
            item.style.zIndex = '1000'
            item.style.width = this.initialRect.width + 'px'
            item.style.height = this.initialRect.height + 'px'
            item.style.left = this.initialRect.left + 'px'
            item.style.top = this.initialRect.top + 'px'
            item.style.pointerEvents = 'none'
            item.style.opacity = '0.9'
            item.style.transform = 'scale(1.05) rotate(2deg)'
            item.style.transition = 'transform 0.1s, opacity 0.1s'
            item.style.boxShadow = '0 10px 30px rgba(0,0,0,0.3)'
            
            // Create placeholder
            this.placeholder = document.createElement('div')
            this.placeholder.className = 'photo-item-placeholder'
            this.placeholder.style.width = this.initialRect.width + 'px'
            this.placeholder.style.height = this.initialRect.height + 'px'
            this.placeholder.style.border = '3px dashed currentColor'
            this.placeholder.style.opacity = '0.4'
            this.placeholder.style.borderRadius = '4px'
            item.parentNode.insertBefore(this.placeholder, item)
        },
        onDrag(x, y, getItemAtPoint) {
            if (!this.draggedItem) return
            
            // Move the dragged item
            const dx = x - this.startX
            const dy = y - this.startY
            this.draggedItem.style.left = (this.initialRect.left + dx) + 'px'
            this.draggedItem.style.top = (this.initialRect.top + dy) + 'px'
            
            // Find item under cursor
            const targetItem = getItemAtPoint(x, y)
            if (targetItem && targetItem !== this.placeholder) {
                const targetRect = targetItem.getBoundingClientRect()
                const midY = targetRect.top + targetRect.height / 2
                
                if (y < midY) {
                    targetItem.parentNode.insertBefore(this.placeholder, targetItem)
                } else {
                    targetItem.parentNode.insertBefore(this.placeholder, targetItem.nextSibling)
                }
            }
        },
        endDrag(saveOrder) {
            if (!this.draggedItem) return
            
            // Reset styles
            this.draggedItem.style.position = ''
            this.draggedItem.style.zIndex = ''
            this.draggedItem.style.width = ''
            this.draggedItem.style.height = ''
            this.draggedItem.style.left = ''
            this.draggedItem.style.top = ''
            this.draggedItem.style.pointerEvents = ''
            this.draggedItem.style.opacity = ''
            this.draggedItem.style.transform = ''
            this.draggedItem.style.transition = ''
            this.draggedItem.style.boxShadow = ''
            
            // Move item to placeholder position
            if (this.placeholder && this.placeholder.parentNode) {
                this.placeholder.parentNode.insertBefore(this.draggedItem, this.placeholder)
                this.placeholder.remove()
            }
            
            this.draggedItem = null
            this.placeholder = null
            
            // Save the new order
            saveOrder()
        }
    },
    
    // Map for Friends app - location sharing (Google Maps)
    FriendsMap: {
        mounted() {
            this.apiKey = document.querySelector('meta[name="google-maps-api-key"]')?.content
            if (!this.apiKey) {
                console.warn('Google Maps API key not found')
                return
            }
            this.loadGoogleMaps().then(() => this.initMap())
        },
        
        async loadGoogleMaps() {
            if (window.google?.maps) return
            
            await new Promise((resolve) => {
                const script = document.createElement('script')
                script.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKey}&callback=__gmapsCallback`
                script.async = true
                window.__gmapsCallback = () => {
                    delete window.__gmapsCallback
                    resolve()
                }
                document.head.appendChild(script)
            })
        },
        
        initMap() {
            const container = this.el.querySelector('.map-container')
            if (!container || !window.google?.maps) return
            
            // Default to Warsaw if no location
            const defaultLat = parseFloat(this.el.dataset.lat) || 52.2297
            const defaultLng = parseFloat(this.el.dataset.lng) || 21.0122
            const defaultZoom = parseInt(this.el.dataset.zoom) || 13
            
            this.map = new google.maps.Map(container, {
                zoom: defaultZoom,
                center: { lat: defaultLat, lng: defaultLng },
                styles: [
                    { elementType: "geometry", stylers: [{ color: "#1a1a2e" }] },
                    { elementType: "labels.text.stroke", stylers: [{ color: "#0f0f1e" }] },
                    { elementType: "labels.text.fill", stylers: [{ color: "#8b92ab" }] },
                    { featureType: "administrative", elementType: "geometry.stroke", stylers: [{ color: "#2d3561" }] },
                    { featureType: "administrative.locality", elementType: "labels.text.fill", stylers: [{ color: "#c4c7d9" }] },
                    { featureType: "poi", elementType: "labels.text", stylers: [{ visibility: "off" }] },
                    { featureType: "poi", elementType: "geometry", stylers: [{ color: "#232844" }] },
                    { featureType: "poi.park", elementType: "geometry", stylers: [{ color: "#1f3a3a" }] },
                    { featureType: "road", elementType: "geometry", stylers: [{ color: "#2a2f4d" }] },
                    { featureType: "road", elementType: "geometry.stroke", stylers: [{ color: "#1f2339" }] },
                    { featureType: "road.highway", elementType: "geometry", stylers: [{ color: "#3a3f5c" }] },
                    { featureType: "transit", stylers: [{ visibility: "off" }] },
                    { featureType: "water", elementType: "geometry", stylers: [{ color: "#0f1929" }] },
                    { featureType: "water", elementType: "labels.text.fill", stylers: [{ color: "#4a6d8c" }] }
                ],
                mapTypeControl: false,
                streetViewControl: false,
                fullscreenControl: true
            })
            
            this.markers = {}
            this.liveMarkers = {}
            this.infoWindow = new google.maps.InfoWindow()
            
            // Load existing places
            const places = JSON.parse(this.el.dataset.places || '[]')
            places.forEach(place => this.addPlaceMarker(place))
            
            // Load live locations
            const liveLocations = JSON.parse(this.el.dataset.liveLocations || '[]')
            liveLocations.forEach(loc => this.addLiveMarker(loc))
            
            // Click to add place
            this.map.addListener('click', (e) => {
                if (this.el.dataset.addingPlace === 'true') {
                    this.pushEvent('map_clicked', { lat: e.latLng.lat(), lng: e.latLng.lng() })
                }
            })
            
            // Handle events from LiveView
            this.handleEvent('add_place_marker', (place) => this.addPlaceMarker(place))
            this.handleEvent('remove_place_marker', ({id}) => this.removePlaceMarker(id))
            this.handleEvent('update_live_locations', (data) => this.updateLiveLocations(data.locations))
            this.handleEvent('center_map', (data) => {
                this.map.setCenter({ lat: data.lat, lng: data.lng })
                this.map.setZoom(data.zoom || 15)
            })
        },
        
        addPlaceMarker(place) {
            if (this.markers[place.id]) {
                this.markers[place.id].setMap(null)
            }
            
            const marker = new google.maps.Marker({
                position: { lat: place.lat, lng: place.lng },
                map: this.map,
                label: { text: place.emoji || '📍', fontSize: '20px' },
                title: place.name
            })
            
            marker.addListener('click', () => {
                this.infoWindow.setContent(`
                    <div style="padding: 8px; min-width: 150px;">
                        <strong style="font-size: 14px;">${place.name}</strong>
                        ${place.description ? `<p style="margin: 8px 0 0; font-size: 12px; opacity: 0.7;">${place.description}</p>` : ''}
                        <p style="margin: 8px 0 0; font-size: 11px; opacity: 0.5; display: flex; align-items: center; gap: 4px;">
                            <span style="width: 8px; height: 8px; background: ${place.user_color}; display: inline-block;"></span>
                            ${place.user_name || 'Anonymous'}
                        </p>
                    </div>
                `)
                this.infoWindow.open(this.map, marker)
            })
            
            this.markers[place.id] = marker
        },
        
        removePlaceMarker(id) {
            if (this.markers[id]) {
                this.markers[id].setMap(null)
                delete this.markers[id]
            }
        },
        
        addLiveMarker(loc) {
            if (this.liveMarkers[loc.user_id]) {
                this.liveMarkers[loc.user_id].setPosition({ lat: loc.lat, lng: loc.lng })
                return
            }
            
            const marker = new google.maps.Marker({
                position: { lat: loc.lat, lng: loc.lng },
                map: this.map,
                icon: {
                    path: google.maps.SymbolPath.CIRCLE,
                    scale: 12,
                    fillColor: loc.user_color || '#ef4444',
                    fillOpacity: 1,
                    strokeColor: '#fff',
                    strokeWeight: 3
                },
                title: loc.user_name || 'Anonymous',
                zIndex: 1000
            })
            
            marker.addListener('click', () => {
                this.infoWindow.setContent(`
                    <div style="padding: 8px;">
                        <strong>${loc.user_name || 'Anonymous'}</strong>
                        <p style="margin: 4px 0 0; font-size: 11px; color: #10B981;">🔴 Live location</p>
                    </div>
                `)
                this.infoWindow.open(this.map, marker)
            })
            
            this.liveMarkers[loc.user_id] = marker
        },
        
        updateLiveLocations(locations) {
            // Remove old markers for users no longer sharing
            const currentIds = locations.map(l => l.user_id)
            Object.keys(this.liveMarkers).forEach(id => {
                if (!currentIds.includes(id)) {
                    this.liveMarkers[id].setMap(null)
                    delete this.liveMarkers[id]
                }
            })
            
            // Add/update markers
            locations.forEach(loc => this.addLiveMarker(loc))
        },
        
        destroyed() {
            // Clean up markers
            Object.values(this.markers).forEach(m => m.setMap(null))
            Object.values(this.liveMarkers).forEach(m => m.setMap(null))
        }
    }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
    hooks: Hooks, 
    params: {_csrf_token: csrfToken},
    // More tolerant reconnection for mobile
    reconnectAfterMs: (tries) => {
        // Reconnect quickly: 100ms, 200ms, 500ms, 1s, 2s, then every 5s
        return [100, 200, 500, 1000, 2000, 5000][tries - 1] || 5000
    },
    // Fall back to long polling if WebSocket fails
    longPollFallbackMs: 2500
})

// Handle location sharing request
window.addEventListener("phx:request_location", () => {
    if ("geolocation" in navigator) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                // Use liveSocket to push event to the LiveView
                liveSocket.execJS(document.body, JSON.stringify([
                    ["push", { event: "location_update", data: {
                        lat: position.coords.latitude,
                        lng: position.coords.longitude
                    }}]
                ]))
            },
            (error) => {
                console.error('Location error:', error)
                alert('Unable to get your location. Please check your browser permissions.')
            },
            { enableHighAccuracy: true, timeout: 10000 }
        )
    } else {
        alert('Geolocation is not supported by your browser')
    }
})

// Show progress bar on live navigation and form submits - but not on initial connect
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
let initialLoad = true
window.addEventListener("phx:page-loading-start", info => {
    // Don't show topbar on initial page load - content is already there
    if (!initialLoad && info.detail.kind === "redirect") {
        topbar.show(200)
    }
})
window.addEventListener("phx:page-loading-stop", _info => {
    initialLoad = false
    topbar.hide()
})

// Handle CSV download from LiveView
window.addEventListener("phx:download_csv", (e) => {
    const {filename, data} = e.detail
    const blob = new Blob([data], {type: 'text/csv;charset=utf-8;'})
    const link = document.createElement('a')
    const url = URL.createObjectURL(blob)
    
    link.setAttribute('href', url)
    link.setAttribute('download', filename)
    link.style.visibility = 'hidden'
    
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    
    URL.revokeObjectURL(url)
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// Handle page visibility changes - prevent aggressive reconnects on mobile
document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
        // Page became visible again - ensure socket is connected
        if (!liveSocket.isConnected()) {
            liveSocket.connect()
        }
    }
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
