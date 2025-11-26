<script>
  import { onMount } from 'svelte'

  export let width = 100
  export let height = 100
  export let pixels = []
  export let pixelsVersion = 0
  export let colors = []
  export let selectedColor = "#1a1a1a"
  export let canPlace = true
  export let secondsRemaining = 0
  export let cooldownSeconds = 15
  export let stats = { total_pixels: 0, unique_users: 0 }
  export let cursors = []
  export let live

  let hoveredPixel = null
  let pixelSize = 8
  let canvasElement
  let canvasContainer
  let scrollContainer
  let ctx
  let lastCursorSend = 0
  let zoom = 1
  let showPalette = false
  let isMobile = false
  let canScroll = false
  let showScrollHint = false
  let hasScrolled = false
  const CURSOR_THROTTLE_MS = 250

  // Pan/drag state
  let isPanning = false
  let panStart = { x: 0, y: 0 }
  let scrollStart = { x: 0, y: 0 }

  // Detect mobile and check if canvas is scrollable
  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
    const savedColor = localStorage.getItem('pixels_selected_color')
    if (savedColor && colors.includes(savedColor)) {
      selectedColor = savedColor
      live.pushEvent("select_color", { color: savedColor })
    }

    // Check if user has seen scroll hint before
    hasScrolled = localStorage.getItem('pixels_has_scrolled') === 'true'

    // Check scrollability after a short delay to let canvas render
    setTimeout(checkScrollability, 500)
  })

  function checkScrollability() {
    if (!scrollContainer) return
    
    // Add a small threshold (5px) to avoid false positives from rounding
    const threshold = 5
    const isScrollable = scrollContainer.scrollWidth > scrollContainer.clientWidth + threshold ||
                         scrollContainer.scrollHeight > scrollContainer.clientHeight + threshold
    
    canScroll = isScrollable
    
    // Show hint briefly if scrollable and user hasn't scrolled before
    if (isScrollable && !hasScrolled && isMobile) {
      showScrollHint = true
      setTimeout(() => {
        showScrollHint = false
      }, 4000)
    } else {
      showScrollHint = false
    }
  }

  function onUserScrolled() {
    if (!hasScrolled) {
      hasScrolled = true
      localStorage.setItem('pixels_has_scrolled', 'true')
      showScrollHint = false
    }
  }

  // Cooldown progress (0 to 1)
  $: cooldownProgress = canPlace ? 1 : (cooldownSeconds - secondsRemaining) / cooldownSeconds

  // Calculate responsive pixel size based on available space
  function calculatePixelSize() {
    if (!canvasContainer) return

    // Account for margin: m-4 (16px each side = 32px total) on mobile
    // sm:m-8 (32px each side = 64px total) on desktop
    const isSmallScreen = canvasContainer.clientWidth < 640
    const margin = isSmallScreen ? 32 : 64  // 16px * 2 or 32px * 2
    const containerWidth = canvasContainer.clientWidth - margin
    const containerHeight = canvasContainer.clientHeight - margin

    const maxPixelWidth = Math.floor(containerWidth / width)
    const maxPixelHeight = Math.floor(containerHeight / height)

    // On small screens, fit canvas to screen; on large screens allow some flexibility
    const fittedSize = Math.min(maxPixelWidth, maxPixelHeight)
    const newPixelSize = isSmallScreen 
      ? Math.max(2, fittedSize)  // On mobile, fit to screen
      : Math.max(3, Math.min(10, fittedSize))  // On desktop, clamp to reasonable range

    if (newPixelSize !== pixelSize) {
      pixelSize = newPixelSize
      if (ctx) drawCanvas()
    }
  }

  // Draw canvas when pixels change
  $: if (ctx && pixelsVersion >= 0) {
    drawCanvas()
  }

  function initCanvas(node) {
    canvasElement = node
    ctx = node.getContext('2d')
    drawCanvas()
    return { destroy() {} }
  }

  function initContainer(node) {
    canvasContainer = node
    calculatePixelSize()

    const resizeObserver = new ResizeObserver(() => calculatePixelSize())
    resizeObserver.observe(node)

    return { destroy() { resizeObserver.disconnect() } }
  }

  function initScrollContainer(node) {
    scrollContainer = node
    
    // Listen for scroll to dismiss hint
    const handleScroll = () => onUserScrolled()
    node.addEventListener('scroll', handleScroll, { passive: true })
    
    return { 
      destroy() {
        node.removeEventListener('scroll', handleScroll)
      }
    }
  }

  function drawCanvas() {
    if (!ctx) return

    const effectivePixelSize = pixelSize * zoom
    const actualWidth = width * effectivePixelSize
    const actualHeight = height * effectivePixelSize

    if (canvasElement.width !== actualWidth || canvasElement.height !== actualHeight) {
      canvasElement.width = actualWidth
      canvasElement.height = actualHeight
    }

    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, actualWidth, actualHeight)

    // Draw grid - use single path for better performance and appearance
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.06)'
    ctx.lineWidth = 1
    ctx.beginPath()

    for (let x = 0; x <= width; x++) {
      const px = Math.round(x * effectivePixelSize) + 0.5
      ctx.moveTo(px, 0)
      ctx.lineTo(px, actualHeight)
    }

    for (let y = 0; y <= height; y++) {
      const py = Math.round(y * effectivePixelSize) + 0.5
      ctx.moveTo(0, py)
      ctx.lineTo(actualWidth, py)
    }

    ctx.stroke()

    // Draw pixels with 1px inset to show grid border on all sides
    const inset = Math.max(1, Math.round(effectivePixelSize * 0.08))
    const pixelDrawSize = Math.max(1, effectivePixelSize - inset * 2)
    
    pixels.forEach(pixel => {
      ctx.fillStyle = pixel.color
      ctx.fillRect(
        pixel.x * effectivePixelSize + inset,
        pixel.y * effectivePixelSize + inset,
        pixelDrawSize,
        pixelDrawSize
      )
    })

    // Preview hovered pixel with same inset
    if (hoveredPixel && canPlace && !isPanning) {
      ctx.globalAlpha = 0.5
      ctx.fillStyle = selectedColor
      ctx.fillRect(
        hoveredPixel.x * effectivePixelSize + inset,
        hoveredPixel.y * effectivePixelSize + inset,
        pixelDrawSize,
        pixelDrawSize
      )
      ctx.globalAlpha = 1.0
    }
  }

  function getCoords(clientX, clientY) {
    const rect = canvasElement.getBoundingClientRect()
    const effectivePixelSize = pixelSize * zoom
    const x = Math.floor((clientX - rect.left) / effectivePixelSize)
    const y = Math.floor((clientY - rect.top) / effectivePixelSize)
    return { x, y }
  }

  function handleMouseDown(event) {
    if (event.button === 1) {
      event.preventDefault()
      startPan(event.clientX, event.clientY)
    }
  }

  function handleMouseUp(event) {
    if (isPanning) {
      isPanning = false
      return
    }
  }

  function handleClick(event) {
    if (isPanning || !canPlace) return
    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleMove(event) {
    if (isPanning) {
      doPan(event.clientX, event.clientY)
      return
    }

    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
        hoveredPixel = { x, y }
        drawCanvas()
        sendCursorPosition(x, y)
      }
    }
  }

  function startPan(clientX, clientY) {
    isPanning = true
    panStart = { x: clientX, y: clientY }
    if (scrollContainer) {
      scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
    }
  }

  function doPan(clientX, clientY) {
    if (!scrollContainer) return
    const dx = panStart.x - clientX
    const dy = panStart.y - clientY
    scrollContainer.scrollLeft = scrollStart.x + dx
    scrollContainer.scrollTop = scrollStart.y + dy
  }

  function sendCursorPosition(x, y) {
    const now = Date.now()
    if (now - lastCursorSend >= CURSOR_THROTTLE_MS) {
      lastCursorSend = now
      live.pushEvent("cursor_move", { x, y })
    }
  }

  function handleLeave() {
    hoveredPixel = null
    isPanning = false
    drawCanvas()
  }

  // Touch handling
  let lastTouchDistance = 0
  let touchPanStart = null
  let singleTouchStart = null  // Track single touch start position
  let touchMoved = false       // Track if touch moved significantly
  const TAP_THRESHOLD = 10     // Max pixels moved to count as tap

  function handleTouchStart(event) {
    if (event.touches.length === 2) {
      event.preventDefault()
      singleTouchStart = null  // Cancel single touch if second finger added
      touchMoved = true
      const touch1 = event.touches[0]
      const touch2 = event.touches[1]
      const centerX = (touch1.clientX + touch2.clientX) / 2
      const centerY = (touch1.clientY + touch2.clientY) / 2
      touchPanStart = { x: centerX, y: centerY }
      if (scrollContainer) {
        scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
      }
      lastTouchDistance = Math.hypot(
        touch2.clientX - touch1.clientX,
        touch2.clientY - touch1.clientY
      )
    } else if (event.touches.length === 1) {
      const touch = event.touches[0]
      singleTouchStart = { clientX: touch.clientX, clientY: touch.clientY }
      touchMoved = false
      
      const { x, y } = getCoords(touch.clientX, touch.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        hoveredPixel = { x, y }
        drawCanvas()
      }
    }
  }

  function handleTouchMove(event) {
    if (event.touches.length === 2) {
      event.preventDefault()
      const touch1 = event.touches[0]
      const touch2 = event.touches[1]
      
      const centerX = (touch1.clientX + touch2.clientX) / 2
      const centerY = (touch1.clientY + touch2.clientY) / 2
      if (touchPanStart && scrollContainer) {
        const dx = touchPanStart.x - centerX
        const dy = touchPanStart.y - centerY
        scrollContainer.scrollLeft = scrollStart.x + dx
        scrollContainer.scrollTop = scrollStart.y + dy
      }

      const distance = Math.hypot(
        touch2.clientX - touch1.clientX,
        touch2.clientY - touch1.clientY
      )
      if (lastTouchDistance > 0) {
        const scale = distance / lastTouchDistance
        if (Math.abs(scale - 1) > 0.02) {
          const newZoom = Math.max(0.5, Math.min(3, zoom * scale))
          if (newZoom !== zoom) {
            zoom = newZoom
            drawCanvas()
          }
          lastTouchDistance = distance
        }
      }
    } else if (event.touches.length === 1) {
      const touch = event.touches[0]
      
      // Check if moved beyond tap threshold
      if (singleTouchStart) {
        const dx = touch.clientX - singleTouchStart.clientX
        const dy = touch.clientY - singleTouchStart.clientY
        if (Math.hypot(dx, dy) > TAP_THRESHOLD) {
          touchMoved = true
        }
      }
      
      const { x, y } = getCoords(touch.clientX, touch.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
          hoveredPixel = { x, y }
          drawCanvas()
          sendCursorPosition(x, y)
        }
      }
    }
  }

  function handleTouchEnd(event) {
    // Place pixel only if it was a tap (no significant movement) and can place
    if (singleTouchStart && !touchMoved && canPlace && hoveredPixel) {
      const { x, y } = hoveredPixel
      if (x >= 0 && x < width && y >= 0 && y < height) {
        live.pushEvent("place_pixel", { x, y })
      }
    }
    
    touchPanStart = null
    lastTouchDistance = 0
    singleTouchStart = null
    touchMoved = false
    hoveredPixel = null
    drawCanvas()
  }

  function selectColor(color) {
    selectedColor = color
    localStorage.setItem('pixels_selected_color', color)
    live.pushEvent("select_color", { color })
    showPalette = false
  }

  function adjustZoom(delta) {
    zoom = Math.max(0.5, Math.min(3, zoom + delta))
    drawCanvas()
    // Recheck scrollability after zoom change
    setTimeout(checkScrollability, 100)
  }

  function handleKeyDown(event) {
    if (event.key >= '1' && event.key <= '9') {
      const index = parseInt(event.key) - 1
      if (colors[index]) {
        selectColor(colors[index])
      }
    }
    if (event.key === '0' && colors[9]) {
      selectColor(colors[9])
    }
  }

  function handleClickOutside(event) {
    if (showPalette && !event.target.closest('.palette-container')) {
      showPalette = false
    }
  }

  function openPalette() {
    showPalette = true
    showUI = true
    if (uiTimeout) clearTimeout(uiTimeout)
  }
