<script>
  export let width = 500
  export let height = 500
  export let pixels = []
  export let colors = []
  export let selectedColor = "#000000"
  export let canPlace = true
  export let secondsRemaining = 0
  export let stats = { total_pixels: 0, unique_users: 0 }
  export let live

  let hoveredPixel = null
  let pixelSize = 5
  let canvasElement
  let ctx
  let showColorPicker = false

  $: canvasWidth = width * pixelSize
  $: canvasHeight = height * pixelSize

  // Draw canvas when pixels change
  $: if (ctx && pixels) {
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

  function selectColor(color) {
    selectedColor = color
    live.pushEvent("select_color", { color })
    showColorPicker = false
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
          class="w-8 h-8 border border-gray-300 rounded-md shadow-sm hover:shadow transition-shadow"
          style="background-color: {selectedColor}"
          on:click={() => showColorPicker = !showColorPicker}
        ></button>

        {#if showColorPicker}
          <div class="absolute top-full left-0 mt-2 p-2 bg-white border border-gray-200 rounded-lg shadow-xl z-50 w-56">
            <div class="grid grid-cols-4 gap-1.5">
              {#each colors as color}
                <button
                  class="aspect-square rounded hover:scale-110 active:scale-95 transition-transform shadow-sm"
                  class:ring-2={selectedColor === color}
                  class:ring-blue-500={selectedColor === color}
                  class:ring-offset-1={selectedColor === color}
                  style="background-color: {color}"
                  on:click={() => selectColor(color)}
                ></button>
              {/each}
            </div>
          </div>
        {/if}
      </div>

      <!-- Color Palette (Desktop) -->
      <div class="hidden sm:flex items-center gap-1">
        {#each colors as color}
          <button
            class="w-7 h-7 rounded hover:scale-110 active:scale-95 transition-transform shadow-sm"
            class:ring-2={selectedColor === color}
            class:ring-blue-500={selectedColor === color}
            class:ring-offset-1={selectedColor === color}
            style="background-color: {color}"
            on:click={() => selectColor(color)}
            title={color}
          ></button>
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

    <!-- Progress Bar -->
    {#if !canPlace}
      <div class="h-0.5 bg-gray-100">
        <div
          class="h-full bg-blue-500 transition-all duration-1000"
          style="width: {((60 - secondsRemaining) / 60) * 100}%"
        ></div>
      </div>
    {/if}
  </div>

  <!-- Canvas Area (Full Screen) -->
  <div class="flex-1 overflow-auto bg-gray-50">
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
