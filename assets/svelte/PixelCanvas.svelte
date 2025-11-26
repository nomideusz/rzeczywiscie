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
  let showHelp = false
  const CURSOR_THROTTLE_MS = 250

  // Pan/drag state
  let isPanning = false
  let panStart = { x: 0, y: 0 }
  let scrollStart = { x: 0, y: 0 }

  function centerCanvas() {
    if (!scrollContainer) return
    const sw = scrollContainer.scrollWidth
    const sh = scrollContainer.scrollHeight
    const cw = scrollContainer.clientWidth
    const ch = scrollContainer.clientHeight
    scrollContainer.scrollLeft = (sw - cw) / 2
    scrollContainer.scrollTop = (sh - ch) / 2
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
  })

  $: cooldownProgress = canPlace ? 1 : (cooldownSeconds - secondsRemaining) / cooldownSeconds

  function calculatePixelSize() {
    if (!canvasContainer) return
    const padding = 32
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

  $: if (ctx && pixelsVersion >= 0) drawCanvas()

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

    // Pixels
    const inset = Math.max(1, Math.round(effectivePixelSize * 0.06))
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
    return {
      x: Math.floor((clientX - rect.left) / effectivePixelSize),
      y: Math.floor((clientY - rect.top) / effectivePixelSize)
    }
  }

  function handleMouseDown(e) {
    if (e.button === 1) {
      e.preventDefault()
      startPan(e.clientX, e.clientY)
    }
  }

  function handleMouseUp() {
    if (isPanning) isPanning = false
  }

  function handleClick(e) {
    if (isPanning || !canPlace) return
    const { x, y } = getCoords(e.clientX, e.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleMove(e) {
    if (isPanning) {
      doPan(e.clientX, e.clientY)
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

  function startPan(clientX, clientY) {
    isPanning = true
    panStart = { x: clientX, y: clientY }
    if (scrollContainer) {
      scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
    }
  }

  function doPan(clientX, clientY) {
    if (!scrollContainer) return
    scrollContainer.scrollLeft = scrollStart.x + (panStart.x - clientX)
    scrollContainer.scrollTop = scrollStart.y + (panStart.y - clientY)
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
      if (scrollContainer) scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
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
      if (touchPanStart && scrollContainer) {
        scrollContainer.scrollLeft = scrollStart.x + (touchPanStart.x - centerX)
        scrollContainer.scrollTop = scrollStart.y + (touchPanStart.y - centerY)
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
    showPalette = false
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
  }

  function handleClickOutside(e) {
    if (showPalette && !e.target.closest('.palette-container')) showPalette = false
  }
</script>

<svelte:window on:keydown={handleKeyDown} on:mouseup={handleMouseUp} on:click={handleClickOutside} />

<div class="min-h-screen bg-base-200 flex flex-col">
  <!-- Header -->
  <div class="bg-base-100 border-b-4 border-base-content flex-shrink-0 z-20">
    <div class="container mx-auto px-4 py-3">
      <div class="flex items-center justify-between gap-4">
        <div class="flex items-center gap-4">
          <div>
            <h1 class="text-lg md:text-xl font-black uppercase tracking-tight">Pixel Canvas</h1>
            <p class="text-[10px] font-bold uppercase tracking-wide opacity-60 hidden sm:block">Collaborative pixel art</p>
          </div>
          
          <!-- Stats -->
          <div class="hidden md:flex items-center gap-1 border-2 border-base-content">
            <div class="px-3 py-1.5 border-r border-base-content/30">
              <span class="font-black text-primary">{stats.total_pixels.toLocaleString()}</span>
              <span class="text-[10px] font-bold uppercase opacity-50 ml-1">pixels</span>
            </div>
            <div class="px-3 py-1.5">
              <span class="font-black text-secondary">{stats.unique_users}</span>
              <span class="text-[10px] font-bold uppercase opacity-50 ml-1">artists</span>
            </div>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <!-- Zoom Controls -->
          <div class="hidden sm:flex items-center border-2 border-base-content">
            <button class="w-8 h-8 text-sm font-bold hover:bg-base-200 transition-colors cursor-pointer" onclick={() => adjustZoom(-0.25)}>−</button>
            <span class="w-12 text-center text-xs font-bold">{Math.round(zoom * 100)}%</span>
            <button class="w-8 h-8 text-sm font-bold hover:bg-base-200 transition-colors cursor-pointer border-l border-base-content/30" onclick={() => adjustZoom(0.25)}>+</button>
          </div>

          <button
            class="px-3 py-1.5 text-xs font-bold uppercase tracking-wide border-2 border-base-content hover:bg-base-200 transition-colors cursor-pointer"
            onclick={() => showHelp = !showHelp}
          >
            ?
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Canvas Area -->
  <div 
    class="flex-1 overflow-auto relative"
    use:initScrollContainer
    use:initContainer
  >
    <div class="flex items-center justify-center min-h-full p-4" style="min-width: max-content;">
      <div class="border-2 border-base-content bg-base-100 p-1">
        <canvas
          use:initCanvas
          class="bg-white block {isPanning ? 'cursor-grabbing' : 'cursor-crosshair'}"
          on:mousedown={handleMouseDown}
          on:click={handleClick}
          on:mousemove={handleMove}
          on:mouseleave={handleLeave}
          on:touchstart={handleTouchStart}
          on:touchmove={handleTouchMove}
          on:touchend={handleTouchEnd}
          on:contextmenu|preventDefault
        ></canvas>
      </div>
    </div>

    <!-- Live Cursors -->
    {#each cursors as cursor (cursor.id)}
      <div
        class="absolute pointer-events-none transition-all duration-100"
        style="left: calc(50% + {(cursor.x - width/2) * pixelSize * zoom}px); top: calc(50% + {(cursor.y - height/2) * pixelSize * zoom}px);"
      >
        <div class="w-2 h-2 border border-white" style="background-color: {cursor.color}"></div>
      </div>
    {/each}
  </div>

  <!-- Bottom Toolbar -->
  <div class="bg-base-100 border-t-4 border-base-content flex-shrink-0">
    <div class="container mx-auto px-4 py-3">
      <div class="flex items-center justify-between gap-4">
        <!-- Color Picker -->
        <div class="palette-container relative flex items-center gap-3">
          <!-- Current color with cooldown -->
          <button
            class="w-12 h-12 border-2 border-base-content cursor-pointer relative overflow-hidden flex-shrink-0"
            style="background-color: {selectedColor};"
            onclick={() => showPalette = !showPalette}
          >
            {#if !canPlace}
              <div class="absolute inset-0 bg-black/30 flex items-center justify-center">
                <span class="text-white text-sm font-black drop-shadow">{secondsRemaining}</span>
              </div>
            {/if}
            <!-- Cooldown border -->
            <div 
              class="absolute bottom-0 left-0 h-1 bg-white/50 transition-all duration-1000"
              style="width: {cooldownProgress * 100}%"
            ></div>
          </button>

          <!-- Expanded palette -->
          {#if showPalette}
            <div class="absolute bottom-16 left-0 bg-base-100 border-2 border-base-content p-2 z-50">
              <div class="grid grid-cols-5 gap-1" style="width: 180px;">
                {#each colors as color, i}
                  <button
                    class="w-8 h-8 cursor-pointer relative {selectedColor === color ? 'ring-2 ring-base-content ring-offset-1' : 'hover:scale-110'} transition-all"
                    style="background-color: {color};"
                    onclick={() => selectColor(color)}
                  >
                    {#if i < 10 && !isMobile}
                      <span class="absolute -top-1 -right-1 w-3.5 h-3.5 bg-base-content text-base-100 text-[8px] font-bold flex items-center justify-center opacity-0 hover:opacity-100 transition-opacity">
                        {i < 9 ? i + 1 : 0}
                      </span>
                    {/if}
                  </button>
                {/each}
              </div>
              {#if !isMobile}
                <p class="text-[9px] font-bold uppercase tracking-wide opacity-40 mt-2 text-center">Keys 1-0</p>
              {/if}
            </div>
          {/if}

          <!-- Color strip (desktop) -->
          <div class="hidden md:flex border-2 border-base-content">
            {#each colors.slice(0, 10) as color, i}
              <button
                class="w-7 h-7 cursor-pointer transition-all {selectedColor === color ? 'scale-110 z-10 ring-1 ring-base-content' : 'hover:scale-105'}"
                style="background-color: {color};"
                onclick={() => selectColor(color)}
              ></button>
            {/each}
          </div>
        </div>

        <!-- Mobile Stats -->
        <div class="md:hidden flex items-center gap-2 text-xs">
          <span class="font-black text-primary">{stats.total_pixels.toLocaleString()}</span>
          <span class="opacity-50">pixels</span>
        </div>

        <!-- Coordinates & Zoom (mobile) -->
        <div class="flex items-center gap-2">
          {#if hoveredPixel}
            <div class="hidden sm:block px-2 py-1 bg-base-content text-base-100 text-xs font-mono font-bold">
              {hoveredPixel.x},{hoveredPixel.y}
            </div>
          {/if}

          <!-- Mobile zoom -->
          <div class="sm:hidden flex items-center border-2 border-base-content">
            <button class="w-8 h-8 text-sm font-bold active:bg-base-200 cursor-pointer" onclick={() => adjustZoom(-0.25)}>−</button>
            <button class="w-8 h-8 text-sm font-bold active:bg-base-200 cursor-pointer border-l border-base-content/30" onclick={() => adjustZoom(0.25)}>+</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- Help Modal -->
{#if showHelp}
  <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onclick={() => showHelp = false}>
    <div class="bg-base-100 border-2 border-base-content max-w-sm w-full" onclick={(e) => e.stopPropagation()}>
      <div class="px-4 py-3 border-b-2 border-base-content bg-base-200 flex items-center justify-between">
        <span class="text-sm font-bold uppercase tracking-wide">How to Play</span>
        <button class="text-lg opacity-50 hover:opacity-100 cursor-pointer" onclick={() => showHelp = false}>✕</button>
      </div>
      <div class="p-4 space-y-3 text-sm">
        <div class="flex items-start gap-3">
          <span class="text-lg">🎨</span>
          <div>
            <div class="font-bold">Place Pixels</div>
            <div class="text-xs opacity-60">Click/tap any square to place a pixel in your selected color</div>
          </div>
        </div>
        <div class="flex items-start gap-3">
          <span class="text-lg">⏱️</span>
          <div>
            <div class="font-bold">Cooldown</div>
            <div class="text-xs opacity-60">{cooldownSeconds} second wait between placements</div>
          </div>
        </div>
        <div class="flex items-start gap-3">
          <span class="text-lg">🔍</span>
          <div>
            <div class="font-bold">Navigate</div>
            <div class="text-xs opacity-60">Scroll to pan, pinch or use +/- to zoom</div>
          </div>
        </div>
        {#if !isMobile}
          <div class="flex items-start gap-3">
            <span class="text-lg">⌨️</span>
            <div>
              <div class="font-bold">Keyboard</div>
              <div class="text-xs opacity-60">Press 1-0 to quickly select colors</div>
            </div>
          </div>
        {/if}
        <div class="flex items-start gap-3">
          <span class="text-lg">👥</span>
          <div>
            <div class="font-bold">Collaborate</div>
            <div class="text-xs opacity-60">See other artists' cursors in real-time</div>
          </div>
        </div>
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