</script>

<svelte:window on:keydown={handleKeyDown} on:mouseup={handleMouseUp} on:click={handleClickOutside} />

<div class="fixed inset-0 flex flex-col bg-neutral-100">
  <!-- Canvas Area - full screen -->
  <div 
    class="flex-1 overflow-auto"
    use:initScrollContainer
    use:initContainer
  >
    <div class="flex items-center justify-center min-h-full min-w-full">
      <div class="relative m-4 sm:m-8">
        <canvas
          use:initCanvas
          class="shadow-2xl rounded-sm bg-white {isPanning ? 'cursor-grabbing' : 'cursor-crosshair'}"
          on:mousedown={handleMouseDown}
          on:click={handleClick}
          on:mousemove={handleMove}
          on:mouseleave={handleLeave}
          on:touchstart={handleTouchStart}
          on:touchmove={handleTouchMove}
          on:touchend={handleTouchEnd}
          on:contextmenu|preventDefault
        ></canvas>

        <!-- Live Cursors -->
        {#each cursors as cursor (cursor.id)}
          <div
            class="absolute pointer-events-none transition-all duration-100"
            style="left: {cursor.x * pixelSize * zoom}px; top: {cursor.y * pixelSize * zoom}px;"
          >
            <div
              class="w-2 h-2 rounded-full border border-white shadow"
              style="background-color: {cursor.color}"
            ></div>
          </div>
        {/each}
      </div>
    </div>

    <!-- Scroll hint overlay -->
    {#if showScrollHint && canScroll}
      <div class="absolute inset-0 pointer-events-none flex items-center justify-center">
        <div class="bg-black/70 text-white px-4 py-3 rounded-2xl flex items-center gap-3 animate-hint">
          <svg class="w-6 h-6 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
          </svg>
          <span class="text-sm">Drag to explore</span>
        </div>
      </div>
    {/if}
  </div>

  <!-- UI Container -->
  <div class="contents">
    
    <!-- Color picker - bottom center on mobile, bottom left on desktop -->
    <div 
      class="fixed z-50 {isMobile ? 'bottom-4 left-1/2 -translate-x-1/2' : 'bottom-6 left-6'}"
    >
      <div class="palette-container relative flex items-end gap-3">
        <!-- Back button - only on desktop -->
        {#if !isMobile}
          <a 
            href="/" 
            class="w-10 h-10 bg-white rounded-full shadow-lg flex items-center justify-center text-neutral-400 hover:text-neutral-900 transition-colors"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
            </svg>
          </a>
        {/if}

        <!-- Expanded palette -->
        {#if showPalette}
          <div class="absolute {isMobile ? 'bottom-16 left-1/2 -translate-x-1/2' : 'bottom-16 left-0'} bg-white rounded-2xl shadow-2xl p-4 animate-in">
            <div class="flex flex-wrap gap-2 justify-center" style="width: 200px;">
              {#each colors as color, i}
                <button
                  class="group relative w-9 h-9 rounded-lg transition-all active:scale-95 {selectedColor === color ? 'ring-2 ring-neutral-900 ring-offset-2' : ''}"
                  style="background-color: {color};"
                  on:click={() => selectColor(color)}
                >
                  {#if i < 10 && !isMobile}
                    <span class="absolute -top-1 -right-1 w-4 h-4 bg-neutral-900 text-white text-[10px] font-medium rounded-full opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      {i < 9 ? i + 1 : 0}
                    </span>
                  {/if}
                </button>
              {/each}
            </div>
            {#if !isMobile}
              <p class="text-[10px] text-neutral-400 mt-3 text-center">1-0 for first 10 colors</p>
            {/if}
          </div>
        {/if}

        <!-- Current color button -->
        <button
          class="w-14 h-14 sm:w-12 sm:h-12 rounded-full shadow-lg transition-all active:scale-95 relative overflow-hidden"
          style="background-color: {selectedColor};"
          on:click={openPalette}
        >
          <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 36 36">
            <circle cx="18" cy="18" r="16" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="3"/>
            <circle cx="18" cy="18" r="16" fill="none" stroke="white" stroke-width="3"
              stroke-dasharray="100" stroke-dashoffset={100 - cooldownProgress * 100} stroke-linecap="round"
              class="transition-all duration-1000 ease-linear"/>
          </svg>
          {#if !canPlace}
            <span class="absolute inset-0 flex items-center justify-center text-white text-sm font-bold drop-shadow">
              {secondsRemaining}
            </span>
          {/if}
        </button>

        <!-- Zoom controls - inline on mobile -->
        {#if isMobile}
          <div class="bg-white rounded-full shadow-lg flex items-center overflow-hidden">
            <button class="w-10 h-10 text-neutral-600 active:bg-neutral-100 text-lg font-medium" on:click={() => adjustZoom(-0.25)}>−</button>
            <button class="w-10 h-10 text-neutral-600 active:bg-neutral-100 text-lg font-medium" on:click={() => adjustZoom(0.25)}>+</button>
          </div>
        {/if}
      </div>
    </div>

    <!-- Desktop zoom controls - bottom right -->
    {#if !isMobile}
      <div class="fixed bottom-6 right-6 flex items-center gap-2">
        <div class="bg-white rounded-full shadow-lg flex items-center overflow-hidden">
          <button class="w-10 h-10 text-neutral-600 hover:bg-neutral-50 text-lg font-medium transition-colors" on:click={() => adjustZoom(-0.25)}>−</button>
          <span class="text-xs text-neutral-500 w-12 text-center font-medium">{Math.round(zoom * 100)}%</span>
          <button class="w-10 h-10 text-neutral-600 hover:bg-neutral-50 text-lg font-medium transition-colors" on:click={() => adjustZoom(0.25)}>+</button>
        </div>
      </div>
    {/if}

    <!-- Stats - top left, smaller on mobile -->
    <div 
      class="fixed z-50 {isMobile ? 'top-2 left-2' : 'top-6 left-6'}"
    >
      <div class="bg-white/90 backdrop-blur rounded-xl shadow-lg {isMobile ? 'px-3 py-2' : 'px-4 py-3'}">
        <div class="flex items-center gap-2">
          {#if isMobile}
            <a href="/" class="text-neutral-400">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
              </svg>
            </a>
          {/if}
          <div>
            <h1 class="{isMobile ? 'text-xs' : 'text-sm'} font-semibold text-neutral-900">Pixels</h1>
            <p class="{isMobile ? 'text-[10px]' : 'text-xs'} text-neutral-500">{stats.total_pixels.toLocaleString()} · {stats.unique_users} artists</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Coordinates - only on desktop -->
    {#if hoveredPixel && !isMobile}
      <div class="fixed top-6 right-6 bg-neutral-900 text-white px-3 py-2 rounded-lg text-xs font-mono">
        {hoveredPixel.x}, {hoveredPixel.y}
      </div>
    {/if}
  </div>
</div>

<style>
  :global(body) {
    overflow: hidden;
  }

  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
  }

  .animate-in {
    animation: fadeIn 0.15s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.95);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  .animate-hint {
    animation: hintFade 4s ease-out forwards;
  }

  @keyframes hintFade {
    0% { opacity: 0; transform: scale(0.9); }
    10% { opacity: 1; transform: scale(1); }
    80% { opacity: 1; }
    100% { opacity: 0; }
  }

  .animate-bounce-x {
    animation: bounceX 1.5s ease-in-out infinite;
  }

  @keyframes bounceX {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-4px); }
  }
</style>
