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
  const CURSOR_THROTTLE_MS = 250

  // Pan state
  let isPanning = false
  let panStart = { x: 0, y: 0 }
  let scrollStart = { x: 0, y: 0 }

  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
    // Calculate optimal zoom to fill container
    setTimeout(() => {
      if (canvasWrapper) {
        const wrapperWidth = canvasWrapper.clientWidth - 32
        const wrapperHeight = canvasWrapper.clientHeight - 32
        const optimalZoomX = wrapperWidth / (width * pixelSize)
        const optimalZoomY = wrapperHeight / (height * pixelSize)
        zoom = Math.min(optimalZoomX, optimalZoomY, 2.5)
        zoom = Math.max(0.8, zoom)
        drawCanvas()
      }
    }, 50)
    
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

    // Grid - always visible
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

  // Touch handling - single finger pans, tap places, two fingers zoom
  let lastTouchDistance = 0
  let singleTouchStart = null
  let touchMoved = false
  let scrollElement = null
  const TAP_THRESHOLD = 15

  function getScrollElement() {
    if (!scrollElement && canvasWrapper) {
      scrollElement = canvasWrapper.querySelector('.overflow-auto')
    }
    return scrollElement
  }

  function handleTouchStart(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      singleTouchStart = null
      touchMoved = true
      const t1 = e.touches[0], t2 = e.touches[1]
      lastTouchDistance = Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY)
    } else if (e.touches.length === 1) {
      const t = e.touches[0]
      const scroll = getScrollElement()
      singleTouchStart = { 
        clientX: t.clientX, 
        clientY: t.clientY,
        scrollLeft: scroll ? scroll.scrollLeft : 0,
        scrollTop: scroll ? scroll.scrollTop : 0
      }
      touchMoved = false
    }
  }

  function handleTouchMove(e) {
    if (e.touches.length === 2) {
      e.preventDefault()
      const t1 = e.touches[0], t2 = e.touches[1]
      const distance = Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY)
      if (lastTouchDistance > 0) {
        const scale = distance / lastTouchDistance
        if (Math.abs(scale - 1) > 0.015) {
          zoom = Math.max(0.5, Math.min(3, zoom * scale))
          drawCanvas()
          lastTouchDistance = distance
        }
      }
    } else if (e.touches.length === 1 && singleTouchStart) {
      const t = e.touches[0]
      const dx = t.clientX - singleTouchStart.clientX
      const dy = t.clientY - singleTouchStart.clientY
      
      if (Math.hypot(dx, dy) > TAP_THRESHOLD) {
        touchMoved = true
        // Pan the scroll container
        const scroll = getScrollElement()
        if (scroll) {
          scroll.scrollLeft = singleTouchStart.scrollLeft - dx
          scroll.scrollTop = singleTouchStart.scrollTop - dy
        }
      }
    }
  }

  function handleTouchEnd(e) {
    // Only place pixel on tap (not drag)
    if (singleTouchStart && !touchMoved && canPlace) {
      const { x, y } = getCoords(singleTouchStart.clientX, singleTouchStart.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        live.pushEvent("place_pixel", { x, y })
      }
    }
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
    if (e.key === '+' || e.key === '=') adjustZoom(0.25)
    if (e.key === '-') adjustZoom(-0.25)
  }
</script>

<svelte:window onkeydown={handleKeyDown} onmouseup={handleMouseUp} />

<div class="flex flex-col bg-base-200 overflow-hidden" style="height: calc(100vh - 8rem);">
  <!-- Canvas area - no page scroll needed -->
  <div 
    class="flex-1 min-h-0 overflow-auto bg-neutral-100 relative"
    style="scrollbar-width: thin;"
    use:initWrapper
  >
    <div class="inline-block p-4">
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
    <div class="absolute bottom-3 right-3 flex items-center gap-0.5 bg-base-100/90 backdrop-blur border border-base-content/20 rounded p-0.5 z-10">
      <button class="w-7 h-7 text-sm font-bold hover:bg-base-200 rounded cursor-pointer" onclick={() => adjustZoom(-0.25)}>−</button>
      <span class="w-10 text-center text-[10px] font-bold opacity-60">{Math.round(zoom * 100)}%</span>
      <button class="w-7 h-7 text-sm font-bold hover:bg-base-200 rounded cursor-pointer" onclick={() => adjustZoom(0.25)}>+</button>
    </div>

    <!-- Coordinates + stats -->
    <div class="absolute top-3 left-3 flex items-center gap-2 text-[10px] font-bold opacity-50 z-10">
      <span>{stats.total_pixels.toLocaleString()} px</span>
      <span>•</span>
      <span>{stats.unique_users} artists</span>
      {#if hoveredPixel}
        <span>•</span>
        <span class="font-mono">[{hoveredPixel.x},{hoveredPixel.y}]</span>
      {/if}
    </div>
  </div>

  <!-- Bottom bar - color picker with timer -->
  <div class="flex items-center justify-center gap-1 px-2 py-2 bg-base-100 border-t border-base-content/10">
    {#each colors as color}
      <button
        class="relative w-8 h-8 sm:w-9 sm:h-9 border-2 cursor-pointer transition-all {selectedColor === color ? 'border-base-content scale-105' : 'border-transparent hover:border-base-content/30'}"
        style="background-color: {color};"
        onclick={() => selectColor(color)}
      >
        {#if selectedColor === color && !canPlace}
          <div class="absolute inset-0 bg-black/40 flex items-center justify-center">
            <span class="text-white text-[10px] font-black">{secondsRemaining}</span>
          </div>
          <div class="absolute bottom-0 left-0 right-0 h-0.5 bg-white/70" style="width: {cooldownProgress * 100}%"></div>
        {/if}
      </button>
    {/each}
  </div>
</div>

<style>
  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
    touch-action: none;
  }
</style>
