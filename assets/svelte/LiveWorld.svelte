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

    // UI state
    let showUsers = true
    let showChat = false
    let chatMessages = []
    let newChatMessage = ""
    let lightboxImage = null
    let durationInterval

    const emojis = ["📍", "⭐", "❤️", "🎉", "🎯", "🔥", "💡", "🏠", "🚀", "🎨"]

    $: onlineCount = users.length
    $: pinCount = pins.length
    $: countriesCount = new Set(users.map(u => u.country).filter(Boolean)).size

    onMount(() => {
        if (!googleMapsApiKey) {
            console.warn("Google Maps API key not provided.")
            return
        }

        const script = document.createElement('script')
        script.src = `https://maps.googleapis.com/maps/api/js?key=${googleMapsApiKey}&callback=initMap`
        script.async = true
        script.defer = true

        window.initMap = () => initializeMap()
        document.head.appendChild(script)

        live.handleEvent("pin_created", handlePinCreated)
        live.handleEvent("pin_deleted", handlePinDeleted)
        live.handleEvent("presence_update", handlePresenceUpdate)
        live.handleEvent("cursor_move", handleCursorMove)
        live.handleEvent("chat_message", handleChatMessage)

        durationInterval = setInterval(() => users = users, 1000)

        const handlePaste = (e) => {
            if (!showPinModal) return
            const items = e.clipboardData?.items
            if (!items) return
            for (let i = 0; i < items.length; i++) {
                if (items[i].type.startsWith('image/')) {
                    e.preventDefault()
                    processImageFile(items[i].getAsFile())
                    break
                }
            }
        }

        const handleKeydown = (e) => {
            if (e.key === 'Escape') {
                if (lightboxImage) lightboxImage = null
                if (showPinModal) showPinModal = false
            }
        }

        document.addEventListener('paste', handlePaste)
        document.addEventListener('keydown', handleKeydown)
        window.openLightbox = (src) => lightboxImage = src

        return () => {
            if (script.parentNode) document.head.removeChild(script)
            document.removeEventListener('paste', handlePaste)
            document.removeEventListener('keydown', handleKeydown)
            delete window.openLightbox
        }
    })

    onDestroy(() => {
        if (durationInterval) clearInterval(durationInterval)
    })

    function initializeMap() {
        const center = currentUser.lat && currentUser.lng
            ? { lat: currentUser.lat, lng: currentUser.lng }
            : { lat: 20, lng: 0 }

        map = new google.maps.Map(mapElement, {
            zoom: currentUser.lat ? 5 : 2,
            center: center,
            styles: [{ featureType: "poi", elementType: "labels", stylers: [{ visibility: "off" }] }],
            mapTypeControl: true,
            mapTypeControlOptions: {
                position: google.maps.ControlPosition.TOP_RIGHT
            },
            streetViewControl: false,
            fullscreenControl: true,
            fullscreenControlOptions: {
                position: google.maps.ControlPosition.RIGHT_BOTTOM
            }
        })

        isMapLoaded = true

        map.addListener('click', (e) => openPinModal(e.latLng.lat(), e.latLng.lng()))

        let throttle
        map.addListener('mousemove', (e) => {
            if (!throttle) {
                throttle = setTimeout(() => {
                    live.pushEvent("cursor_move", { lat: e.latLng.lat(), lng: e.latLng.lng() }, () => {})
                    throttle = null
                }, 100)
            }
        })

        renderUsers()
        renderPins()
    }

    function renderUsers() {
        if (!isMapLoaded) return

        userMarkers.forEach(m => m.setMap(null))
        userMarkers.clear()

        if (currentUser.lat && currentUser.lng) {
            const marker = new google.maps.Marker({
                position: { lat: currentUser.lat, lng: currentUser.lng },
                map,
                title: `${currentUser.name} (You)`,
                icon: {
                    path: google.maps.SymbolPath.CIRCLE,
                    scale: 14,
                    fillColor: currentUser.color,
                    fillOpacity: 1,
                    strokeColor: '#fff',
                    strokeWeight: 3
                },
                zIndex: 1000
            })

            const info = new google.maps.InfoWindow({ content: getUserInfoHTML(currentUser, true) })
            marker.addListener('click', () => {
                info.setContent(getUserInfoHTML(currentUser, true))
                info.open(map, marker)
            })
            userMarkers.set(currentUser.id, marker)
        }

        users.filter(u => u.id !== currentUser.id).forEach(user => {
            if (!user.lat || !user.lng) return
            const marker = new google.maps.Marker({
                position: { lat: user.lat, lng: user.lng },
                map,
                title: user.name,
                icon: {
                    path: google.maps.SymbolPath.CIRCLE,
                    scale: 10,
                    fillColor: user.color,
                    fillOpacity: 0.9,
                    strokeColor: '#fff',
                    strokeWeight: 2
                },
                zIndex: 900
            })

            const info = new google.maps.InfoWindow({ content: getUserInfoHTML(user, false) })
            marker.addListener('click', () => {
                info.setContent(getUserInfoHTML(user, false))
                info.open(map, marker)
            })
            userMarkers.set(user.id, marker)
        })
    }

    function renderPins() {
        if (!isMapLoaded) return

        pinMarkers.forEach(m => m.setMap(null))
        pinMarkers.clear()

        pins.forEach(pin => {
            const marker = new google.maps.Marker({
                position: { lat: pin.lat, lng: pin.lng },
                map,
                label: { text: pin.emoji || "📍", fontSize: "20px" },
                title: pin.message || pin.user_name,
                zIndex: 500
            })

            const info = new google.maps.InfoWindow({ content: getPinInfoHTML(pin) })
            marker.addListener('click', () => info.open(map, marker))
            pinMarkers.set(pin.id, marker)
        })
    }

    function getUserInfoHTML(user, isYou) {
        const flag = user.country_code ? getFlagEmoji(user.country_code) : "🌍"
        const localTime = user.timezone ? getLocalTime(user.timezone) : "—"
        const duration = getDuration(user.joined_at)

        return `
            <div style="padding: 12px; min-width: 200px; font-family: system-ui;">
                <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 2px solid #1a1a1a;">
                    <div style="width: 18px; height: 18px; background: ${user.color};"></div>
                    <strong style="font-size: 14px; text-transform: uppercase;">${user.name}</strong>
                    ${isYou ? '<span style="color: #10B981; font-size: 10px; font-weight: bold;">(YOU)</span>' : ''}
                </div>
                <div style="font-size: 12px; color: #333; line-height: 1.7;">
                    <div>${flag} ${user.city || 'Unknown'}, ${user.country || 'Unknown'}</div>
                    <div>🕐 ${localTime}</div>
                    <div>⏱️ ${duration}</div>
                </div>
            </div>
        `
    }

    function getPinInfoHTML(pin) {
        const time = new Date(pin.created_at * 1000).toLocaleString()
        return `
            <div style="padding: 12px; min-width: 200px; max-width: 280px; font-family: system-ui;">
                <div style="font-size: 28px; margin-bottom: 10px;">${pin.emoji}</div>
                ${pin.image_data ? `<img src="${pin.image_data}" onclick="window.openLightbox('${pin.image_data}')" style="width: 100%; max-height: 180px; object-fit: contain; background: #f5f5f5; margin-bottom: 10px; cursor: pointer;" />` : ''}
                ${pin.message ? `<p style="margin: 0 0 10px; font-size: 13px;">${pin.message}</p>` : ''}
                <div style="font-size: 11px; color: #666; padding-top: 10px; border-top: 1px solid #ddd;">
                    <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 3px;">
                        <div style="width: 10px; height: 10px; background: ${pin.user_color};"></div>
                        <span style="font-weight: 600;">${pin.user_name}</span>
                    </div>
                    <div>${pin.city || 'Unknown location'} • ${time}</div>
                </div>
            </div>
        `
    }

    function handleCursorMove(data) {
        if (!isMapLoaded || data.user_id === currentUser.id) return

        if (cursorMarkers.has(data.user_id)) {
            cursorMarkers.get(data.user_id).setPosition({ lat: data.lat, lng: data.lng })
        } else {
            const marker = new google.maps.Marker({
                position: { lat: data.lat, lng: data.lng },
                map,
                icon: {
                    path: "M 0,0 L 0,20 L 5,15 L 10,25 L 15,22 L 10,12 L 18,12 Z",
                    fillColor: data.color,
                    fillOpacity: 0.7,
                    strokeColor: '#fff',
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
                if (m) { m.setMap(null); cursorMarkers.delete(data.user_id) }
            }, 2000)
        }
    }

    function handlePinCreated(pin) { pins = [pin, ...pins]; renderPins() }
    function handlePinDeleted(data) { pins = pins.filter(p => p.id !== data.id); renderPins() }
    function handlePresenceUpdate(data) { users = data.users; renderUsers() }
    
    function handleChatMessage(data) {
        chatMessages = [...chatMessages, data]
        setTimeout(() => {
            const el = document.getElementById('chat-messages')
            if (el) el.scrollTop = el.scrollHeight
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
        closePinModal()
    }

    function closePinModal() {
        showPinModal = false
        newPinMessage = ""
        newPinEmoji = "📍"
        newPinImage = null
        newPinImagePreview = null
        pendingPinPosition = null
    }

    function handleImageSelect(e) {
        const file = e.target.files[0]
        if (file) processImageFile(file)
    }

    function processImageFile(file) {
        if (file.size > 3 * 1024 * 1024) { alert('Max 3MB'); return }
        if (!file.type.startsWith('image/')) { alert('Images only'); return }
        const reader = new FileReader()
        reader.onload = (e) => {
            if (showPinModal) {
                newPinImage = e.target.result
                newPinImagePreview = e.target.result
            }
        }
        reader.readAsDataURL(file)
    }

    function sendChat() {
        if (!newChatMessage.trim()) return
        live.pushEvent("send_chat", { message: newChatMessage }, () => {})
        newChatMessage = ""
    }

    function flyToUser(user) {
        if (!map || !user.lat || !user.lng) return
        map.panTo({ lat: user.lat, lng: user.lng })
        map.setZoom(8)
    }

    function getFlagEmoji(code) {
        return code.toUpperCase().split('').map(c => String.fromCodePoint(c.charCodeAt(0) + 127397)).join('')
    }

    function getLocalTime(tz) {
        try { return new Date().toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit' }) }
        catch { return "—" }
    }

    function getDuration(start) {
        const s = Math.floor(Date.now() / 1000 - start)
        if (s < 60) return `${s}s`
        const m = Math.floor(s / 60)
        if (m < 60) return `${m}m`
        return `${Math.floor(m / 60)}h ${m % 60}m`
    }

    $: if (isMapLoaded) renderUsers()
    $: if (isMapLoaded) renderPins()
</script>

<div class="min-h-screen bg-base-200 flex flex-col">
    <!-- Header -->
    <div class="bg-base-100 border-b-4 border-base-content flex-shrink-0 z-20">
        <div class="container mx-auto px-4 py-3">
            <div class="flex items-center justify-between gap-4">
                <div class="flex items-center gap-4">
                    <div>
                        <h1 class="text-lg md:text-xl font-black uppercase tracking-tight">Live World</h1>
                        <p class="text-[10px] font-bold uppercase tracking-wide opacity-60 hidden sm:block">Real-time global presence</p>
                    </div>
                    
                    <!-- Quick Stats -->
                    <div class="hidden md:flex items-center gap-1 border-2 border-base-content">
                        <div class="px-3 py-1.5 border-r border-base-content/30">
                            <span class="font-black text-success">{onlineCount}</span>
                            <span class="text-[10px] font-bold uppercase opacity-50 ml-1">online</span>
                        </div>
                        <div class="px-3 py-1.5 border-r border-base-content/30">
                            <span class="font-black text-primary">{pinCount}</span>
                            <span class="text-[10px] font-bold uppercase opacity-50 ml-1">pins</span>
                        </div>
                        <div class="px-3 py-1.5">
                            <span class="font-black text-secondary">{countriesCount}</span>
                            <span class="text-[10px] font-bold uppercase opacity-50 ml-1">countries</span>
                        </div>
                    </div>
                </div>

                <div class="flex items-center gap-2">
                    <button
                        class="px-3 py-1.5 text-xs font-bold uppercase tracking-wide border-2 border-base-content transition-colors cursor-pointer {showUsers ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
                        onclick={() => showUsers = !showUsers}
                    >
                        👥 {onlineCount}
                    </button>
                    <button
                        class="px-3 py-1.5 text-xs font-bold uppercase tracking-wide border-2 border-base-content transition-colors cursor-pointer {showChat ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
                        onclick={() => showChat = !showChat}
                    >
                        💬 {chatMessages.length || ''}
                    </button>
                    {#if currentUser.name}
                        <div class="hidden sm:flex items-center gap-2 px-3 py-1.5 border-2 border-base-content bg-base-200">
                            <div class="w-3 h-3" style="background: {currentUser.color}"></div>
                            <span class="text-xs font-bold uppercase">{currentUser.name}</span>
                        </div>
                    {/if}
                </div>
            </div>
        </div>
    </div>

    <!-- Map Container -->
    <div class="flex-1 relative">
        <div bind:this={mapElement} class="absolute inset-0"></div>

        {#if !googleMapsApiKey}
            <div class="absolute inset-0 flex items-center justify-center bg-base-200">
                <div class="bg-base-100 border-2 border-base-content p-8 text-center">
                    <div class="text-5xl mb-4">🗺️</div>
                    <h2 class="text-lg font-black uppercase tracking-wide mb-2">API Key Required</h2>
                    <p class="text-xs opacity-60">Configure GOOGLE_MAPS_API_KEY</p>
                </div>
            </div>
        {/if}

        <!-- Users Panel - Bottom Left -->
        {#if showUsers && isMapLoaded}
            <div class="absolute bottom-4 left-4 bg-base-100 border-2 border-base-content z-10 w-64 max-h-80">
                <div class="px-3 py-2 border-b-2 border-base-content bg-base-200 flex items-center justify-between">
                    <span class="text-xs font-bold uppercase tracking-wide">Online ({onlineCount})</span>
                    <button class="text-xs opacity-50 hover:opacity-100 cursor-pointer" onclick={() => showUsers = false}>✕</button>
                </div>
                <div class="overflow-y-auto max-h-60">
                    {#if currentUser.name}
                        <button 
                            class="w-full px-3 py-2 flex items-center gap-3 hover:bg-base-200 transition-colors cursor-pointer border-b border-base-content/10"
                            onclick={() => flyToUser(currentUser)}
                        >
                            <div class="w-4 h-4 flex-shrink-0" style="background: {currentUser.color}"></div>
                            <div class="flex-1 min-w-0 text-left">
                                <div class="text-xs font-bold uppercase truncate">{currentUser.name} <span class="text-success">(you)</span></div>
                                <div class="text-[10px] opacity-50 truncate">
                                    {currentUser.country_code ? getFlagEmoji(currentUser.country_code) : ''} {currentUser.city || 'Unknown'}
                                </div>
                            </div>
                            <div class="text-[10px] font-bold opacity-40">{getDuration(currentUser.joined_at)}</div>
                        </button>
                    {/if}
                    {#each users.filter(u => u.id !== currentUser.id) as user}
                        <button 
                            class="w-full px-3 py-2 flex items-center gap-3 hover:bg-base-200 transition-colors cursor-pointer border-b border-base-content/10"
                            onclick={() => flyToUser(user)}
                        >
                            <div class="w-4 h-4 flex-shrink-0" style="background: {user.color}"></div>
                            <div class="flex-1 min-w-0 text-left">
                                <div class="text-xs font-bold uppercase truncate">{user.name}</div>
                                <div class="text-[10px] opacity-50 truncate">
                                    {user.country_code ? getFlagEmoji(user.country_code) : ''} {user.city || 'Unknown'}
                                </div>
                            </div>
                            <div class="text-[10px] font-bold opacity-40">{getDuration(user.joined_at)}</div>
                        </button>
                    {/each}
                    {#if users.length === 0 && !currentUser.name}
                        <div class="px-3 py-6 text-center text-xs opacity-40">No users online</div>
                    {/if}
                </div>
            </div>
        {/if}

        <!-- Chat Panel - Bottom Right -->
        {#if showChat}
            <div class="absolute bottom-4 right-4 bg-base-100 border-2 border-base-content w-72 max-h-96 flex flex-col z-10">
                <div class="px-3 py-2 border-b-2 border-base-content bg-base-200 flex items-center justify-between flex-shrink-0">
                    <span class="text-xs font-bold uppercase tracking-wide">Chat</span>
                    <button class="text-xs opacity-50 hover:opacity-100 cursor-pointer" onclick={() => showChat = false}>✕</button>
                </div>
                <div id="chat-messages" class="flex-1 overflow-y-auto p-2 space-y-1.5 min-h-[150px] max-h-[250px]">
                    {#if chatMessages.length === 0}
                        <p class="text-[10px] text-center py-8 opacity-40">No messages yet</p>
                    {/if}
                    {#each chatMessages as msg}
                        <div class="bg-base-200 p-2">
                            <div class="flex items-center gap-1.5 mb-0.5">
                                <div class="w-2 h-2" style="background: {msg.color}"></div>
                                <span class="text-[10px] font-bold uppercase">{msg.user_name}</span>
                                <span class="text-[9px] opacity-40">{new Date(msg.timestamp * 1000).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</span>
                            </div>
                            <p class="text-xs">{msg.message}</p>
                        </div>
                    {/each}
                </div>
                <form onsubmit={(e) => { e.preventDefault(); sendChat(); }} class="p-2 border-t-2 border-base-content flex-shrink-0">
                    <div class="flex gap-1.5">
                        <input
                            type="text"
                            bind:value={newChatMessage}
                            placeholder="Message..."
                            class="flex-1 px-2 py-1.5 text-xs border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none"
                            maxlength="200"
                        />
                        <button type="submit" class="px-3 py-1.5 text-xs font-bold bg-base-content text-base-100 cursor-pointer">→</button>
                    </div>
                </form>
            </div>
        {/if}

        <!-- Instructions - Top Left (below map controls) -->
        {#if isMapLoaded}
            <div class="absolute top-16 left-4 bg-base-100/90 border-2 border-base-content p-2 z-10 text-[10px] font-bold uppercase tracking-wide opacity-70">
                Click anywhere to drop a pin
            </div>
        {/if}
    </div>

    <!-- Mobile Stats Bar -->
    <div class="md:hidden bg-base-100 border-t-2 border-base-content flex-shrink-0">
        <div class="grid grid-cols-3 divide-x divide-base-content/30">
            <div class="py-2 text-center">
                <span class="font-black text-success">{onlineCount}</span>
                <span class="text-[10px] font-bold uppercase opacity-50 ml-1">online</span>
            </div>
            <div class="py-2 text-center">
                <span class="font-black text-primary">{pinCount}</span>
                <span class="text-[10px] font-bold uppercase opacity-50 ml-1">pins</span>
            </div>
            <div class="py-2 text-center">
                <span class="font-black text-secondary">{countriesCount}</span>
                <span class="text-[10px] font-bold uppercase opacity-50 ml-1">countries</span>
            </div>
        </div>
    </div>
</div>

<!-- Pin Modal -->
{#if showPinModal}
    <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onclick={closePinModal}>
        <div class="bg-base-100 border-2 border-base-content max-w-sm w-full" onclick={(e) => e.stopPropagation()}>
            <div class="px-4 py-3 border-b-2 border-base-content bg-base-200 flex items-center justify-between">
                <span class="text-sm font-bold uppercase tracking-wide">Drop Pin</span>
                <button class="text-lg opacity-50 hover:opacity-100 cursor-pointer" onclick={closePinModal}>✕</button>
            </div>
            
            <div class="p-4 space-y-4">
                <div>
                    <label class="block text-[10px] font-bold uppercase tracking-wide opacity-60 mb-2">Emoji</label>
                    <div class="flex gap-1.5 flex-wrap">
                        {#each emojis as emoji}
                            <button
                                class="text-xl p-1.5 border-2 cursor-pointer {newPinEmoji === emoji ? 'border-base-content bg-base-200' : 'border-transparent hover:border-base-content/30'}"
                                onclick={() => newPinEmoji = emoji}
                            >{emoji}</button>
                        {/each}
                    </div>
                </div>

                <div>
                    <label class="block text-[10px] font-bold uppercase tracking-wide opacity-60 mb-2">Message</label>
                    <textarea
                        bind:value={newPinMessage}
                        class="w-full px-3 py-2 text-sm border-2 border-base-content bg-base-100 focus:border-primary focus:outline-none resize-none"
                        rows="2"
                        placeholder="Optional message..."
                        maxlength="200"
                    ></textarea>
                </div>

                <div>
                    <label class="block text-[10px] font-bold uppercase tracking-wide opacity-60 mb-2">Photo (optional)</label>
                    {#if newPinImagePreview}
                        <div class="relative">
                            <img src={newPinImagePreview} alt="Preview" class="w-full h-32 object-contain bg-base-200 border-2 border-base-content" />
                            <button class="absolute top-1 right-1 w-6 h-6 bg-error text-error-content text-sm font-bold cursor-pointer" onclick={() => { newPinImage = null; newPinImagePreview = null }}>✕</button>
                        </div>
                    {:else}
                        <input type="file" accept="image/*" onchange={handleImageSelect} class="w-full text-xs" />
                    {/if}
                </div>
            </div>

            <div class="flex gap-2 p-4 border-t-2 border-base-content">
                <button class="flex-1 px-4 py-2.5 text-xs font-bold uppercase tracking-wide bg-base-content text-base-100 cursor-pointer" onclick={dropPin}>Drop Pin</button>
                <button class="px-4 py-2.5 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-200 cursor-pointer" onclick={closePinModal}>Cancel</button>
            </div>
        </div>
    </div>
{/if}

<!-- Image Lightbox -->
{#if lightboxImage}
    <div class="fixed inset-0 bg-black/90 flex items-center justify-center z-[9999] p-4" onclick={() => lightboxImage = null}>
        <button class="absolute top-4 right-4 w-10 h-10 bg-base-100 text-base-content text-xl font-bold hover:bg-base-200 cursor-pointer" onclick={() => lightboxImage = null}>×</button>
        <img src={lightboxImage} alt="Enlarged" class="max-w-full max-h-full object-contain" onclick={(e) => e.stopPropagation()} />
    </div>
{/if}
