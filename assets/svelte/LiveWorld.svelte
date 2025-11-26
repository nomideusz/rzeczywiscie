<script>
    import { onMount, onDestroy } from 'svelte'

    export let currentUser = {}
    export let users = []
    export let pins = []
    export let googleMapsApiKey = ""
    export let live

    let map
    let mapElement
    let userMarkers = new Map()
    let pinMarkers = new Map()
    let cursorMarkers = new Map()
    let showPinModal = false
    let newPinMessage = ""
    let newPinEmoji = "📍"
    let newPinImage = null
    let newPinImagePreview = null
    let pendingPinPosition = null
    let isMapLoaded = false

    // Chat state
    let showChat = false
    let chatMessages = []
    let newChatMessage = ""

    // Stats
    let showStats = true
    let stats = {
        usersOnline: 0,
        totalPins: 0,
        countries: new Set()
    }

    // Duration timer
    let durationInterval

    // Lightbox
    let lightboxImage = null

    const emojis = ["📍", "⭐", "❤️", "🎉", "🎯", "🔥", "💡", "🌍", "🚀", "🎨"]

    onMount(() => {
        if (!googleMapsApiKey) {
            console.warn("Google Maps API key not provided. Map will not load.")
            return
        }

        const script = document.createElement('script')
        script.src = `https://maps.googleapis.com/maps/api/js?key=${googleMapsApiKey}&callback=initMap`
        script.async = true
        script.defer = true

        window.initMap = () => {
            initializeMap()
        }

        document.head.appendChild(script)

        live.handleEvent("pin_created", handlePinCreated)
        live.handleEvent("pin_deleted", handlePinDeleted)
        live.handleEvent("presence_update", handlePresenceUpdate)
        live.handleEvent("cursor_move", handleCursorMove)
        live.handleEvent("chat_message", handleChatMessage)

        durationInterval = setInterval(updateDurations, 1000)
        updateStats()

        const handlePaste = (e) => {
            const items = e.clipboardData?.items;
            if (!items) return;

            for (let i = 0; i < items.length; i++) {
                if (items[i].type.startsWith('image/')) {
                    e.preventDefault();
                    const file = items[i].getAsFile();
                    if (file) {
                        processImageFile(file);
                    }
                    break;
                }
            }
        };

        document.addEventListener('paste', handlePaste);

        const handleKeydown = (e) => {
            if (e.key === 'Escape' && lightboxImage) {
                lightboxImage = null;
            }
        };

        document.addEventListener('keydown', handleKeydown);

        window.openLightbox = (imageSrc) => {
            lightboxImage = imageSrc;
        };

        return () => {
            if (script.parentNode) {
                document.head.removeChild(script)
            }
            document.removeEventListener('paste', handlePaste);
            document.removeEventListener('keydown', handleKeydown);
            delete window.openLightbox;
        }
    })

    onDestroy(() => {
        if (durationInterval) {
            clearInterval(durationInterval)
        }
    })

    function updateDurations() {
        users = users
    }

    function updateStats() {
        stats.usersOnline = users.length
        stats.totalPins = pins.length
        stats.countries = new Set(users.map(u => u.country).filter(Boolean))
    }

    function initializeMap() {
        const center = currentUser.lat && currentUser.lng
            ? { lat: currentUser.lat, lng: currentUser.lng }
            : { lat: 20, lng: 0 }

        map = new google.maps.Map(mapElement, {
            zoom: currentUser.lat ? 5 : 2,
            center: center,
            styles: [
                {
                    featureType: "poi",
                    elementType: "labels",
                    stylers: [{ visibility: "off" }]
                }
            ],
            mapTypeControl: true,
            streetViewControl: false,
            fullscreenControl: true
        })

        isMapLoaded = true

        map.addListener('click', (e) => {
            openPinModal(e.latLng.lat(), e.latLng.lng())
        })

        let throttleTimeout
        map.addListener('mousemove', (e) => {
            if (!throttleTimeout) {
                throttleTimeout = setTimeout(() => {
                    live.pushEvent("cursor_move", {
                        lat: e.latLng.lat(),
                        lng: e.latLng.lng()
                    }, () => {})
                    throttleTimeout = null
                }, 100)
            }
        })

        renderUsers()
        renderPins()
    }

    function renderUsers() {
        if (!isMapLoaded) return

        userMarkers.forEach(marker => marker.setMap(null))
        userMarkers.clear()

        if (currentUser.lat && currentUser.lng) {
            const marker = new google.maps.Marker({
                position: { lat: currentUser.lat, lng: currentUser.lng },
                map: map,
                title: `${currentUser.name} (You)`,
                icon: {
                    path: google.maps.SymbolPath.CIRCLE,
                    scale: 12,
                    fillColor: currentUser.color,
                    fillOpacity: 1,
                    strokeColor: '#ffffff',
                    strokeWeight: 3
                },
                zIndex: 1000
            })

            const infoWindow = new google.maps.InfoWindow({
                content: getUserInfoHTML(currentUser, true)
            })

            marker.addListener('click', () => {
                infoWindow.setContent(getUserInfoHTML(currentUser, true))
                infoWindow.open(map, marker)
            })

            userMarkers.set(currentUser.id, marker)
        }

        users.filter(u => u.id !== currentUser.id).forEach(user => {
            if (user.lat && user.lng) {
                const marker = new google.maps.Marker({
                    position: { lat: user.lat, lng: user.lng },
                    map: map,
                    title: user.name,
                    icon: {
                        path: google.maps.SymbolPath.CIRCLE,
                        scale: 10,
                        fillColor: user.color,
                        fillOpacity: 0.8,
                        strokeColor: '#ffffff',
                        strokeWeight: 2
                    },
                    zIndex: 900
                })

                const infoWindow = new google.maps.InfoWindow({
                    content: getUserInfoHTML(user, false)
                })

                marker.addListener('click', () => {
                    infoWindow.setContent(getUserInfoHTML(user, false))
                    infoWindow.open(map, marker)
                })

                userMarkers.set(user.id, marker)
            }
        })
    }

    function renderPins() {
        if (!isMapLoaded) return

        pinMarkers.forEach(marker => marker.setMap(null))
        pinMarkers.clear()

        pins.forEach(pin => {
            const marker = new google.maps.Marker({
                position: { lat: pin.lat, lng: pin.lng },
                map: map,
                label: {
                    text: pin.emoji || "📍",
                    fontSize: "20px"
                },
                title: pin.message || pin.user_name,
                zIndex: 500
            })

            const infoWindow = new google.maps.InfoWindow({
                content: getPinInfoHTML(pin)
            })

            marker.addListener('click', () => {
                infoWindow.open(map, marker)
            })

            pinMarkers.set(pin.id, marker)
        })
    }

    function getUserInfoHTML(user, isCurrentUser) {
        const flag = user.country_code ? getFlagEmoji(user.country_code) : "🌍"
        const localTime = user.timezone ? getLocalTime(user.timezone) : "Unknown"
        const duration = getDuration(user.joined_at)

        return `
            <div style="padding: 12px; min-width: 220px; font-family: system-ui, sans-serif;">
                <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 12px; padding-bottom: 12px; border-bottom: 2px solid #1a1a1a;">
                    <div style="width: 20px; height: 20px; background: ${user.color};"></div>
                    <strong style="font-size: 14px; text-transform: uppercase; letter-spacing: 0.5px;">${user.name}</strong>
                    ${isCurrentUser ? '<span style="color: #10B981; font-size: 10px; font-weight: bold;">(YOU)</span>' : ''}
                </div>
                <div style="font-size: 12px; color: #333; line-height: 1.8;">
                    <div style="font-weight: 600;">${flag} ${user.city}, ${user.country}</div>
                    <div>🕐 ${localTime}</div>
                    <div>⏱️ Online: ${duration}</div>
                </div>
            </div>
        `
    }

    function getPinInfoHTML(pin) {
        const flag = pin.country ? pin.country : "🌍"
        const time = new Date(pin.created_at * 1000).toLocaleString()

        return `
            <div style="padding: 12px; min-width: 220px; max-width: 300px; font-family: system-ui, sans-serif;">
                <div style="font-size: 28px; margin-bottom: 12px;">${pin.emoji}</div>
                ${pin.image_data ? `<img src="${pin.image_data}" onclick="window.openLightbox('${pin.image_data}')" style="width: 100%; max-height: 200px; object-fit: contain; background: #f3f4f6; margin-bottom: 12px; cursor: pointer;" />` : ''}
                ${pin.message ? `<p style="margin: 0 0 12px 0; font-size: 14px;">${pin.message}</p>` : ''}
                <div style="font-size: 11px; color: #666; padding-top: 12px; border-top: 1px solid #ddd;">
                    <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 4px;">
                        <div style="width: 12px; height: 12px; background: ${pin.user_color};"></div>
                        <span style="font-weight: 600;">${pin.user_name}</span>
                    </div>
                    <div>${flag} ${pin.city || 'Unknown'}</div>
                    <div>${time}</div>
                </div>
            </div>
        `
    }

    function closeLightbox() {
        lightboxImage = null;
    }

    function handleCursorMove(data) {
        if (!isMapLoaded || data.user_id === currentUser.id) return

        if (cursorMarkers.has(data.user_id)) {
            const marker = cursorMarkers.get(data.user_id)
            marker.setPosition({ lat: data.lat, lng: data.lng })
        } else {
            const marker = new google.maps.Marker({
                position: { lat: data.lat, lng: data.lng },
                map: map,
                icon: {
                    path: "M 0,0 L 0,20 L 5,15 L 10,25 L 15,22 L 10,12 L 18,12 Z",
                    fillColor: data.color,
                    fillOpacity: 0.7,
                    strokeColor: '#ffffff',
                    strokeWeight: 1,
                    scale: 0.8,
                    anchor: new google.maps.Point(0, 0)
                },
                title: data.user_name,
                zIndex: 2000
            })

            cursorMarkers.set(data.user_id, marker)

            setTimeout(() => {
                const m = cursorMarkers.get(data.user_id)
                if (m) {
                    m.setMap(null)
                    cursorMarkers.delete(data.user_id)
                }
            }, 2000)
        }
    }

    function handlePinCreated(pin) {
        pins = [pin, ...pins]
        renderPins()
        updateStats()
    }

    function handlePinDeleted(data) {
        pins = pins.filter(p => p.id !== data.id)
        renderPins()
        updateStats()
    }

    function handlePresenceUpdate(data) {
        users = data.users
        renderUsers()
        updateStats()
    }

    function handleChatMessage(data) {
        chatMessages = [...chatMessages, data]
        setTimeout(() => {
            const chatContainer = document.getElementById('chat-messages')
            if (chatContainer) {
                chatContainer.scrollTop = chatContainer.scrollHeight
            }
        }, 10)
    }

    function openPinModal(lat, lng) {
        pendingPinPosition = { lat, lng }
        showPinModal = true
    }

    function dropPin() {
        if (!pendingPinPosition) return

        live.pushEvent("drop_pin", {
            lat: pendingPinPosition.lat,
            lng: pendingPinPosition.lng,
            message: newPinMessage,
            emoji: newPinEmoji,
            image_data: newPinImage
        }, () => {})

        showPinModal = false
        newPinMessage = ""
        newPinEmoji = "📍"
        newPinImage = null
        newPinImagePreview = null
        pendingPinPosition = null
    }

    function handleImageSelect(event) {
        const file = event.target.files[0]
        if (file) {
            processImageFile(file)
        }
    }

    function processImageFile(file) {
        if (file.size > 3 * 1024 * 1024) {
            alert('Image must be smaller than 3MB')
            return
        }

        if (!file.type.startsWith('image/')) {
            alert('Please select an image file')
            return
        }

        const reader = new FileReader()
        reader.onload = (e) => {
            if (showPinModal) {
                newPinImage = e.target.result
                newPinImagePreview = e.target.result
            }
        }
        reader.readAsDataURL(file)
    }

    function removeImage() {
        newPinImage = null
        newPinImagePreview = null
    }

    function sendChatMessage() {
        if (!newChatMessage.trim()) return

        live.pushEvent("send_chat", {
            message: newChatMessage
        }, () => {})

        newChatMessage = ""
    }

    function getFlagEmoji(countryCode) {
        const offset = 127397
        return countryCode
            .toUpperCase()
            .split('')
            .map(char => String.fromCodePoint(char.charCodeAt(0) + offset))
            .join('')
    }

    function getLocalTime(timezone) {
        try {
            return new Date().toLocaleTimeString('en-US', { timeZone: timezone })
        } catch (e) {
            return "Unknown"
        }
    }

    function getDuration(startTime) {
        const seconds = Math.floor(Date.now() / 1000 - startTime)
        if (seconds < 60) return `${seconds}s`
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60) return `${minutes}m`
        const hours = Math.floor(minutes / 60)
        return `${hours}h ${minutes % 60}m`
    }

    $: if (isMapLoaded) {
        renderUsers()
    }

    $: if (isMapLoaded) {
        renderPins()
    }

    $: {
        users
        updateStats()
    }
