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
  let ctx
  let lastCursorSend = 0
  let zoom = 0.8
  let showPalette = false
  let isMobile = false
  const CURSOR_THROTTLE_MS = 250

  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0

    // Calculate appropriate zoom for mobile to fit screen
    if (isMobile) {
      const viewportWidth = window.innerWidth
      const viewportHeight = window.innerHeight
      const toolbarHeight = 120 // Approximate height of toolbar + padding + header

      // Calculate zoom to fit width (with padding)
      const maxCanvasWidth = viewportWidth - 32
      const maxCanvasHeight = viewportHeight - toolbarHeight
      const fullCanvasWidth = width * pixelSize
      const fullCanvasHeight = height * pixelSize

      const zoomByWidth = maxCanvasWidth / fullCanvasWidth
      const zoomByHeight = maxCanvasHeight / fullCanvasHeight
      const calculatedZoom = Math.min(zoomByWidth, zoomByHeight)

      // Clamp zoom between 0.5 and 1.0 for mobile, keep pixels visible
      zoom = Math.min(1.0, Math.max(0.5, calculatedZoom))
    }

    const savedColor = localStorage.getItem('pixels_selected_color')
    if (savedColor && colors.includes(savedColor)) {
      selectedColor = savedColor
      live.pushEvent("select_color", { color: savedColor })
    }
  })

  $: cooldownProgress = canPlace ? 1 : (cooldownSeconds - secondsRemaining) / cooldownSeconds

  $: if (ctx && pixelsVersion >= 0) drawCanvas()

  function initCanvas(node) {
    canvasElement = node
    ctx = node.getContext('2d')
    drawCanvas()
    return { destroy() {} }
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

    // Pixels (draw first, under the grid)
    const inset = 0.5 // Fixed sub-pixel inset for clean edges

    pixels.forEach(pixel => {
      // Calculate exact grid cell boundaries
      const cellLeft = Math.round(pixel.x * effectivePixelSize)
      const cellTop = Math.round(pixel.y * effectivePixelSize)
      const cellRight = Math.round((pixel.x + 1) * effectivePixelSize)
      const cellBottom = Math.round((pixel.y + 1) * effectivePixelSize)

      // Draw pixel within cell boundaries with inset
      ctx.fillStyle = pixel.color
      ctx.fillRect(
        cellLeft + inset,
        cellTop + inset,
        cellRight - cellLeft - inset * 2,
        cellBottom - cellTop - inset * 2
      )
    })

    // Hover preview
    if (hoveredPixel && canPlace) {
      const cellLeft = Math.round(hoveredPixel.x * effectivePixelSize)
      const cellTop = Math.round(hoveredPixel.y * effectivePixelSize)
      const cellRight = Math.round((hoveredPixel.x + 1) * effectivePixelSize)
      const cellBottom = Math.round((hoveredPixel.y + 1) * effectivePixelSize)

      ctx.globalAlpha = 0.6
      ctx.fillStyle = selectedColor
      ctx.fillRect(
        cellLeft + inset,
        cellTop + inset,
        cellRight - cellLeft - inset * 2,
        cellBottom - cellTop - inset * 2
      )
      ctx.globalAlpha = 1.0
    }

    // Grid (draw last, on top of pixels)
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
  }

  function getCoords(clientX, clientY) {
    const rect = canvasElement.getBoundingClientRect()
    const effectivePixelSize = pixelSize * zoom
    return {
      x: Math.floor((clientX - rect.left) / effectivePixelSize),
      y: Math.floor((clientY - rect.top) / effectivePixelSize)
    }
  }

  function handleClick(e) {
    if (!canPlace) return
    const { x, y } = getCoords(e.clientX, e.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleMove(e) {
    const { x, y } = getCoords(e.clientX, e.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
        hoveredPixel = { x, y }
        drawCanvas()
        sendCursorPosition(x, y)
      }
    }
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
    drawCanvas()
  }

  // Touch - tap to place (distinguish from pan/scroll)
  let touchStart = null
  let touchMoved = false
  let touchStartTime = 0

  function handleTouchStart(e) {
    if (e.touches.length === 1) {
      touchStart = { x: e.touches[0].clientX, y: e.touches[0].clientY }
      touchStartTime = Date.now()
      touchMoved = false
    }
  }

  function handleTouchMove(e) {
    if (touchStart) {
      const dx = e.touches[0].clientX - touchStart.x
      const dy = e.touches[0].clientY - touchStart.y
      // More lenient threshold to allow scrolling without accidental pixel placement
      if (Math.hypot(dx, dy) > 5) touchMoved = true
    }
  }

  function handleTouchEnd(e) {
    const touchDuration = Date.now() - touchStartTime
    // Only place pixel if: 1) no movement, 2) quick tap (<300ms), 3) can place
    if (touchStart && !touchMoved && touchDuration < 300 && canPlace) {
      const { x, y } = getCoords(touchStart.x, touchStart.y)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        live.pushEvent("place_pixel", { x, y })
      }
    }
    touchStart = null
    touchMoved = false
    touchStartTime = 0
  }

  function selectColor(color) {
    selectedColor = color
    localStorage.setItem('pixels_selected_color', color)
    live.pushEvent("select_color", { color })
  }

  function adjustZoom(delta) {
    zoom = Math.max(0.5, Math.min(2.5, zoom + delta))
    drawCanvas()
  }

  function handleKeyDown(e) {
    if (e.key >= '1' && e.key <= '9') {
      const idx = parseInt(e.key) - 1
      if (colors[idx]) selectColor(colors[idx])
    }
    if (e.key === '0' && colors[9]) selectColor(colors[9])
    if (e.key === '+' || e.key === '=') adjustZoom(0.15)
    if (e.key === '-') adjustZoom(-0.15)
    if (e.key === 'Escape') showPalette = false
  }

  function handleClickOutside(e) {
    if (showPalette && !e.target.closest('.relative')) {
      showPalette = false
    }
  }
