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
  let pixelSize = 2 // Smaller pixels: 500x500 grid = 1000x1000px canvas
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

    // Draw grid
    ctx.strokeStyle = '#EEEEEE'
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

<div class="min-h-screen bg-base-100">
  <!-- Header -->
  <div class="container mx-auto px-4 py-8">
    <h1 class="text-5xl font-black tracking-tight uppercase mb-4">
      Pixel<br /><span class="text-primary">Canvas</span>
    </h1>
    <p class="text-lg opacity-70">
      500×500 collaborative pixel art. Place one pixel every minute.
    </p>
  </div>

  <div class="container mx-auto px-4 pb-8">
    <div class="grid lg:grid-cols-[1fr_320px] gap-6">
      <!-- Canvas Section -->
      <div class="border-4 border-base-content bg-base-100 p-4 sm:p-6">
      <div class="mb-4 flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="w-3 h-3 bg-primary rounded-none animate-pulse"></div>
          <span class="text-xs uppercase tracking-widest font-bold opacity-70">
            Live Canvas
          </span>
        </div>
        <div class="text-xs font-bold opacity-50">
          {stats.total_pixels} pixels · {stats.unique_users} artists
        </div>
      </div>

      <!-- Canvas -->
      <div class="overflow-auto border-2 border-base-content bg-white max-h-[600px] lg:max-h-[800px]">
        <canvas
          use:initCanvas
          width={canvasWidth}
          height={canvasHeight}
          class="cursor-crosshair block"
          class:cursor-not-allowed={!canPlace}
          on:click={handleCanvasClick}
          on:mousemove={handleCanvasMove}
          on:mouseleave={handleCanvasLeave}
        ></canvas>
      </div>

      <!-- Instructions -->
      <div class="mt-4 text-sm opacity-70">
        Click any pixel to place your color. {#if !canPlace}Wait {secondsRemaining}s to place again.{/if}
      </div>
    </div>

    <!-- Controls Sidebar -->
    <div class="space-y-6">
      <!-- Color Picker -->
      <div class="border-4 border-base-content bg-base-100 p-6">
        <h3 class="text-xl font-black uppercase mb-4 tracking-tight">Palette</h3>
        <div class="grid grid-cols-4 gap-2">
          {#each colors as color}
            <button
              on:click={() => selectColor(color)}
              class="w-full aspect-square border-4 transition-all hover:scale-110"
              class:border-base-content={selectedColor === color}
              class:border-transparent={selectedColor !== color}
              style="background-color: {color}"
              title={color}
            ></button>
          {/each}
        </div>

        <div class="mt-4 p-3 bg-base-200 border-2 border-base-content">
          <div class="text-xs uppercase tracking-wider font-bold opacity-50 mb-2">Selected</div>
          <div class="flex items-center gap-3">
            <div class="w-12 h-12 border-2 border-base-content" style="background-color: {selectedColor}"></div>
            <div class="text-sm font-mono">{selectedColor}</div>
          </div>
        </div>
      </div>

      <!-- Cooldown Timer -->
      <div class="border-4 border-base-content bg-base-100 p-6">
        <h3 class="text-xl font-black uppercase mb-4 tracking-tight">Cooldown</h3>

        {#if canPlace}
          <div class="text-center py-8">
            <div class="text-6xl font-black mb-2">✓</div>
            <div class="text-sm font-bold uppercase tracking-wide text-primary">Ready!</div>
          </div>
        {:else}
          <div class="text-center py-8">
            <div class="text-6xl font-black mb-2">{secondsRemaining}</div>
            <div class="text-xs uppercase tracking-wider font-bold opacity-50">seconds</div>
          </div>
        {/if}

        <!-- Progress bar -->
        <div class="mt-4 h-2 bg-base-200 border-2 border-base-content overflow-hidden">
          <div
            class="h-full bg-primary transition-all duration-1000"
            style="width: {canPlace ? 100 : ((60 - secondsRemaining) / 60) * 100}%"
          ></div>
        </div>
      </div>

      <!-- Stats -->
      <div class="border-4 border-base-content bg-base-100 p-6">
        <h3 class="text-xl font-black uppercase mb-4 tracking-tight">Stats</h3>
        <div class="space-y-3">
          <div>
            <div class="text-xs uppercase tracking-wider font-bold opacity-50">Total Pixels</div>
            <div class="text-3xl font-black">{stats.total_pixels.toLocaleString()}</div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider font-bold opacity-50">Artists</div>
            <div class="text-3xl font-black">{stats.unique_users.toLocaleString()}</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
