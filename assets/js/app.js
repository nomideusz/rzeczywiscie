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
            const deviceId = generateDeviceFingerprint()
            
            // Load user name from localStorage (keyed by device ID for consistency)
            const storedName = localStorage.getItem(`friends_user_name_${deviceId}`)
            
            // Send device ID and stored name to server
            this.pushEvent("set_user_id", { 
                user_id: deviceId,
                user_name: storedName
            })
            
            // Listen for save_user_name event from server
            this.handleEvent("save_user_name", ({ name }) => {
                if (name) {
                    localStorage.setItem(`friends_user_name_${deviceId}`, name)
                } else {
                    localStorage.removeItem(`friends_user_name_${deviceId}`)
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