</script>

<svelte:window onkeydown={handleKeyDown} onclick={handleClickOutside} />

<div class="bg-base-200 min-h-screen">
  <div class="container mx-auto px-4 py-3 max-w-full overflow-x-hidden">
    <!-- Compact toolbar -->
    <div class="flex items-center justify-between gap-3 max-w-full">
      <!-- Left: Current color (click to expand on mobile) + desktop palette -->
      <div class="relative flex items-center gap-2">
        <!-- Current color button -->
        <button
          class="relative w-10 h-10 border-2 border-base-content cursor-pointer overflow-hidden"
          style="background-color: {selectedColor};"
          onclick={() => showPalette = !showPalette}
        >
          {#if !canPlace}
            <div class="absolute inset-0 bg-black/50 flex items-center justify-center z-10">
              <span class="text-white text-xs font-black">{secondsRemaining}</span>
            </div>
            <!-- Progress border that wraps around (double stroke for contrast) -->
            <svg class="absolute inset-0 w-full h-full pointer-events-none" viewBox="0 0 40 40">
              <!-- Dark outer stroke for contrast -->
              <rect
                x="1"
                y="1"
                width="38"
                height="38"
                fill="none"
                stroke="rgba(0,0,0,0.8)"
                stroke-width="3"
                stroke-dasharray="{152 * cooldownProgress} 152"
                stroke-dashoffset="0"
                pathLength="152"
              />
              <!-- Bright inner stroke -->
              <rect
                x="1"
                y="1"
                width="38"
                height="38"
                fill="none"
                stroke="rgba(255,255,255,0.95)"
                stroke-width="1.5"
                stroke-dasharray="{152 * cooldownProgress} 152"
                stroke-dashoffset="0"
                pathLength="152"
              />
            </svg>
          {/if}
        </button>

        <!-- Desktop: inline palette -->
        <div class="hidden md:flex border-2 border-base-content">
          {#each colors as color}
            <button
              class="w-6 h-6 cursor-pointer {selectedColor === color ? 'ring-1 ring-inset ring-base-content' : ''}"
              style="background-color: {color};"
              onclick={() => selectColor(color)}
            ></button>
          {/each}
        </div>

        <!-- Mobile: dropdown palette -->
        {#if showPalette}
          <div class="absolute top-12 left-0 z-50 bg-base-100 border-2 border-base-content p-2 md:hidden shadow-lg">
            <div class="grid grid-cols-5 gap-1.5 w-max">
              {#each colors as color}
                <button
                  class="w-10 h-10 cursor-pointer border border-base-content {selectedColor === color ? 'ring-2 ring-offset-1 ring-base-content' : ''}"
                  style="background-color: {color};"
                  onclick={() => { selectColor(color); showPalette = false; }}
                ></button>
              {/each}
            </div>
          </div>
        {/if}
      </div>

      <!-- Right: Stats + Zoom -->
      <div class="flex items-center gap-2 text-xs">
        <!-- Stats -->
        <div class="hidden sm:block opacity-50">
          <span class="font-bold">{stats.total_pixels.toLocaleString()}</span> px
          <span class="mx-1">·</span>
          <span class="font-bold">{stats.unique_users}</span> artists
        </div>

        <!-- Zoom -->
        <div class="flex items-center border-2 border-base-content">
          <button class="w-7 h-7 font-bold hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer" onclick={() => adjustZoom(-0.15)}>−</button>
          <span class="w-10 text-center text-[11px] font-bold">{Math.round(zoom * 100)}%</span>
          <button class="w-7 h-7 font-bold hover:bg-base-content hover:text-base-100 transition-colors cursor-pointer" onclick={() => adjustZoom(0.15)}>+</button>
        </div>
      </div>
    </div>

    <!-- Canvas wrapper -->
    <div class="relative flex justify-center items-start mt-3 w-full overflow-auto max-h-[calc(100vh-140px)] bg-base-300/30 rounded-lg border-2 border-base-content p-4 scroll-smooth">
      <div class="relative inline-block">
        <canvas
          use:initCanvas
          class="bg-white shadow-xl border-2 border-base-content cursor-crosshair block"
          onclick={handleClick}
          onmousemove={handleMove}
          onmouseleave={handleLeave}
          ontouchstart={handleTouchStart}
          ontouchmove={handleTouchMove}
          ontouchend={handleTouchEnd}
        ></canvas>

        <!-- Coordinates overlay -->
        {#if hoveredPixel}
          <div class="absolute top-2 right-2 px-2 py-1 bg-black/60 text-white text-xs font-mono rounded">
            {hoveredPixel.x}, {hoveredPixel.y}
          </div>
        {/if}
      </div>

      <!-- Scroll indicator for mobile (shows when canvas is larger than viewport) -->
      {#if isMobile}
        <div class="absolute bottom-2 left-1/2 -translate-x-1/2 px-3 py-1.5 bg-base-content text-base-100 text-xs font-bold rounded-full shadow-lg pointer-events-none opacity-70 flex items-center gap-1.5">
          <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
          </svg>
          <span>Drag to scroll</span>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
  }
</style>
