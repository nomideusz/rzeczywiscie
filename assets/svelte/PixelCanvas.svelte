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
  let pixelSize = 4 // Larger pixels: 500x500 grid = 2000x2000px canvas
  let canvasElement
  let ctx

  // Reactive canvas dimensions
  $: canvasWidth = width * pixelSize
  $: canvasHeight = height * pixelSize

  // Draw canvas when pixels change
  $: if (ctx && pixels) {
    drawCanvas()
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

    // Draw grid (lighter, less prominent)
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
        pixelSize - 2,
        pixelSize - 2
      )
    })

    // Draw hovered pixel preview
    if (hoveredPixel && canPlace) {
      ctx.globalAlpha = 0.5
      ctx.fillStyle = selectedColor
      ctx.fillRect(
        hoveredPixel.x * pixelSize + 1,
        hoveredPixel.y * pixelSize + 1,
        pixelSize - 2,
        pixelSize - 2
      )
      ctx.globalAlpha = 1.0
    }
  }

  function handleCanvasClick(event) {
    if (!canPlace) return

    const rect = canvasElement.getBoundingClientRect()
    const x = Math.floor((event.clientX - rect.left) / pixelSize)
    const y = Math.floor((event.clientY - rect.top) / pixelSize)

    if (x >= 0 && x < width && y >= 0 && y < height) {
      live.pushEvent("place_pixel", { x, y }, () => {})
    }
  }

  function handleCanvasMove(event) {
    const rect = canvasElement.getBoundingClientRect()
    const x = Math.floor((event.clientX - rect.left) / pixelSize)
    const y = Math.floor((event.clientY - rect.top) / pixelSize)

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
</script>

<!-- Full screen layout -->
<div class="fixed inset-0 bg-white overflow-hidden flex flex-col">
  <!-- Minimal header -->
  <div class="flex-none border-b-2 border-black px-4 py-2 bg-white z-10">
    <a href="/" class="text-sm font-bold hover:text-primary transition-colors">
      ← Kruk.live
    </a>
  </div>

  <!-- Main content area -->
  <div class="flex-1 flex overflow-hidden">
    <!-- Canvas area (scrollable) -->
    <div class="flex-1 overflow-auto bg-neutral-100 flex items-center justify-center p-4">
      <canvas
        use:initCanvas
        width={canvasWidth}
        height={canvasHeight}
        class="cursor-crosshair border-2 border-black shadow-[8px_8px_0_0_rgba(0,0,0,1)]"
        class:cursor-not-allowed={!canPlace}
        on:click={handleCanvasClick}
        on:mousemove={handleCanvasMove}
        on:mouseleave={handleCanvasLeave}
      ></canvas>
    </div>

    <!-- Controls sidebar (fixed on right) -->
    <div class="flex-none w-80 border-l-2 border-black bg-white overflow-y-auto">
      <div class="p-6 space-y-6">
        <!-- Stats -->
        <div class="border-2 border-black p-4">
          <div class="flex items-center gap-2 mb-3">
            <div class="w-2 h-2 bg-primary rounded-none animate-pulse"></div>
            <h3 class="text-xs uppercase font-bold tracking-wider">Live</h3>
          </div>
          <div class="space-y-2">
            <div class="flex justify-between text-xs">
              <span class="opacity-60">Pixels</span>
              <span class="font-bold">{stats.total_pixels.toLocaleString()}</span>
            </div>
            <div class="flex justify-between text-xs">
              <span class="opacity-60">Artists</span>
              <span class="font-bold">{stats.unique_users.toLocaleString()}</span>
            </div>
          </div>
        </div>

        <!-- Color Palette -->
        <div class="border-2 border-black p-4">
          <h3 class="text-sm font-bold uppercase mb-3 tracking-tight">Palette</h3>
          <div class="grid grid-cols-4 gap-2 mb-3">
            {#each colors as color}
              <button
                on:click={() => selectColor(color)}
                class="w-full aspect-square border-2 transition-all hover:scale-110"
                class:border-black={selectedColor === color}
                class:border-gray-300={selectedColor !== color}
                class:shadow-[4px_4px_0_0_rgba(0,0,0,1)]={selectedColor === color}
                style="background-color: {color}"
                title={color}
              ></button>
            {/each}
          </div>
          <div class="flex items-center gap-2 text-xs">
            <div class="w-8 h-8 border-2 border-black" style="background-color: {selectedColor}"></div>
            <span class="font-mono opacity-60">{selectedColor}</span>
          </div>
        </div>

        <!-- Cooldown -->
        <div class="border-2 border-black p-4">
          <h3 class="text-sm font-bold uppercase mb-3 tracking-tight">Cooldown</h3>

          {#if canPlace}
            <div class="text-center py-6">
              <div class="text-4xl font-black mb-2">✓</div>
              <div class="text-xs uppercase tracking-wide text-primary font-bold">Ready!</div>
            </div>
          {:else}
            <div class="text-center py-6">
              <div class="text-5xl font-black mb-1">{secondsRemaining}</div>
              <div class="text-xs uppercase tracking-wider opacity-50 font-bold">seconds</div>
            </div>
          {/if}

          <!-- Progress bar -->
          <div class="h-2 bg-gray-200 border-2 border-black overflow-hidden">
            <div
              class="h-full bg-primary transition-all duration-1000"
              style="width: {canPlace ? 100 : ((60 - secondsRemaining) / 60) * 100}%"
            ></div>
          </div>
        </div>

        <!-- Instructions -->
        <div class="text-xs opacity-60 leading-relaxed">
          Click any pixel to place your selected color.
          {#if !canPlace}
            Wait <span class="font-bold text-black">{secondsRemaining}s</span> to place again.
          {:else}
            <span class="font-bold text-primary">Ready to place!</span>
          {/if}
        </div>
      </div>
    </div>
  </div>
</div>
