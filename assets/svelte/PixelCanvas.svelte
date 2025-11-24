<script>
  export let width = 500
  export let height = 500
  export let pixels = []
  export let pixelsVersion = 0
  export let colors = []
  export let selectedColor = "#1a1a1a"
  export let canPlace = true
  export let secondsRemaining = 0
  export let stats = { total_pixels: 0, unique_users: 0 }
  export let live

  let hoveredPixel = null
  let pixelSize = 5
  let canvasElement
  let canvasContainer
  let ctx
  let showColorPicker = false

  $: canvasWidth = width * pixelSize
  $: canvasHeight = height * pixelSize

  // Calculate responsive pixel size based on available space
  function calculatePixelSize() {
    if (!canvasContainer) return

    const containerWidth = canvasContainer.clientWidth
    const containerHeight = canvasContainer.clientHeight

    // Calculate pixel size that fits both dimensions with some padding
    const maxPixelWidth = Math.floor(containerWidth / width)
    const maxPixelHeight = Math.floor(containerHeight / height)

    // Use the smaller dimension to ensure it fits
    const newPixelSize = Math.max(1, Math.min(maxPixelWidth, maxPixelHeight))

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
    }
  }

  function handleLeave() {
    hoveredPixel = null
    drawCanvas()
  }

  // Touch support
  function handleTouch(event) {
    event.preventDefault()
    if (!canPlace || event.touches.length !== 1) return

    const touch = event.touches[0]
    const { x, y } = getCoords(touch.clientX, touch.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
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
    }
  }

  function selectColor(color, event) {
    if (event) {
      event.stopPropagation()
      event.preventDefault()
    }
    selectedColor = color
    live.pushEvent("select_color", { color })
    showColorPicker = false
  }

  function handleColorPickerClick(event) {
    // Prevent clicks inside the color picker from closing it
    event.stopPropagation()
  }
</script>

