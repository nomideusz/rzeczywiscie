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

  function centerCanvas() {
    if (!scrollContainer) return
    
    const scrollWidth = scrollContainer.scrollWidth
    const scrollHeight = scrollContainer.scrollHeight
    const clientWidth = scrollContainer.clientWidth
    const clientHeight = scrollContainer.clientHeight
    
    scrollContainer.scrollLeft = (scrollWidth - clientWidth) / 2
    scrollContainer.scrollTop = (scrollHeight - clientHeight) / 2
  }

  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
    if (isMobile) {
      zoom = 2
      if (ctx) drawCanvas()
      setTimeout(centerCanvas, 100)
    }
    
    const savedColor = localStorage.getItem('pixels_selected_color')
    if (savedColor && colors.includes(savedColor)) {
      selectedColor = savedColor
      live.pushEvent("select_color", { color: savedColor })
    }

    hasScrolled = localStorage.getItem('pixels_has_scrolled') === 'true'
    setTimeout(checkScrollability, 500)
  })

  function checkScrollability() {
    if (!scrollContainer) return
    
    const threshold = 5
    const isScrollable = scrollContainer.scrollWidth > scrollContainer.clientWidth + threshold ||
                         scrollContainer.scrollHeight > scrollContainer.clientHeight + threshold
    
    canScroll = isScrollable
    
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

  $: cooldownProgress = canPlace ? 1 : (cooldownSeconds - secondsRemaining) / cooldownSeconds

  function calculatePixelSize() {
    if (!canvasContainer) return

    const padding = 64
    const containerWidth = canvasContainer.clientWidth - padding
    const containerHeight = canvasContainer.clientHeight - padding

    const maxPixelWidth = Math.floor(containerWidth / width)
    const maxPixelHeight = Math.floor(containerHeight / height)

    const fittedSize = Math.min(maxPixelWidth, maxPixelHeight)
    const newPixelSize = Math.max(2, Math.min(8, fittedSize))

    if (newPixelSize !== pixelSize) {
      pixelSize = newPixelSize
      if (ctx) drawCanvas()
    }
  }

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

    ctx.strokeStyle = 'rgba(0, 0, 0, 0.08)'
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
  let singleTouchStart = null
  let touchMoved = false
  const TAP_THRESHOLD = 10

  function handleTouchStart(event) {
    if (event.touches.length === 2) {
      event.preventDefault()
      singleTouchStart = null
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
  }
</script>

<svelte:window on:keydown={handleKeyDown} on:mouseup={handleMouseUp} on:click={handleClickOutside} />

<div class="fixed inset-0 flex flex-col bg-base-200">
  <!-- Canvas Area -->
  <div 
    class="flex-1 overflow-auto"
    use:initScrollContainer
    use:initContainer
  >
    <div class="flex items-center justify-center min-h-full" style="min-width: max-content; padding: 2rem;">
      <div class="relative border-2 border-base-content">
        <canvas
          use:initCanvas
          class="bg-white {isPanning ? 'cursor-grabbing' : 'cursor-crosshair'}"
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
              class="w-2 h-2 border-2 border-white"
              style="background-color: {cursor.color}"
            ></div>
          </div>
        {/each}
      </div>
    </div>

    <!-- Scroll hint overlay -->
    {#if showScrollHint && canScroll}
      <div class="absolute inset-0 pointer-events-none flex items-center justify-center">
        <div class="bg-base-content text-base-100 px-4 py-3 flex items-center gap-3 animate-hint font-bold text-sm uppercase tracking-wide">
          <span>↔</span>
          <span>Drag to explore</span>
        </div>
      </div>
    {/if}
  </div>

  <!-- UI Container -->
  <div class="contents">
    
    <!-- Color picker -->
    <div 
      class="fixed z-50 {isMobile ? 'bottom-4 left-1/2 -translate-x-1/2' : 'bottom-6 left-6'}"
    >
      <div class="palette-container relative flex items-end gap-3">
        <!-- Back button - only on desktop -->
        {#if !isMobile}
          <a 
            href="/" 
            class="w-10 h-10 bg-base-100 border-2 border-base-content flex items-center justify-center text-base-content hover:bg-base-content hover:text-base-100 transition-colors"
          >
            ←
          </a>
        {/if}

        <!-- Expanded palette -->
        {#if showPalette}
          <div class="absolute {isMobile ? 'bottom-16 left-1/2 -translate-x-1/2' : 'bottom-16 left-0'} bg-base-100 border-2 border-base-content p-3 animate-in">
            <div class="flex flex-wrap gap-1 justify-center" style="width: 200px;">
              {#each colors as color, i}
                <button
                  class="w-8 h-8 transition-all cursor-pointer {selectedColor === color ? 'ring-2 ring-base-content ring-offset-1' : 'hover:scale-110'}"
                  style="background-color: {color};"
                  on:click={() => selectColor(color)}
                >
                </button>
              {/each}
            </div>
            {#if !isMobile}
              <p class="text-[9px] font-bold uppercase tracking-wide opacity-40 mt-2 text-center">Press 1-0 for colors</p>
            {/if}
          </div>
        {/if}

        <!-- Current color button with cooldown -->
        <button
          class="w-14 h-14 sm:w-12 sm:h-12 border-2 border-base-content transition-all cursor-pointer relative overflow-hidden"
          style="background-color: {selectedColor};"
          on:click={openPalette}
        >
          <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 36 36">
            <rect x="0" y="0" width="36" height="36" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="4"/>
            <rect x="0" y="0" width="36" height="36" fill="none" stroke="white" stroke-width="4"
              stroke-dasharray="144" stroke-dashoffset={144 - cooldownProgress * 144}
              class="transition-all duration-1000 ease-linear"/>
          </svg>
          {#if !canPlace}
            <span class="absolute inset-0 flex items-center justify-center text-white text-sm font-black drop-shadow">
              {secondsRemaining}
            </span>
          {/if}
        </button>

        <!-- Zoom controls - inline on mobile -->
        {#if isMobile}
          <div class="bg-base-100 border-2 border-base-content flex items-center">
            <button class="w-10 h-10 text-base-content active:bg-base-200 text-lg font-bold cursor-pointer" on:click={() => adjustZoom(-0.25)}>−</button>
            <button class="w-10 h-10 text-base-content active:bg-base-200 text-lg font-bold cursor-pointer border-l-2 border-base-content" on:click={() => adjustZoom(0.25)}>+</button>
          </div>
        {/if}
      </div>
    </div>

    <!-- Desktop zoom controls -->
    {#if !isMobile}
      <div class="fixed bottom-6 right-6 flex items-center gap-2">
        <div class="bg-base-100 border-2 border-base-content flex items-center">
          <button class="w-10 h-10 text-base-content hover:bg-base-200 text-lg font-bold transition-colors cursor-pointer" on:click={() => adjustZoom(-0.25)}>−</button>
          <span class="text-xs font-bold w-14 text-center">{Math.round(zoom * 100)}%</span>
          <button class="w-10 h-10 text-base-content hover:bg-base-200 text-lg font-bold transition-colors cursor-pointer border-l-2 border-base-content" on:click={() => adjustZoom(0.25)}>+</button>
        </div>
      </div>
    {/if}

    <!-- Stats -->
    <div 
      class="fixed z-50 {isMobile ? 'top-2 left-2' : 'top-6 left-6'}"
    >
      <div class="bg-base-100 border-2 border-base-content {isMobile ? 'px-3 py-2' : 'px-4 py-3'}">
        <div class="flex items-center gap-3">
          {#if isMobile}
            <a href="/" class="text-base-content font-bold">←</a>
          {/if}
          <div>
            <h1 class="{isMobile ? 'text-xs' : 'text-sm'} font-black uppercase tracking-tight">Pixels</h1>
            <p class="{isMobile ? 'text-[9px]' : 'text-[10px]'} font-bold uppercase tracking-wide opacity-50">
              {stats.total_pixels.toLocaleString()} placed · {stats.unique_users} artists
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Coordinates - only on desktop -->
    {#if hoveredPixel && !isMobile}
      <div class="fixed top-6 right-6 bg-base-content text-base-100 px-3 py-2 text-xs font-mono font-bold">
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
</style>
