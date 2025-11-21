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
    let selectedUser = null
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
    let showStats = false
    let stats = {
        usersOnline: 0,
        totalPins: 0,
        countries: new Set()
    }

    // Duration timer
    let durationInterval

    const emojis = ["📍", "⭐", "❤️", "🎉", "🎯", "🔥", "💡", "🌍", "🚀", "🎨"]

    // Load Google Maps
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

        // Subscribe to LiveView events
        live.handleEvent("pin_created", handlePinCreated)
        live.handleEvent("pin_deleted", handlePinDeleted)
        live.handleEvent("presence_update", handlePresenceUpdate)
        live.handleEvent("cursor_move", handleCursorMove)
        live.handleEvent("chat_message", handleChatMessage)

        // Update durations every second
        durationInterval = setInterval(updateDurations, 1000)

        // Update stats
        updateStats()

        // Listen for clipboard paste events
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

        return () => {
            if (script.parentNode) {
                document.head.removeChild(script)
            }
            document.removeEventListener('paste', handlePaste);
        }
    })

    onDestroy(() => {
        if (durationInterval) {
            clearInterval(durationInterval)
        }
    })

    function updateDurations() {
        // This will trigger a re-render which updates all duration displays
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

        // Add click listener to drop pins
        map.addListener('click', (e) => {
            openPinModal(e.latLng.lat(), e.latLng.lng())
        })

        // Add mouse move listener for cursor tracking
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

        // Render existing users and pins
        renderUsers()
        renderPins()
    }

    function renderUsers() {
        if (!isMapLoaded) return

        // Clear old markers
        userMarkers.forEach(marker => marker.setMap(null))
        userMarkers.clear()

        // Add current user marker
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

        // Add other users
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

        // Clear old pin markers
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
            <div style="padding: 8px; min-width: 200px;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <div style="width: 16px; height: 16px; border-radius: 50%; background: ${user.color};"></div>
                    <strong>${user.name}</strong>
                    ${isCurrentUser ? '<span style="color: #10B981;">(You)</span>' : ''}
                </div>
                <div style="font-size: 13px; color: #666; line-height: 1.6;">
                    <div>${flag} ${user.city}, ${user.country}</div>
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
            <div style="padding: 8px; min-width: 200px; max-width: 300px;">
                <div style="font-size: 24px; margin-bottom: 8px;">${pin.emoji}</div>
                ${pin.image_data ? `<img src="${pin.image_data}" style="width: 100%; max-height: 200px; object-fit: contain; background: #f3f4f6; border-radius: 8px; margin-bottom: 8px;" />` : ''}
                ${pin.message ? `<p style="margin: 8px 0;">${pin.message}</p>` : ''}
                <div style="font-size: 12px; color: #666;">
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 12px; height: 12px; border-radius: 50%; background: ${pin.user_color};"></div>
                        ${pin.user_name}
                    </div>
                    <div>${flag} ${pin.city || 'Unknown'}</div>
                    <div>${time}</div>
                </div>
            </div>
        `
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
        // Auto-scroll chat to bottom
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
        // Check file size (max 3MB)
        if (file.size > 3 * 1024 * 1024) {
            alert('Image must be smaller than 3MB')
            return
        }

        // Check file type
        if (!file.type.startsWith('image/')) {
            alert('Please select an image file')
            return
        }

        const reader = new FileReader()
        reader.onload = (e) => {
            // Only add to pin modal if it's currently open
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

<div class="min-h-screen bg-gray-50 relative">
    <!-- Header -->
    <div class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8">
            <div class="flex items-center justify-between flex-wrap gap-4">
                <div>
                    <h1 class="text-2xl font-bold text-gray-900">🌍 Live World</h1>
                    <p class="text-sm text-gray-500">Real-time global presence map</p>
                </div>
                <div class="flex items-center gap-3 flex-wrap">
                    <button
                        class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
                        on:click={() => showChat = !showChat}
                    >
                        💬 Chat {chatMessages.length > 0 ? `(${chatMessages.length})` : ''}
                    </button>
                    <button
                        class="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 font-medium transition-colors"
                        on:click={() => showStats = !showStats}
                    >
                        📊 Stats
                    </button>
                    {#if currentUser.name}
                        <div class="flex items-center gap-2 px-3 py-2 bg-gray-100 rounded-lg">
                            <div class="w-3 h-3 rounded-full" style="background: {currentUser.color}"></div>
                            <span class="text-sm font-medium">{currentUser.name}</span>
                        </div>
                    {/if}
                </div>
            </div>
        </div>
    </div>

    <!-- Map Container -->
    <div class="relative" style="height: calc(100vh - 100px);">
        <div bind:this={mapElement} class="w-full h-full"></div>

        {#if !googleMapsApiKey}
            <div class="absolute inset-0 flex items-center justify-center bg-gray-100">
                <div class="text-center">
                    <div class="text-6xl mb-4">🗺️</div>
                    <h2 class="text-xl font-semibold text-gray-700 mb-2">Google Maps API Key Required</h2>
                    <p class="text-gray-500">Please configure your Google Maps API key to use this feature.</p>
                </div>
            </div>
        {/if}

        <!-- Stats Panel -->
        {#if showStats}
            <div class="absolute top-4 left-4 bg-white rounded-lg shadow-lg p-4 max-w-xs z-10">
                <h3 class="font-semibold mb-3 flex items-center justify-between">
                    📊 Live Stats
                    <button class="text-gray-400 hover:text-gray-600" on:click={() => showStats = false}>✕</button>
                </h3>
                <div class="space-y-2 text-sm">
                    <div class="flex justify-between items-center">
                        <span class="text-gray-600">👥 Users Online:</span>
                        <span class="font-bold text-green-600">{stats.usersOnline}</span>
                    </div>
                    <div class="flex justify-between items-center">
                        <span class="text-gray-600">📍 Total Pins:</span>
                        <span class="font-bold text-blue-600">{stats.totalPins}</span>
                    </div>
                    <div class="flex justify-between items-center">
                        <span class="text-gray-600">🌍 Countries:</span>
                        <span class="font-bold text-purple-600">{stats.countries.size}</span>
                    </div>
                </div>
            </div>
        {/if}

        <!-- Chat Panel -->
        {#if showChat}
            <div class="absolute top-4 right-4 bg-white rounded-lg shadow-lg w-80 max-h-[500px] flex flex-col z-10">
                <div class="p-4 border-b flex items-center justify-between">
                    <h3 class="font-semibold">💬 Global Chat</h3>
                    <button class="text-gray-400 hover:text-gray-600" on:click={() => showChat = false}>✕</button>
                </div>
                <div id="chat-messages" class="flex-1 overflow-y-auto p-4 space-y-2 min-h-[200px] max-h-[300px]">
                    {#if chatMessages.length === 0}
                        <p class="text-gray-400 text-sm text-center py-8">No messages yet. Start the conversation!</p>
                    {/if}
                    {#each chatMessages as msg}
                        <div class="bg-gray-50 rounded-lg p-2">
                            <div class="flex items-center gap-2 mb-1">
                                <div class="w-2 h-2 rounded-full" style="background: {msg.color}"></div>
                                <span class="text-xs font-semibold">{msg.user_name}</span>
                                <span class="text-xs text-gray-400">{new Date(msg.timestamp * 1000).toLocaleTimeString()}</span>
                            </div>
                            <p class="text-sm">{msg.message}</p>
                        </div>
                    {/each}
                </div>
                <form on:submit|preventDefault={sendChatMessage} class="p-4 border-t">
                    <div class="flex gap-2">
                        <input
                            type="text"
                            bind:value={newChatMessage}
                            placeholder="Type a message..."
                            class="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                            maxlength="200"
                        />
                        <button
                            type="submit"
                            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium"
                        >
                            Send
                        </button>
                    </div>
                </form>
            </div>
        {/if}

        <!-- Instructions (moved to bottom left) -->
        <div class="absolute bottom-4 left-4 bg-white rounded-lg shadow-lg p-4 max-w-sm z-10">
            <h3 class="font-semibold mb-2">How to use:</h3>
            <ul class="text-sm space-y-1 text-gray-600">
                <li>👆 <strong>Click</strong> on the map to drop a pin</li>
                <li>🔴 <strong>Colored dots</strong> are online users</li>
                <li>🖱️ <strong>Hover</strong> to see live cursors</li>
                <li>💬 <strong>Chat</strong> with everyone in real-time</li>
                <li>📊 <strong>Stats</strong> show live activity</li>
            </ul>
        </div>
    </div>

    <!-- Pin Modal -->
    {#if showPinModal}
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" on:click={() => showPinModal = false}>
            <div class="bg-white rounded-lg shadow-xl p-6 max-w-md w-full mx-4" on:click|stopPropagation>
                <h3 class="text-lg font-semibold mb-4">Drop a Pin 📍</h3>

                <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Choose an emoji</label>
                    <div class="flex gap-2 flex-wrap">
                        {#each emojis as emoji}
                            <button
                                class="text-2xl p-2 rounded hover:bg-gray-100 {newPinEmoji === emoji ? 'bg-blue-100 ring-2 ring-blue-500' : ''}"
                                on:click={() => newPinEmoji = emoji}
                            >
                                {emoji}
                            </button>
                        {/each}
                    </div>
                </div>

                <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Message (optional)</label>
                    <textarea
                        bind:value={newPinMessage}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                        rows="3"
                        placeholder="Leave a message..."
                        maxlength="200"
                    ></textarea>
                </div>

                <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Photo (optional, max 3MB)</label>
                    {#if newPinImagePreview}
                        <div class="relative">
                            <img src={newPinImagePreview} alt="Preview" class="w-full h-40 object-contain bg-gray-100 rounded-lg" />
                            <button
                                class="absolute top-2 right-2 bg-red-500 text-white rounded-full w-8 h-8 flex items-center justify-center hover:bg-red-600"
                                on:click={removeImage}
                                type="button"
                            >
                                ✕
                            </button>
                        </div>
                    {:else}
                        <input
                            type="file"
                            accept="image/*"
                            on:change={handleImageSelect}
                            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                        />
                    {/if}
                </div>

                <div class="flex gap-3">
                    <button
                        class="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium"
                        on:click={dropPin}
                    >
                        Drop Pin
                    </button>
                    <button
                        class="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50"
                        on:click={() => showPinModal = false}
                    >
                        Cancel
                    </button>
                </div>
            </div>
        </div>
    {/if}
</div>