<div class="fixed inset-0 flex flex-col bg-white">
  <!-- Minimal Header -->
  <div class="bg-white border-b border-gray-200 shadow-sm">
    <div class="px-3 py-2.5 flex flex-wrap items-center gap-2 sm:gap-3 max-w-screen-2xl mx-auto">
      <!-- Back Link -->
      <a
        href="/real-estate"
        class="flex items-center gap-1 text-sm text-gray-600 hover:text-gray-900 transition-colors flex-shrink-0"
        title="Back to Kruk.live"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
        </svg>
        <span class="hidden sm:inline font-medium">Kruk.live</span>
      </a>

      <!-- Divider -->
      <div class="h-4 w-px bg-gray-300 hidden sm:block"></div>

      <!-- Title -->
      <h1 class="text-sm font-semibold text-gray-800 flex-shrink-0">
        Pixel Canvas
      </h1>

      <!-- Color Picker Button (Mobile) -->
      <div class="relative sm:hidden">
        <button
          class="w-9 h-9 rounded-lg border-2 border-gray-200 shadow-sm hover:shadow-md transition-all hover:scale-105 active:scale-95 relative group"
          style="background-color: {selectedColor}"
          on:click={() => showColorPicker = !showColorPicker}
        >
          <div class="absolute inset-0 rounded-lg ring-2 ring-blue-400 opacity-0 group-hover:opacity-100 transition-opacity"></div>
        </button>

        {#if showColorPicker}
          <div
            class="absolute top-full left-0 mt-2 p-3 bg-white border border-gray-200 rounded-xl shadow-2xl z-50 w-64 backdrop-blur-sm"
            on:click={handleColorPickerClick}
            on:touchstart={handleColorPickerClick}
          >
            <div class="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Pick a color</div>
            <div class="grid grid-cols-4 gap-2">
              {#each colors as color}
                <button
                  class="aspect-square rounded-lg hover:scale-110 active:scale-95 transition-all relative group shadow-sm hover:shadow-md"
                  class:ring-2={selectedColor === color}
                  class:ring-blue-500={selectedColor === color}
                  class:ring-offset-2={selectedColor === color}
                  style="background-color: {color}"
                  on:click={(e) => selectColor(color, e)}
                  on:touchend={(e) => selectColor(color, e)}
                >
                  {#if selectedColor === color}
                    <div class="absolute inset-0 flex items-center justify-center">
                      <svg class="w-4 h-4 text-white drop-shadow-lg" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                      </svg>
                    </div>
                  {/if}
                </button>
              {/each}
            </div>
            <div class="mt-3 pt-3 border-t border-gray-100">
              <div class="flex items-center gap-2">
                <div class="w-10 h-10 rounded-lg border-2 border-gray-200 shadow-inner" style="background-color: {selectedColor}"></div>
                <div class="flex-1">
                  <div class="text-xs text-gray-500 font-medium">Selected</div>
                  <div class="text-xs font-mono text-gray-700">{selectedColor.toUpperCase()}</div>
                </div>
              </div>
            </div>
          </div>
        {/if}
      </div>

      <!-- Color Palette (Desktop) -->
      <div class="hidden sm:flex items-center gap-1.5 px-2 py-1 bg-gray-50 rounded-lg border border-gray-200">
        {#each colors as color}
          <button
            class="w-7 h-7 rounded-md hover:scale-110 active:scale-95 transition-all relative group shadow-sm hover:shadow-md"
            class:ring-2={selectedColor === color}
            class:ring-blue-500={selectedColor === color}
            class:ring-offset-2={selectedColor === color}
            style="background-color: {color}"
            on:click={(e) => selectColor(color, e)}
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

      <div class="flex-1"></div>

      <!-- Stats -->
      <div class="hidden md:flex items-center gap-2 text-xs text-gray-500">
        <span>{stats.total_pixels.toLocaleString()}</span>
        <span>pixels</span>
        <span class="text-gray-300">·</span>
        <span>{stats.unique_users.toLocaleString()}</span>
        <span>artists</span>
      </div>

      <!-- Cooldown -->
      <div class="flex items-center gap-2 flex-shrink-0">
        {#if canPlace}
          <div class="px-2.5 py-1 bg-green-500 text-white font-medium text-xs rounded-md shadow-sm">
            Ready
          </div>
        {:else}
          <div class="px-2.5 py-1 bg-gray-100 text-gray-700 font-medium text-xs rounded-md border border-gray-200">
            {secondsRemaining}s
          </div>
        {/if}
      </div>
    </div>

    <!-- Cooldown Progress Bar -->
    {#if !canPlace}
      <div class="h-1 bg-gray-100 relative overflow-hidden">
        <div
          class="h-full bg-gradient-to-r from-orange-400 to-amber-500 transition-all duration-1000 ease-linear"
          style="width: {((60 - secondsRemaining) / 60) * 100}%"
        ></div>
      </div>
    {/if}
  </div>

  <!-- Canvas Area (Full Screen) -->
  <div class="flex-1 overflow-hidden bg-gray-50 flex items-center justify-center" use:initContainer>
    <canvas
      use:initCanvas
      width={canvasWidth}
      height={canvasHeight}
      class="bg-white cursor-crosshair shadow-sm"
      class:cursor-not-allowed={!canPlace}
      on:click={handleClick}
      on:mousemove={handleMove}
      on:mouseleave={handleLeave}
      on:touchstart={handleTouch}
      on:touchmove={handleTouchMove}
      on:touchend={handleLeave}
    ></canvas>
  </div>
</div>

<!-- Close color picker when clicking outside -->
{#if showColorPicker}
  <div
    class="fixed inset-0 z-40"
    on:click={() => showColorPicker = false}
    on:touchend|preventDefault={() => showColorPicker = false}
  ></div>
{/if}

<style>
  :global(body) {
    overflow: hidden;
  }

  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
  }
</style>
