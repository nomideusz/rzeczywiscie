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
