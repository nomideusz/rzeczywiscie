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
  let pixelSize = 5 // Smaller pixels for more detail
  let canvasElement
  let ctx
  let showControls = false

  // Reactive canvas dimensions
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
  }

  function drawCanvas() {
    if (!ctx) return

    // Clear canvas
    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, canvasWidth, canvasHeight)

    // Draw grid (lighter grid for smaller pixels)
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

    // Draw hovered pixel preview
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

  function getPixelCoordinates(clientX, clientY) {
    const rect = canvasElement.getBoundingClientRect()
    const x = Math.floor((clientX - rect.left) / pixelSize)
    const y = Math.floor((clientY - rect.top) / pixelSize)
    return { x, y }
  }

  function handleCanvasClick(event) {
    if (!canPlace) return
    const { x, y } = getPixelCoordinates(event.clientX, event.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y }, () => {})
    }
  }

  function handleCanvasMove(event) {
    const { x, y } = getPixelCoordinates(event.clientX, event.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      hoveredPixel = { x, y }
      drawCanvas()
    }
  }

  // Touch support for mobile
  function handleTouchStart(event) {
    event.preventDefault()
    if (!canPlace || event.touches.length !== 1) return

    const touch = event.touches[0]
    const { x, y } = getPixelCoordinates(touch.clientX, touch.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      hoveredPixel = { x, y }
      drawCanvas()
      live.pushEvent("place_pixel", { x, y }, () => {})
    }
  }

  function handleTouchMove(event) {
    event.preventDefault()
    if (event.touches.length !== 1) return

    const touch = event.touches[0]
    const { x, y } = getPixelCoordinates(touch.clientX, touch.clientY)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      hoveredPixel = { x, y }
      drawCanvas()
    }
  }

  function handleCanvasLeave() {
    hoveredPixel = null
    drawCanvas()
  }

  function selectColor(color) {
    selectedColor = color
    live.pushEvent("select_color", { color }, () => {})
  }

  function toggleControls() {
    showControls = !showControls
  }
</script>

