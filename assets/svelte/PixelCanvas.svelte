<script>
  import {onMount, onDestroy} from "svelte"

  export let live
  export let width = 200
  export let height = 200
  export let colors = []
  export let selectedColor = null
  export let secondsRemaining = 0
  export let cooldownSeconds = 15
  export let stats = null

  const MIN_SCALE = 2
  const MAX_SCALE = 24

  let canvasEl
  let ctx
  let viewport
  let scale = 4
  let remaining = 0
  let timer = null

  // "x,y" -> color; kept client-side, synced via LiveView push events
  let pixelMap = new Map()

  // pan/click discrimination
  let panning = false
  let movedDistance = 0
  let last = {x: 0, y: 0}

  $: startCountdown(secondsRemaining)

  function startCountdown(s) {
    clearInterval(timer)
    remaining = s
    if (s > 0) {
      timer = setInterval(() => {
        remaining -= 1
        if (remaining <= 0) clearInterval(timer)
      }, 1000)
    }
  }

  function draw() {
    if (!ctx) return
    ctx.fillStyle = "#ffffff"
    ctx.fillRect(0, 0, width, height)
    for (const [key, color] of pixelMap) {
      const [x, y] = key.split(",")
      ctx.fillStyle = color
      ctx.fillRect(+x, +y, 1, 1)
    }
  }

  function drawPixel(x, y, color) {
    if (!ctx) return
    ctx.fillStyle = color
    ctx.fillRect(x, y, 1, 1)
  }

  function canvasCoords(event) {
    const rect = canvasEl.getBoundingClientRect()
    const x = Math.floor(((event.clientX - rect.left) / rect.width) * width)
    const y = Math.floor(((event.clientY - rect.top) / rect.height) * height)
    if (x < 0 || x >= width || y < 0 || y >= height) return null
    return {x, y}
  }

  function handleClick(event) {
    if (movedDistance > 5) return // it was a pan, not a click
    if (remaining > 0) return
    const coords = canvasCoords(event)
    if (coords) live.pushEvent("place_pixel", coords)
  }

  function handleWheel(event) {
    event.preventDefault()
    const factor = event.deltaY < 0 ? 1.25 : 0.8
    scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale * factor))
  }

  function handlePointerDown(event) {
    panning = true
    movedDistance = 0
    last = {x: event.clientX, y: event.clientY}
  }

  function handlePointerMove(event) {
    if (!panning) return
    const dx = event.clientX - last.x
    const dy = event.clientY - last.y
    movedDistance += Math.abs(dx) + Math.abs(dy)
    last = {x: event.clientX, y: event.clientY}
    viewport.scrollLeft -= dx
    viewport.scrollTop -= dy
  }

  function handlePointerUp() {
    panning = false
  }

  function selectColor(color) {
    live.pushEvent("select_color", {color})
  }

  onMount(() => {
    ctx = canvasEl.getContext("2d")
    draw()

    live.handleEvent("canvas", ({pixels}) => {
      pixelMap = new Map(pixels.map(([x, y, c]) => [`${x},${y}`, c]))
      draw()
    })

    live.handleEvent("pixel", ({x, y, color}) => {
      pixelMap.set(`${x},${y}`, color)
      drawPixel(x, y, color)
    })

    // persistent per-browser identity so the cooldown follows the browser
    let uid = localStorage.getItem("pixel_uid")
    if (!uid) {
      uid = crypto.randomUUID().replaceAll("-", "")
      localStorage.setItem("pixel_uid", uid)
    }
    live.pushEvent("set_user_id", {user_id: uid})
  })

  onDestroy(() => clearInterval(timer))
</script>

<div class="min-h-screen bg-base-200 flex flex-col">
  <!-- Header -->
  <div class="bg-base-100 border-b-2 border-base-content">
    <div class="container mx-auto px-4 py-3 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-lg font-black uppercase tracking-wide">Pixels</h1>
        <p class="text-[10px] opacity-60">
          One pixel per {cooldownSeconds}s &middot; overwriting allowed
          {#if stats}
            &middot; {stats.total_pixels} pixels by {stats.contributors} people
          {/if}
        </p>
      </div>
      <div class="text-right">
        {#if remaining > 0}
          <div class="text-2xl font-black text-warning tabular-nums">{remaining}s</div>
          <div class="text-[10px] font-bold uppercase opacity-60">cooldown</div>
        {:else}
          <div class="text-2xl font-black text-success">Ready</div>
          <div class="text-[10px] font-bold uppercase opacity-60">click to place</div>
        {/if}
      </div>
    </div>
  </div>

  <!-- Palette -->
  <div class="bg-base-100 border-b border-base-content/20">
    <div class="container mx-auto px-4 py-2 flex flex-wrap gap-1.5 justify-center">
      {#each colors as color (color)}
        <button
          aria-label={`Select color ${color}`}
          class="w-8 h-8 border-2 transition-transform cursor-pointer {selectedColor === color
            ? 'border-base-content scale-110 shadow'
            : 'border-base-content/20 hover:scale-105'}"
          style="background: {color}"
          onclick={() => selectColor(color)}
        ></button>
      {/each}
    </div>
  </div>

  <!-- Canvas -->
  <div
    bind:this={viewport}
    class="flex-1 overflow-auto touch-none select-none bg-base-300 cursor-crosshair"
    onwheel={handleWheel}
    onpointerdown={handlePointerDown}
    onpointermove={handlePointerMove}
    onpointerup={handlePointerUp}
    onpointerleave={handlePointerUp}
  >
    <div class="p-8 inline-block min-w-full min-h-full text-center">
      <canvas
        bind:this={canvasEl}
        {width}
        {height}
        class="inline-block bg-white border-2 border-base-content shadow-lg"
        style="width: {width * scale}px; height: {height * scale}px; image-rendering: pixelated;"
        onclick={handleClick}
      ></canvas>
    </div>
  </div>

  <div class="bg-base-100 border-t border-base-content/20 flex items-center justify-center gap-3 py-1 text-[10px] opacity-70">
    <button class="w-6 h-6 border border-base-content/40 font-bold cursor-pointer hover:bg-base-200" onclick={() => (scale = Math.max(MIN_SCALE, scale * 0.8))}>&minus;</button>
    <span class="opacity-60">scroll to zoom &middot; drag to pan</span>
    <button class="w-6 h-6 border border-base-content/40 font-bold cursor-pointer hover:bg-base-200" onclick={() => (scale = Math.min(MAX_SCALE, scale * 1.25))}>+</button>
  </div>
</div>
