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
function generateDeviceFingerprint() {
    const components = [
        screen.width + 'x' + screen.height,          // Screen resolution - same across browsers
        screen.colorDepth,                           // Screen color depth - same across browsers
        navigator.hardwareConcurrency || 'unknown',  // CPU cores - same across browsers
        new Date().getTimezoneOffset(),              // Timezone - same across browsers
        navigator.maxTouchPoints || 0                // Touch capability - same across browsers
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
            // Generate device fingerprint and send to server
            const deviceId = generateDeviceFingerprint()
            this.pushEvent("set_user_id", { user_id: deviceId })
        }
    },
    FriendsApp: {
        mounted() {
            // Generate device fingerprint
            this.deviceId = generateDeviceFingerprint()
            
            // Load linked user ID from localStorage (if previously linked)
            const linkedUserId = localStorage.getItem(`friends_linked_user_id_${this.deviceId}`)
            
            // Load user name from localStorage (keyed by actual user ID for consistency)
            const effectiveUserId = linkedUserId || this.deviceId
            const storedName = localStorage.getItem(`friends_user_name_${effectiveUserId}`)
            
            // Send device ID, linked ID, and stored name to server
            this.pushEvent("set_user_id", { 
                user_id: this.deviceId,
                linked_user_id: linkedUserId,
                user_name: storedName
            })
            
            // Listen for save_user_name event from server
            this.handleEvent("save_user_name", ({ name }) => {
                const effectiveId = localStorage.getItem(`friends_linked_user_id_${this.deviceId}`) || this.deviceId
                if (name) {
                    localStorage.setItem(`friends_user_name_${effectiveId}`, name)
                } else {
                    localStorage.removeItem(`friends_user_name_${effectiveId}`)
                }
            })
            
            // Listen for linked_user_id event from server (when device is linked/unlinked)
            this.handleEvent("linked_user_id", ({ user_id, is_linked }) => {
                if (is_linked && user_id) {
                    // Store the linked user ID
                    localStorage.setItem(`friends_linked_user_id_${this.deviceId}`, user_id)
                    console.log(`Device linked to account: ${user_id}`)
                } else {
                    // Remove linked user ID (unlinked)
                    localStorage.removeItem(`friends_linked_user_id_${this.deviceId}`)
                    console.log('Device unlinked')
                }
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
            
            // Create a hidden optimized file input
            fileInput.addEventListener('change', async (e) => {
                const files = e.target.files
                if (!files || files.length === 0) return
                
                const file = files[0]
                
                // Check if it's an image that needs optimization
                if (file.type.startsWith('image/') && file.type !== 'image/gif') {
                    // Show that we're optimizing
                    const originalSize = file.size
                    
                    const optimized = await optimizeImage(file, 1200)
                    
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
            // Generate device fingerprint
            this.deviceId = generateDeviceFingerprint()
            
            // Load linked user ID from localStorage
            const linkedUserId = localStorage.getItem(`friends_linked_user_id_${this.deviceId}`)
            const effectiveUserId = linkedUserId || this.deviceId
            const storedName = localStorage.getItem(`friends_user_name_${effectiveUserId}`)
            
            // Send to server
            this.pushEvent("set_user_id", { 
                user_id: this.deviceId,
                user_name: storedName
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
    }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

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

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