<div class="fixed inset-0 flex flex-col bg-base-100">
  <!-- Minimal Header -->
  <div class="flex items-center justify-between px-4 py-2 bg-base-200 border-b-2 border-base-content">
    <div class="flex items-center gap-3">
      <h1 class="text-xl font-black uppercase tracking-tight">
        Pixel <span class="text-primary">Canvas</span>
      </h1>
      <div class="hidden sm:flex items-center gap-2 text-xs opacity-60">
        <div class="w-2 h-2 bg-primary rounded-full animate-pulse"></div>
        <span>{stats.total_pixels} pixels · {stats.unique_users} artists</span>
      </div>
    </div>

    <div class="flex items-center gap-2">
      <!-- Cooldown indicator -->
      {#if canPlace}
        <div class="px-3 py-1 bg-primary text-primary-content font-bold text-sm uppercase">Ready!</div>
      {:else}
        <div class="px-3 py-1 bg-base-300 font-bold text-sm">{secondsRemaining}s</div>
      {/if}

      <!-- Mobile menu toggle -->
      <button
        class="lg:hidden btn btn-sm btn-square"
        on:click={toggleControls}
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-16 6h16"></path>
        </svg>
      </button>
    </div>
  </div>

  <!-- Main Content -->
  <div class="flex-1 flex overflow-hidden">
    <!-- Canvas Area -->
    <div class="flex-1 overflow-auto bg-base-200">
      <div class="inline-block min-w-full min-h-full">
        <canvas
          use:initCanvas
          width={canvasWidth}
          height={canvasHeight}
          class="cursor-crosshair bg-white"
          class:cursor-not-allowed={!canPlace}
          on:click={handleCanvasClick}
          on:mousemove={handleCanvasMove}
          on:mouseleave={handleCanvasLeave}
          on:touchstart={handleTouchStart}
          on:touchmove={handleTouchMove}
          on:touchend={handleCanvasLeave}
        ></canvas>
      </div>
    </div>

    <!-- Desktop Sidebar / Mobile Overlay -->
    <div
      class="lg:relative absolute inset-0 lg:inset-auto z-10 lg:z-auto"
      class:hidden={!showControls}
      class:lg:block={true}
    >
      <!-- Backdrop for mobile -->
      <div
        class="lg:hidden absolute inset-0 bg-black/50"
        on:click={toggleControls}
      ></div>

      <!-- Controls Panel -->
      <div class="lg:relative absolute right-0 top-0 bottom-0 w-80 lg:w-64 bg-base-100 border-l-2 border-base-content overflow-y-auto flex flex-col">
        <!-- Close button for mobile -->
        <div class="lg:hidden flex justify-end p-2 border-b border-base-300">
          <button class="btn btn-sm btn-square" on:click={toggleControls}>
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>

        <div class="p-4 space-y-4">
          <!-- Color Picker -->
          <div>
            <h3 class="text-sm font-bold uppercase mb-3 opacity-70">Palette</h3>
            <div class="grid grid-cols-4 gap-2">
              {#each colors as color}
                <button
                  on:click={() => selectColor(color)}
                  class="aspect-square border-2 transition-all hover:scale-110 active:scale-95"
                  class:border-base-content={selectedColor === color}
                  class:border-transparent={selectedColor !== color}
                  class:ring-2={selectedColor === color}
                  class:ring-primary={selectedColor === color}
                  style="background-color: {color}"
                  title={color}
                ></button>
              {/each}
            </div>

            <!-- Selected color -->
            <div class="mt-3 p-2 bg-base-200 flex items-center gap-2">
              <div class="w-8 h-8 border border-base-content flex-shrink-0" style="background-color: {selectedColor}"></div>
              <div class="text-xs font-mono">{selectedColor}</div>
            </div>
          </div>

          <!-- Cooldown Details -->
          <div>
            <h3 class="text-sm font-bold uppercase mb-3 opacity-70">Cooldown</h3>
            {#if canPlace}
              <div class="text-center py-4 bg-primary/10">
                <div class="text-4xl mb-1">✓</div>
                <div class="text-xs font-bold uppercase text-primary">Ready to Place!</div>
              </div>
            {:else}
              <div class="text-center py-4 bg-base-200">
                <div class="text-4xl font-black mb-1">{secondsRemaining}</div>
                <div class="text-xs uppercase opacity-60">seconds</div>
              </div>
            {/if}

            <!-- Progress bar -->
            <div class="mt-2 h-1.5 bg-base-200 overflow-hidden">
              <div
                class="h-full bg-primary transition-all duration-1000"
                style="width: {canPlace ? 100 : ((60 - secondsRemaining) / 60) * 100}%"
              ></div>
            </div>
          </div>

          <!-- Stats -->
          <div>
            <h3 class="text-sm font-bold uppercase mb-3 opacity-70">Statistics</h3>
            <div class="space-y-2">
              <div class="flex justify-between items-center">
                <span class="text-xs opacity-60">Total Pixels</span>
                <span class="text-lg font-black">{stats.total_pixels.toLocaleString()}</span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-xs opacity-60">Artists</span>
                <span class="text-lg font-black">{stats.unique_users.toLocaleString()}</span>
              </div>
            </div>
          </div>

          <!-- Instructions -->
          <div class="text-xs opacity-60 leading-relaxed pt-2 border-t border-base-300">
            <p class="mb-2"><strong>Desktop:</strong> Click to place pixel</p>
            <p><strong>Mobile:</strong> Tap to place pixel. Scroll to navigate.</p>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Mobile FAB (Floating Action Button) when controls hidden -->
  {#if !showControls}
    <button
      class="lg:hidden fixed bottom-4 right-4 w-14 h-14 rounded-full shadow-lg flex items-center justify-center z-20"
      class:bg-primary={canPlace}
      class:text-primary-content={canPlace}
      class:bg-base-300={!canPlace}
      on:click={toggleControls}
    >
      {#if canPlace}
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"></path>
        </svg>
      {:else}
        <span class="text-sm font-bold">{secondsRemaining}</span>
      {/if}
    </button>
  {/if}
</div>

<style>
  /* Ensure no scrollbars on body when fullscreen */
  :global(body) {
    overflow: hidden;
  }

  /* Smooth scrolling for canvas area */
  canvas {
    image-rendering: pixelated;
    image-rendering: -moz-crisp-edges;
    image-rendering: crisp-edges;
  }
</style>
