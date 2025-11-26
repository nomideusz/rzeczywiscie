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
  let zoom = 1.2
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
    <!-- Stats bar -->
    <div class="flex items-center justify-between mb-3 text-xs opacity-60">
      <div class="flex items-center gap-3">
        <span><strong>{stats.total_pixels.toLocaleString()}</strong> pixels</span>
        <span><strong>{stats.unique_users}</strong> artists</span>
      </div>
      <div class="flex items-center gap-2">
        <button class="px-2 py-1 hover:bg-base-300 rounded cursor-pointer" onclick={() => adjustZoom(-0.2)}>−</button>
        <span class="w-12 text-center">{Math.round(zoom * 100)}%</span>
        <button class="px-2 py-1 hover:bg-base-300 rounded cursor-pointer" onclick={() => adjustZoom(0.2)}>+</button>
      </div>
    </div>

    <!-- Canvas wrapper - scrollable horizontally if needed -->
    <div class="overflow-x-auto pb-3" style="scrollbar-width: thin;">
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

    <!-- Color picker -->
    <div class="flex items-center justify-center gap-1 pt-2">
      {#each colors as color}
        <button
          class="relative w-8 h-8 sm:w-9 sm:h-9 border-2 cursor-pointer transition-all {selectedColor === color ? 'border-base-content scale-110' : 'border-base-content/20 hover:border-base-content/50'}"
          style="background-color: {color};"
          onclick={() => selectColor(color)}
        >
          {#if selectedColor === color && !canPlace}
            <div class="absolute inset-0 bg-black/50 flex items-center justify-center">
              <span class="text-white text-xs font-bold">{secondsRemaining}</span>
            </div>
            <div class="absolute bottom-0 left-0 h-1 bg-white/80" style="width: {cooldownProgress * 100}%"></div>
          {/if}
        </button>
      {/each}
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
