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

<div class="fixed inset-0 flex flex-col bg-base-100">
  <!-- Compact Header with All Controls -->
  <div class="bg-base-200 border-b-2 border-base-content">
    <div class="px-3 py-2 flex flex-wrap items-center gap-3 sm:gap-4">
      <!-- Back Link -->
      <a
        href="/real-estate"
        class="btn btn-sm btn-ghost gap-1 flex-shrink-0"
        title="Back to Kruk.live"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path>
        </svg>
        <span class="hidden sm:inline">Kruk.live</span>
      </a>

      <!-- Title -->
      <h1 class="text-lg sm:text-xl font-black uppercase tracking-tight flex-shrink-0">
        Pixel<span class="text-primary">Canvas</span>
      </h1>

      <!-- Color Picker Button (Mobile) -->
      <div class="relative sm:hidden">
        <button
          class="w-10 h-10 border-2 border-base-content rounded"
          style="background-color: {selectedColor}"
          on:click={() => showColorPicker = !showColorPicker}
        ></button>

        {#if showColorPicker}
          <div class="absolute top-full left-0 mt-2 p-3 bg-base-100 border-2 border-base-content shadow-xl z-50 w-64">
            <div class="grid grid-cols-4 gap-2">
              {#each colors as color}
                <button
                  class="aspect-square border-2 hover:scale-110 active:scale-95 transition-transform"
                  class:border-primary={selectedColor === color}
                  class:border-base-300={selectedColor !== color}
                  style="background-color: {color}"
                  on:click={() => selectColor(color)}
                ></button>
              {/each}
            </div>
          </div>
        {/if}
      </div>

      <!-- Color Palette (Desktop) -->
      <div class="hidden sm:flex items-center gap-1 flex-wrap">
        {#each colors as color}
          <button
            class="w-8 h-8 border-2 hover:scale-110 active:scale-95 transition-transform"
            class:border-base-content={selectedColor === color}
            class:border-base-300={selectedColor !== color}
            class:ring-2={selectedColor === color}
            class:ring-primary={selectedColor === color}
            style="background-color: {color}"
            on:click={() => selectColor(color)}
            title={color}
          ></button>
        {/each}
      </div>

      <div class="flex-1"></div>

      <!-- Stats -->
      <div class="hidden md:flex items-center gap-3 text-xs opacity-60">
        <span>{stats.total_pixels} pixels</span>
        <span>·</span>
        <span>{stats.unique_users} artists</span>
      </div>

      <!-- Cooldown -->
      <div class="flex items-center gap-2 flex-shrink-0">
        {#if canPlace}
          <div class="px-3 py-1 bg-primary text-primary-content font-bold text-sm uppercase">
            Ready!
          </div>
        {:else}
          <div class="px-3 py-1 bg-base-300 font-bold text-sm">
            {secondsRemaining}s
          </div>
        {/if}
      </div>
    </div>

    <!-- Progress Bar -->
    {#if !canPlace}
      <div class="h-1 bg-base-300">
        <div
          class="h-full bg-primary transition-all duration-1000"
          style="width: {((60 - secondsRemaining) / 60) * 100}%"
        ></div>
      </div>
    {/if}
  </div>

  <!-- Canvas Area (Full Screen) -->
  <div class="flex-1 overflow-auto bg-base-200">
    <canvas
      use:initCanvas
      width={canvasWidth}
      height={canvasHeight}
      class="bg-white cursor-crosshair"
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
