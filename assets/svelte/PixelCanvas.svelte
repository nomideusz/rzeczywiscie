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
  let zoom = 1
  let isMobile = false
  const CURSOR_THROTTLE_MS = 250

  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
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

    // Grid
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

    // Pixels
    const inset = Math.max(0.5, Math.round(effectivePixelSize * 0.04))
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

    // Hover preview
    if (hoveredPixel && canPlace) {
      ctx.globalAlpha = 0.6
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

  // Touch - tap to place
  let touchStart = null
  let touchMoved = false

  function handleTouchStart(e) {
    if (e.touches.length === 1) {
      touchStart = { x: e.touches[0].clientX, y: e.touches[0].clientY }
      touchMoved = false
    }
  }

  function handleTouchMove(e) {
    if (touchStart) {
      const dx = e.touches[0].clientX - touchStart.x
      const dy = e.touches[0].clientY - touchStart.y
      if (Math.hypot(dx, dy) > 10) touchMoved = true
    }
  }

  function handleTouchEnd(e) {
    if (touchStart && !touchMoved && canPlace) {
      const { x, y } = getCoords(touchStart.x, touchStart.y)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        live.pushEvent("place_pixel", { x, y })
      }
    }
    touchStart = null
    touchMoved = false
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
    if (e.key === '+' || e.key === '=') adjustZoom(0.2)
    if (e.key === '-') adjustZoom(-0.2)
  }
</script>

<svelte:window onkeydown={handleKeyDown} />

<div class="py-4 bg-base-200">
  <div class="container mx-auto px-4">
    <!-- Unified toolbar -->
    <div class="flex items-center justify-center gap-3 sm:gap-4 mb-4">
      <!-- Zoom out -->
      <button 
        class="w-8 h-8 flex items-center justify-center text-lg font-bold opacity-40 hover:opacity-100 hover:bg-base-300 rounded transition-all cursor-pointer"
        onclick={() => adjustZoom(-0.2)}
      >−</button>

      <!-- Colors -->
      <div class="flex items-center gap-0.5 sm:gap-1">
        {#each colors as color}
          <button
            class="relative w-6 h-6 sm:w-7 sm:h-7 rounded-sm cursor-pointer transition-all {selectedColor === color ? 'scale-125 z-10' : 'hover:scale-110'}"
            style="background-color: {color};"
            onclick={() => selectColor(color)}
          >
            {#if selectedColor === color}
              <!-- Border progress for cooldown -->
              <svg class="absolute -inset-0.5 w-[calc(100%+4px)] h-[calc(100%+4px)]" viewBox="0 0 36 36">
                <rect x="1" y="1" width="34" height="34" fill="none" stroke="currentColor" stroke-width="2" class="opacity-30" rx="2"/>
                {#if !canPlace}
                  <rect 
                    x="1" y="1" width="34" height="34" fill="none" stroke="currentColor" stroke-width="2.5" rx="2"
                    stroke-dasharray="{cooldownProgress * 136} 136"
                    stroke-dashoffset="0"
                    class="transition-all duration-1000"
                    style="transform-origin: center; transform: rotate(-90deg);"
                  />
                {/if}
              </svg>
              {#if !canPlace}
                <span class="absolute inset-0 flex items-center justify-center text-[9px] font-black text-white drop-shadow-sm">{secondsRemaining}</span>
              {/if}
            {/if}
          </button>
        {/each}
      </div>

      <!-- Zoom in -->
      <button 
        class="w-8 h-8 flex items-center justify-center text-lg font-bold opacity-40 hover:opacity-100 hover:bg-base-300 rounded transition-all cursor-pointer"
        onclick={() => adjustZoom(0.2)}
      >+</button>

      <!-- Stats (desktop) -->
      <div class="hidden sm:flex items-center gap-2 text-[11px] opacity-40 ml-2">
        <span>{stats.total_pixels.toLocaleString()} px</span>
        <span>•</span>
        <span>{stats.unique_users} artists</span>
        <span>•</span>
        <span>{Math.round(zoom * 100)}%</span>
      </div>
    </div>

    <!-- Canvas wrapper -->
    <div class="flex justify-center">
        <div class="relative inline-block">
          <canvas
            use:initCanvas
            class="bg-white shadow-lg cursor-crosshair block"
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