</script>

<div class="min-h-screen bg-base-200 relative">
    <!-- Header -->
    <div class="bg-base-100 border-b-4 border-base-content relative z-20">
        <div class="container mx-auto px-4 py-4">
            <div class="flex items-center justify-between flex-wrap gap-4">
                <div>
                    <h1 class="text-xl md:text-2xl font-black uppercase tracking-tight">Live World</h1>
                    <p class="text-xs font-bold uppercase tracking-wide opacity-60">Real-time global presence</p>
                </div>
                <div class="flex items-center gap-2">
                    <button
                        class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content transition-colors cursor-pointer {showChat ? 'bg-base-content text-base-100' : 'hover:bg-base-content hover:text-base-100'}"
                        onclick={() => showChat = !showChat}
                    >
                        💬 Chat {chatMessages.length > 0 ? `(${chatMessages.length})` : ''}
                    </button>
                    <button
                        class="px-3 py-2 text-xs font-bold uppercase tracking-wide border-2 border-base-content transition-colors cursor-pointer {showStats ? 'bg-base-content text-base-100' : 'hover:bg-base-content hover:text-base-100'}"
                        onclick={() => showStats = !showStats}
                    >
                        📊 Stats
                    </button>
                    {#if currentUser.name}
                        <div class="flex items-center gap-2 px-3 py-2 border-2 border-base-content">
                            <div class="w-3 h-3" style="background: {currentUser.color}"></div>
                            <span class="text-xs font-bold uppercase">{currentUser.name}</span>
                        </div>
                    {/if}
                </div>
            </div>
        </div>
    </div>

    <!-- Map Container -->
    <div class="relative" style="height: calc(100vh - 80px);">
        <div bind:this={mapElement} class="w-full h-full"></div>

        {#if !googleMapsApiKey}
            <div class="absolute inset-0 flex items-center justify-center bg-base-200">
                <div class="bg-base-100 border-2 border-base-content p-8 text-center">
                    <div class="text-5xl mb-4">🗺️</div>
                    <h2 class="text-lg font-black uppercase tracking-wide mb-2">API Key Required</h2>
                    <p class="text-xs opacity-60">Configure your Google Maps API key to use this feature.</p>
                </div>
            </div>
        {/if}

        <!-- Stats Panel -->
        {#if showStats}
            <div class="absolute top-4 left-4 bg-base-100 border-2 border-base-content z-10 min-w-[200px]">
                <div class="px-4 py-2 border-b-2 border-base-content bg-base-200 flex items-center justify-between">
                    <span class="text-xs font-bold uppercase tracking-wide">Live Stats</span>
                    <button class="text-xs opacity-50 hover:opacity-100 cursor-pointer" onclick={() => showStats = false}>✕</button>
                </div>
                <div class="p-4 space-y-3">
                    <div class="flex justify-between items-center">
                        <span class="text-xs font-bold uppercase tracking-wide opacity-60">Online</span>
                        <span class="text-lg font-black text-success">{stats.usersOnline}</span>
                    </div>
                    <div class="flex justify-between items-center">
                        <span class="text-xs font-bold uppercase tracking-wide opacity-60">Pins</span>
                        <span class="text-lg font-black text-primary">{stats.totalPins}</span>
                    </div>
                    <div class="flex justify-between items-center">
                        <span class="text-xs font-bold uppercase tracking-wide opacity-60">Countries</span>
                        <span class="text-lg font-black text-secondary">{stats.countries.size}</span>
                    </div>
                </div>
            </div>
        {/if}

        <!-- Chat Panel -->
        {#if showChat}
            <div class="absolute top-4 right-4 bg-base-100 border-2 border-base-content w-80 max-h-[500px] flex flex-col z-10">
                <div class="px-4 py-2 border-b-2 border-base-content bg-base-200 flex items-center justify-between">
                    <span class="text-xs font-bold uppercase tracking-wide">Global Chat</span>
                    <button class="text-xs opacity-50 hover:opacity-100 cursor-pointer" onclick={() => showChat = false}>✕</button>
                </div>
                <div id="chat-messages" class="flex-1 overflow-y-auto p-4 space-y-2 min-h-[200px] max-h-[300px]">
                    {#if chatMessages.length === 0}
                        <p class="text-xs text-center py-8 opacity-40">No messages yet</p>
                    {/if}
                    {#each chatMessages as msg}
                        <div class="border border-base-content/20 p-2">
                            <div class="flex items-center gap-2 mb-1">
                                <div class="w-2 h-2" style="background: {msg.color}"></div>
                                <span class="text-[10px] font-bold uppercase">{msg.user_name}</span>
                                <span class="text-[10px] opacity-40">{new Date(msg.timestamp * 1000).toLocaleTimeString()}</span>
                            </div>
                            <p class="text-xs">{msg.message}</p>
                        </div>
                    {/each}
                </div>
                <form onsubmit={(e) => { e.preventDefault(); sendChatMessage(); }} class="p-3 border-t-2 border-base-content">
                    <div class="flex gap-2">
                        <input
                            type="text"
                            bind:value={newChatMessage}
                            placeholder="Type a message..."
                            class="flex-1 px-3 py-2 text-xs border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                            maxlength="200"
                        />
                        <button
                            type="submit"
                            class="px-4 py-2 text-xs font-bold uppercase bg-base-content text-base-100 cursor-pointer"
                        >
                            Send
                        </button>
                    </div>
                </form>
            </div>
        {/if}

        <!-- Instructions -->
        <div class="absolute bottom-4 left-4 bg-base-100 border-2 border-base-content p-4 max-w-xs z-10">
            <div class="text-xs font-bold uppercase tracking-wide mb-2 opacity-60">How to use</div>
            <ul class="text-xs space-y-1 opacity-80">
                <li>👆 Click map to drop a pin</li>
                <li>🔴 Colored dots = online users</li>
                <li>🖱️ Hover to see live cursors</li>
                <li>💬 Chat with everyone in real-time</li>
            </ul>
        </div>
    </div>

    <!-- Pin Modal -->
    {#if showPinModal}
        <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onclick={() => showPinModal = false}>
            <div class="bg-base-100 border-2 border-base-content max-w-md w-full" onclick={(e) => e.stopPropagation()}>
                <div class="px-4 py-3 border-b-2 border-base-content bg-base-200">
                    <h3 class="text-sm font-bold uppercase tracking-wide">Drop a Pin</h3>
                </div>
                
                <div class="p-4 space-y-4">
                    <div>
                        <label class="block text-xs font-bold uppercase tracking-wide opacity-60 mb-2">Emoji</label>
                        <div class="flex gap-2 flex-wrap">
                            {#each emojis as emoji}
                                <button
                                    class="text-2xl p-2 border-2 transition-colors cursor-pointer {newPinEmoji === emoji ? 'border-base-content bg-base-200' : 'border-transparent hover:border-base-content/30'}"
                                    onclick={() => newPinEmoji = emoji}
                                >
                                    {emoji}
                                </button>
                            {/each}
                        </div>
                    </div>

                    <div>
                        <label class="block text-xs font-bold uppercase tracking-wide opacity-60 mb-2">Message (optional)</label>
                        <textarea
                            bind:value={newPinMessage}
                            class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                            rows="3"
                            placeholder="Leave a message..."
                            maxlength="200"
                        ></textarea>
                    </div>

                    <div>
                        <label class="block text-xs font-bold uppercase tracking-wide opacity-60 mb-2">Photo (optional, max 3MB)</label>
                        {#if newPinImagePreview}
                            <div class="relative">
                                <img src={newPinImagePreview} alt="Preview" class="w-full h-40 object-contain bg-base-200 border-2 border-base-content" />
                                <button
                                    class="absolute top-2 right-2 w-8 h-8 bg-error text-error-content font-bold cursor-pointer"
                                    onclick={removeImage}
                                    type="button"
                                >
                                    ✕
                                </button>
                            </div>
                        {:else}
                            <input
                                type="file"
                                accept="image/*"
                                onchange={handleImageSelect}
                                class="w-full px-3 py-2 text-xs border-2 border-base-content bg-base-100"
                            />
                        {/if}
                    </div>
                </div>

                <div class="flex gap-2 p-4 border-t-2 border-base-content">
                    <button
                        class="flex-1 px-4 py-3 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100 cursor-pointer"
                        onclick={dropPin}
                    >
                        Drop Pin
                    </button>
                    <button
                        class="px-4 py-3 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-200 cursor-pointer"
                        onclick={() => showPinModal = false}
                    >
                        Cancel
                    </button>
                </div>
            </div>
        </div>
    {/if}

    <!-- Image Lightbox -->
    {#if lightboxImage}
        <div
            class="fixed inset-0 bg-black/90 flex items-center justify-center z-[9999] p-4"
            onclick={closeLightbox}
            role="dialog"
            aria-modal="true"
        >
            <button
                class="absolute top-4 right-4 w-12 h-12 bg-base-100 text-base-content text-2xl font-bold hover:bg-base-200 cursor-pointer"
                onclick={closeLightbox}
                aria-label="Close"
            >
                ×
            </button>
            <img
                src={lightboxImage}
                alt="Enlarged view"
                class="max-w-full max-h-full object-contain"
                onclick={(e) => e.stopPropagation()}
            />
        </div>
    {/if}
</div>
