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
  let pixelSize = 4 // 500x500 grid = 2000x2000px canvas
  let canvasElement
  let ctx

  // Reactive canvas dimensions
  $: canvasWidth = width * pixelSize
  $: canvasHeight = height * pixelSize

  // Draw canvas when pixels change - explicitly depend on pixels
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
<div class="fixed inset-0 bg-white flex flex-col">
  <!-- Compact header with all controls -->
  <div class="flex-none border-b-2 border-black bg-white z-10">
    <!-- Top row: Back link + Stats + Cooldown -->
    <div class="flex items-center justify-between gap-4 px-3 py-2 border-b border-gray-200">
      <a href="/" class="text-xs font-bold hover:text-primary transition-colors whitespace-nowrap">
        ← Kruk.live
      </a>

      <div class="flex items-center gap-3 text-xs">
        <div class="flex items-center gap-1.5">
          <div class="w-1.5 h-1.5 bg-primary rounded-none animate-pulse"></div>
          <span class="hidden sm:inline opacity-60">Live</span>
        </div>
        <span class="opacity-60">{stats.total_pixels.toLocaleString()}px</span>
        <span class="opacity-60">{stats.unique_users} artists</span>
      </div>

      <div class="flex items-center gap-2">
        {#if canPlace}
          <span class="text-xs font-bold text-primary">Ready!</span>
        {:else}
          <span class="text-xs font-bold">{secondsRemaining}s</span>
        {/if}
        <div class="w-12 h-1.5 bg-gray-200 border border-black hidden sm:block">
          <div
            class="h-full bg-primary transition-all duration-1000"
            style="width: {canPlace ? 100 : ((60 - secondsRemaining) / 60) * 100}%"
          ></div>
        </div>
      </div>
    </div>

    <!-- Bottom row: Color palette + Selected color -->
    <div class="flex items-center gap-3 px-3 py-2">
      <span class="text-xs font-bold uppercase opacity-50 hidden sm:inline">Palette</span>

      <div class="flex gap-1.5 flex-wrap">
        {#each colors as color}
          <button
            on:click={() => selectColor(color)}
            class="w-6 h-6 border transition-all hover:scale-110"
            class:border-black={selectedColor === color}
            class:border-2={selectedColor === color}
            class:border-gray-300={selectedColor !== color}
            style="background-color: {color}"
            title={color}
          ></button>
        {/each}
      </div>

      <div class="ml-auto flex items-center gap-2">
        <div class="w-6 h-6 border-2 border-black" style="background-color: {selectedColor}"></div>
        <span class="text-xs font-mono opacity-60 hidden sm:inline">{selectedColor}</span>
      </div>
    </div>
  </div>

  <!-- Canvas area - scrollable with visible scrollbars -->
  <div class="flex-1 overflow-auto bg-neutral-100" style="overflow: auto; -webkit-overflow-scrolling: touch;">
    <div class="inline-block min-w-full min-h-full p-4">
      <canvas
        use:initCanvas
        width={canvasWidth}
        height={canvasHeight}
        class="cursor-crosshair border-2 border-black shadow-[8px_8px_0_0_rgba(0,0,0,1)] mx-auto"
        class:cursor-not-allowed={!canPlace}
        on:click={handleCanvasClick}
        on:mousemove={handleCanvasMove}
        on:mouseleave={handleCanvasLeave}
      ></canvas>
    </div>
  </div>
</div>
