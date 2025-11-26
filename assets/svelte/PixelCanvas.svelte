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
  let canvasWrapper
  let ctx
  let lastCursorSend = 0
  let zoom = 1
  let isMobile = false
  let showHelp = false
  const CURSOR_THROTTLE_MS = 250

  // Pan state
  let isPanning = false
  let panStart = { x: 0, y: 0 }
  let scrollStart = { x: 0, y: 0 }

  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
    // Calculate optimal zoom to fill container
    if (canvasWrapper) {
      const wrapperWidth = canvasWrapper.clientWidth - 32
      const wrapperHeight = canvasWrapper.clientHeight - 32
      const optimalZoomX = wrapperWidth / (width * pixelSize)
      const optimalZoomY = wrapperHeight / (height * pixelSize)
      zoom = Math.min(optimalZoomX, optimalZoomY, 2)
      zoom = Math.max(0.5, zoom)
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

  function initWrapper(node) {
    canvasWrapper = node
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

    // Grid (subtle)
    if (zoom >= 0.8) {
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.04)'
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
    if (hoveredPixel && canPlace && !isPanning) {
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

  function handleMouseDown(e) {
    if (e.button === 1) {
      e.preventDefault()
      isPanning = true
      panStart = { x: e.clientX, y: e.clientY }
      if (canvasWrapper) {
        scrollStart = { x: canvasWrapper.scrollLeft, y: canvasWrapper.scrollTop }
      }
    }
  }

  function handleMouseUp() {
    isPanning = false
  }

  function handleClick(e) {
    if (isPanning || !canPlace) return
    const { x, y } = getCoords(e.clientX, e.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleMove(e) {
    if (isPanning && canvasWrapper) {
      canvasWrapper.scrollLeft = scrollStart.x + (panStart.x - e.clientX)
      canvasWrapper.scrollTop = scrollStart.y + (panStart.y - e.clientY)
      return
    }
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
    isPanning = false
    drawCanvas()
  }

  // Touch handling
  let lastTouchDistance = 0
  let touchPanStart = null
  let singleTouchStart = null
  let touchMoved = false
  const TAP_THRESHOLD = 10

  function handleTouchStart(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      singleTouchStart = null
      touchMoved = true
      const t1 = e.touches[0], t2 = e.touches[1]
      touchPanStart = { x: (t1.clientX + t2.clientX) / 2, y: (t1.clientY + t2.clientY) / 2 }
      if (canvasWrapper) scrollStart = { x: canvasWrapper.scrollLeft, y: canvasWrapper.scrollTop }
      lastTouchDistance = Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY)
    } else if (e.touches.length === 1) {
      const t = e.touches[0]
      singleTouchStart = { clientX: t.clientX, clientY: t.clientY }
      touchMoved = false
      const { x, y } = getCoords(t.clientX, t.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        hoveredPixel = { x, y }
        drawCanvas()
      }
    }
  }

  function handleTouchMove(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      const t1 = e.touches[0], t2 = e.touches[1]
      const centerX = (t1.clientX + t2.clientX) / 2
      const centerY = (t1.clientY + t2.clientY) / 2
      if (touchPanStart && canvasWrapper) {
        canvasWrapper.scrollLeft = scrollStart.x + (touchPanStart.x - centerX)
        canvasWrapper.scrollTop = scrollStart.y + (touchPanStart.y - centerY)
      }
      const distance = Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY)
      if (lastTouchDistance > 0) {
        const scale = distance / lastTouchDistance
        if (Math.abs(scale - 1) > 0.02) {
          zoom = Math.max(0.5, Math.min(3, zoom * scale))
          drawCanvas()
          lastTouchDistance = distance
        }
      }
    } else if (e.touches.length === 1) {
      const t = e.touches[0]
      if (singleTouchStart) {
        const dx = t.clientX - singleTouchStart.clientX
        const dy = t.clientY - singleTouchStart.clientY
        if (Math.hypot(dx, dy) > TAP_THRESHOLD) touchMoved = true
      }
      const { x, y } = getCoords(t.clientX, t.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
          hoveredPixel = { x, y }
          drawCanvas()
          sendCursorPosition(x, y)
        }
      }
    }
  }

  function handleTouchEnd() {
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
  }

  function adjustZoom(delta) {
    zoom = Math.max(0.5, Math.min(3, zoom + delta))
    drawCanvas()
  }

  function handleKeyDown(e) {
    if (e.key >= '1' && e.key <= '9') {
      const idx = parseInt(e.key) - 1
      if (colors[idx]) selectColor(colors[idx])
    }
    if (e.key === '0' && colors[9]) selectColor(colors[9])
    if (e.key === 'Escape') showHelp = false
    if (e.key === '+' || e.key === '=') adjustZoom(0.25)
    if (e.key === '-') adjustZoom(-0.25)
  }
</script>

