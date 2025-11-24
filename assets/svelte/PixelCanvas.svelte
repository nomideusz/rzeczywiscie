<script>
  export let width = 500
  export let height = 500
  export let pixels = []
  export let pixelsVersion = 0
  export let colors = []
  export let selectedColor = "#1a1a1a"
  export let canPlace = true
  export let secondsRemaining = 0
  export let cooldownSeconds = 60
  export let stats = { total_pixels: 0, unique_users: 0 }
  export let cursors = []
  export let live

  let hoveredPixel = null
  let pixelSize = 5
  let canvasElement
  let canvasContainer
  let ctx
  let lastCursorSend = 0
  const CURSOR_THROTTLE_MS = 100  // Send cursor updates every 100ms max

  $: canvasWidth = width * pixelSize
  $: canvasHeight = height * pixelSize

  // Calculate responsive pixel size based on available space
  function calculatePixelSize() {
    if (!canvasContainer) return

    const containerWidth = canvasContainer.clientWidth
    const containerHeight = canvasContainer.clientHeight

    // Calculate pixel size that fits both dimensions
    const maxPixelWidth = Math.floor(containerWidth / width)
    const maxPixelHeight = Math.floor(containerHeight / height)

    // Use the smaller dimension, with a minimum of 4px for visibility
    // On small screens, allow scrolling rather than making pixels invisible
    const fittedSize = Math.min(maxPixelWidth, maxPixelHeight)
    const newPixelSize = Math.max(4, fittedSize)

    if (newPixelSize !== pixelSize) {
      pixelSize = newPixelSize
      // Redraw after size change
      if (ctx) {
        requestAnimationFrame(() => drawCanvas())
      }
    }
  }

  // Draw canvas when pixels change (using version to force reactivity)
  $: if (ctx && pixelsVersion >= 0) {
    requestAnimationFrame(() => drawCanvas())
  }

  function initCanvas(node) {
    canvasElement = node
    ctx = node.getContext('2d')
    drawCanvas()
    return {
      destroy() {}
    }
  }

  function initContainer(node) {
    canvasContainer = node

    // Calculate initial size
    calculatePixelSize()

    // Recalculate on window resize
    const resizeObserver = new ResizeObserver(() => {
      calculatePixelSize()
    })
    resizeObserver.observe(node)

    return {
      destroy() {
        resizeObserver.disconnect()
      }
    }
  }

  function drawCanvas() {
    if (!ctx) return

    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, canvasWidth, canvasHeight)

    // Lighter grid
    ctx.strokeStyle = '#F5F5F5'
    ctx.lineWidth = 1

    for (let x = 0; x <= width; x++) {
      ctx.beginPath()
      ctx.moveTo(x * pixelSize, 0)
      ctx.lineTo(x * pixelSize, canvasHeight)
      ctx.stroke()
    }

    for (let y = 0; y <= height; y++) {
      ctx.beginPath()
      ctx.moveTo(0, y * pixelSize)
      ctx.lineTo(canvasWidth, y * pixelSize)
      ctx.stroke()
    }

    // Draw pixels
    pixels.forEach(pixel => {
      ctx.fillStyle = pixel.color
      ctx.fillRect(
        pixel.x * pixelSize + 1,
        pixel.y * pixelSize + 1,
        pixelSize - 1,
        pixelSize - 1
      )
    })

    // Preview
    if (hoveredPixel && canPlace) {
      ctx.globalAlpha = 0.5
      ctx.fillStyle = selectedColor
      ctx.fillRect(
        hoveredPixel.x * pixelSize + 1,
        hoveredPixel.y * pixelSize + 1,
        pixelSize - 1,
        pixelSize - 1
      )
      ctx.globalAlpha = 1.0
    }
  }

  function getCoords(clientX, clientY) {
    const rect = canvasElement.getBoundingClientRect()
    const x = Math.floor((clientX - rect.left) / pixelSize)
    const y = Math.floor((clientY - rect.top) / pixelSize)
    return { x, y }
  }

  function handleClick(event) {
    if (!canPlace) return
    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleMove(event) {
    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      hoveredPixel = { x, y }
      drawCanvas()

      // Send cursor position (throttled)
      sendCursorPosition(x, y)
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

  // Touch support
  function handleTouchStart(event) {
    if (!canPlace || event.touches.length !== 1) return

    const touch = event.touches[0]
    const { x, y } = getCoords(touch.clientX, touch.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      // Only prevent default when actually placing a pixel
      event.preventDefault()
      hoveredPixel = { x, y }
      drawCanvas()
      live.pushEvent("place_pixel", { x, y })
    }
  }

  function handleTouchMove(event) {
    if (event.touches.length !== 1) return
    const touch = event.touches[0]
    const { x, y } = getCoords(touch.clientX, touch.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      hoveredPixel = { x, y }
      drawCanvas()

      // Send cursor position (throttled)
      sendCursorPosition(x, y)
    }
  }

  function selectColor(color) {
    selectedColor = color
    live.pushEvent("select_color", { color })
  }
</script>

<div class="fixed inset-0 flex flex-col bg-gradient-to-br from-slate-50 to-blue-50">
  <!-- Compact Header - Everything in One Row -->
  <div class="bg-white/90 backdrop-blur-xl border-b border-gray-200/50 shadow-sm">
    <div class="px-2 sm:px-3 py-1.5 flex items-center gap-1.5 sm:gap-3">
      <!-- Back Button -->
      <a
        href="/real-estate"
        class="p-1 hover:bg-gray-100 rounded-lg transition-colors flex-shrink-0"
        title="Back to Kruk.live"
      >
        <svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
        </svg>
      </a>

      <!-- Title -->
      <h1 class="text-sm font-bold text-gray-900 flex-shrink-0 hidden sm:block">Pixel Canvas</h1>

      <!-- Color Palette -->
      <div class="flex items-center gap-1 overflow-x-auto scrollbar-hide flex-1 px-1 py-1">
        {#each colors as color}
          <button
            class="w-7 h-7 rounded-lg flex-shrink-0 transition-all duration-200 relative"
            class:ring-2={selectedColor === color}
            class:ring-offset-1={selectedColor === color}
            class:scale-105={selectedColor === color}
            style="background-color: {color}; {selectedColor === color ? `box-shadow: 0 0 0 2px white, 0 0 0 4px ${color};` : ''}"
            on:click={() => selectColor(color)}
            title={color.toUpperCase()}
          >
            {#if selectedColor === color}
              <div class="absolute inset-0 flex items-center justify-center">
                <svg class="w-3.5 h-3.5 text-white drop-shadow-lg" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                </svg>
              </div>
            {/if}
          </button>
        {/each}
      </div>

      <!-- Stats (Desktop only) -->
      <div class="hidden lg:flex items-center gap-1.5 text-xs text-gray-500 flex-shrink-0">
        <span>{stats.total_pixels.toLocaleString()}</span>
        <span class="text-gray-300">·</span>
        <span>{stats.unique_users}</span>
      </div>

      <!-- Cooldown Status -->
      <div class="flex-shrink-0">
        {#if canPlace}
          <div class="flex items-center gap-1 px-2 py-1 bg-gradient-to-r from-green-500 to-emerald-500 text-white font-semibold text-xs rounded-full">
            <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
            </svg>
            <span class="hidden sm:inline">Go</span>
          </div>
        {:else}
          <div class="flex items-center gap-1 px-2 py-1 bg-gray-100 text-gray-700 font-semibold text-xs rounded-full border border-gray-200">
            <span>{secondsRemaining}s</span>
          </div>
        {/if}
      </div>
    </div>

    <!-- Cooldown Progress Bar -->
    {#if !canPlace}
      <div class="h-0.5 bg-gray-100 relative overflow-hidden">
        <div
          class="h-full bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500 transition-all duration-1000 ease-linear"
          style="width: {((cooldownSeconds - secondsRemaining) / cooldownSeconds) * 100}%"
        ></div>
      </div>
    {/if}
  </div>

  <!-- Canvas Area (Full Screen) -->
  <div class="flex-1 overflow-auto relative" use:initContainer>
    <div class="relative inline-block">
      <canvas
        use:initCanvas
        width={canvasWidth}
        height={canvasHeight}
        class="bg-white cursor-crosshair shadow-sm"
        class:cursor-not-allowed={!canPlace}
        on:click={handleClick}
        on:mousemove={handleMove}
        on:mouseleave={handleLeave}
        on:touchstart={handleTouchStart}
        on:touchmove={handleTouchMove}
        on:touchend={handleLeave}
      ></canvas>

      <!-- Live Cursors Overlay -->
      {#each cursors as cursor (cursor.id)}
        <div
          class="absolute pointer-events-none transition-all duration-75"
          style="left: {cursor.x * pixelSize}px; top: {cursor.y * pixelSize}px; transform: translate(-50%, -50%);"
        >
          <!-- Cursor dot -->
          <div
            class="w-3 h-3 rounded-full border-2 border-white shadow-lg"
            style="background-color: {cursor.color}"
          ></div>
          <!-- User ID label -->
          <div
            class="absolute top-4 left-1/2 -translate-x-1/2 px-1.5 py-0.5 bg-gray-900 text-white text-xs rounded whitespace-nowrap shadow-lg"
            style="font-size: 10px;"
          >
            {cursor.id}
          </div>
        </div>
      {/each}
    </div>
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

  /* Hide scrollbar for color palette */
  .scrollbar-hide {
    -ms-overflow-style: none;  /* IE and Edge */
    scrollbar-width: none;  /* Firefox */
  }

  .scrollbar-hide::-webkit-scrollbar {
    display: none;  /* Chrome, Safari and Opera */
  }
</style>