<svelte:window onkeydown={handleKeyDown} onmouseup={handleMouseUp} />

<div class="flex flex-col" style="height: calc(100vh - 10rem);">
  <!-- Canvas fills available space -->
  <div 
    class="flex-1 overflow-auto bg-neutral-100 relative"
    use:initWrapper
  >
    <div class="min-h-full min-w-full flex items-center justify-center p-4">
      <canvas
        use:initCanvas
        class="bg-white shadow-lg {isPanning ? 'cursor-grabbing' : 'cursor-crosshair'}"
        onmousedown={handleMouseDown}
        onclick={handleClick}
        onmousemove={handleMove}
        onmouseleave={handleLeave}
        ontouchstart={handleTouchStart}
        ontouchmove={handleTouchMove}
        ontouchend={handleTouchEnd}
        oncontextmenu={(e) => e.preventDefault()}
      ></canvas>
    </div>

    <!-- Live Cursors -->
    {#each cursors as cursor (cursor.id)}
      <div
        class="absolute pointer-events-none"
        style="left: calc(50% + {(cursor.x - width/2) * pixelSize * zoom}px); top: calc(50% + {(cursor.y - height/2) * pixelSize * zoom}px);"
      >
        <div class="w-2 h-2 rounded-full" style="background-color: {cursor.color}; box-shadow: 0 0 4px {cursor.color};"></div>
      </div>
    {/each}

    <!-- Floating zoom controls -->
    <div class="absolute bottom-4 right-4 flex items-center gap-1 bg-base-100/90 backdrop-blur border border-base-content/20 rounded-lg p-1">
      <button class="w-8 h-8 text-lg font-bold hover:bg-base-200 rounded cursor-pointer" onclick={() => adjustZoom(-0.25)}>−</button>
      <span class="w-12 text-center text-xs font-bold opacity-60">{Math.round(zoom * 100)}%</span>
      <button class="w-8 h-8 text-lg font-bold hover:bg-base-200 rounded cursor-pointer" onclick={() => adjustZoom(0.25)}>+</button>
    </div>

    <!-- Coordinates -->
    {#if hoveredPixel}
      <div class="absolute top-4 right-4 px-2 py-1 bg-base-content/80 text-base-100 font-mono text-xs rounded">
        {hoveredPixel.x}, {hoveredPixel.y}
      </div>
    {/if}
  </div>

  <!-- Bottom bar - minimal -->
  <div class="flex items-center justify-between gap-4 px-4 py-3 bg-base-100 border-t border-base-content/10">
    <!-- Color palette -->
    <div class="flex items-center gap-1">
      {#each colors as color}
        <button
          class="w-7 h-7 rounded cursor-pointer transition-transform {selectedColor === color ? 'scale-110 shadow-md' : 'hover:scale-105'}"
          style="background-color: {color};"
          onclick={() => selectColor(color)}
        ></button>
      {/each}
    </div>

    <!-- Stats + cooldown -->
    <div class="flex items-center gap-4">
      <div class="text-xs opacity-50">
        <span class="font-bold text-base-content">{stats.total_pixels.toLocaleString()}</span> pixels
        <span class="mx-2">•</span>
        <span class="font-bold text-base-content">{stats.unique_users}</span> artists
      </div>
      
      {#if !canPlace}
        <div class="flex items-center gap-2">
          <div class="w-20 h-1.5 bg-base-200 rounded-full overflow-hidden">
            <div class="h-full bg-primary transition-all duration-1000" style="width: {cooldownProgress * 100}%"></div>
          </div>
          <span class="text-xs font-bold opacity-50">{secondsRemaining}s</span>
        </div>
      {/if}

      <button
        class="text-xs opacity-40 hover:opacity-100 cursor-pointer"
        onclick={() => showHelp = !showHelp}
      >Help</button>
    </div>
  </div>
</div>

<!-- Help Modal -->
{#if showHelp}
  <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onclick={() => showHelp = false}>
    <div class="bg-base-100 rounded-lg max-w-xs w-full shadow-2xl" onclick={(e) => e.stopPropagation()}>
      <div class="px-4 py-3 border-b border-base-content/10 flex items-center justify-between">
        <span class="font-bold">How to Play</span>
        <button class="opacity-40 hover:opacity-100 cursor-pointer" onclick={() => showHelp = false}>✕</button>
      </div>
      <div class="p-4 space-y-2 text-sm">
        <p><strong>Click</strong> to place a pixel</p>
        <p><strong>Scroll</strong> to pan around</p>
        <p><strong>+/−</strong> or pinch to zoom</p>
        <p><strong>1-0</strong> keys for quick color select</p>
        <p class="text-xs opacity-50 pt-2">{cooldownSeconds}s cooldown between placements</p>
      </div>
    </div>
  </div>
{/if}

<style>
  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
    touch-action: none;
  }
</style>
