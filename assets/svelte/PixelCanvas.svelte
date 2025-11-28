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
  export let userStats = { pixels_placed: 0, massive_pixels_available: 0, progress_to_next: 0 }
  export let isMassiveMode = false
  export let live

  let hoveredPixel = null
  let pixelSize = 8
  let canvasElement
  let canvasContainer
  let scrollContainer
  let ctx
  let lastCursorSend = 0
  let zoom = 1
  let showPalette = false
  let isMobile = false
  let canScroll = false
  let showScrollHint = false
  let hasScrolled = false
  const CURSOR_THROTTLE_MS = 250

  // Pan/drag state
  let isPanning = false
  let panStart = { x: 0, y: 0 }
  let scrollStart = { x: 0, y: 0 }

  // Center the scroll position
  function centerCanvas() {
    if (!scrollContainer) return
    
    const scrollWidth = scrollContainer.scrollWidth
    const scrollHeight = scrollContainer.scrollHeight
    const clientWidth = scrollContainer.clientWidth
    const clientHeight = scrollContainer.clientHeight
    
    // Center horizontally and vertically
    scrollContainer.scrollLeft = (scrollWidth - clientWidth) / 2
    scrollContainer.scrollTop = (scrollHeight - clientHeight) / 2
  }

  // Detect mobile and check if canvas is scrollable
  onMount(() => {
    isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    
    // Set default zoom higher on mobile so pixels are visible
    if (isMobile) {
      zoom = 2
      // Redraw with new zoom and center after render
      if (ctx) drawCanvas()
      // Center canvas after a short delay to let it render
      setTimeout(centerCanvas, 100)
    }
    
    const savedColor = localStorage.getItem('pixels_selected_color')
    if (savedColor && colors.includes(savedColor)) {
      selectedColor = savedColor
      live.pushEvent("select_color", { color: savedColor })
    }

    // Check if user has seen scroll hint before
    hasScrolled = localStorage.getItem('pixels_has_scrolled') === 'true'

    // Check scrollability after a short delay to let canvas render
    setTimeout(checkScrollability, 500)
  })

  function checkScrollability() {
    if (!scrollContainer) return
    
    // Add a small threshold (5px) to avoid false positives from rounding
    const threshold = 5
    const isScrollable = scrollContainer.scrollWidth > scrollContainer.clientWidth + threshold ||
                         scrollContainer.scrollHeight > scrollContainer.clientHeight + threshold
    
    canScroll = isScrollable
    
    // Show hint briefly if scrollable and user hasn't scrolled before
    if (isScrollable && !hasScrolled && isMobile) {
      showScrollHint = true
      setTimeout(() => {
        showScrollHint = false
      }, 4000)
    } else {
      showScrollHint = false
    }
  }

  function onUserScrolled() {
    if (!hasScrolled) {
      hasScrolled = true
      localStorage.setItem('pixels_has_scrolled', 'true')
      showScrollHint = false
    }
  }

  // Cooldown progress (0 to 1)
  $: cooldownProgress = canPlace ? 1 : (cooldownSeconds - secondsRemaining) / cooldownSeconds

  // Calculate responsive pixel size based on available space
  function calculatePixelSize() {
    if (!canvasContainer) return

    // Account for padding: 2rem (32px) each side = 64px total
    const padding = 64
    const containerWidth = canvasContainer.clientWidth - padding
    const containerHeight = canvasContainer.clientHeight - padding

    const maxPixelWidth = Math.floor(containerWidth / width)
    const maxPixelHeight = Math.floor(containerHeight / height)

    // Fit canvas nicely in viewport
    const fittedSize = Math.min(maxPixelWidth, maxPixelHeight)
    const newPixelSize = Math.max(2, Math.min(8, fittedSize))

    if (newPixelSize !== pixelSize) {
      pixelSize = newPixelSize
      if (ctx) drawCanvas()
    }
  }

  // Draw canvas when pixels change
  $: if (ctx && pixelsVersion >= 0) {
    drawCanvas()
  }

  function initCanvas(node) {
    canvasElement = node
    ctx = node.getContext('2d')
    drawCanvas()
    return { destroy() {} }
  }

  function initContainer(node) {
    canvasContainer = node
    calculatePixelSize()

    const resizeObserver = new ResizeObserver(() => calculatePixelSize())
    resizeObserver.observe(node)

    return { destroy() { resizeObserver.disconnect() } }
  }

  function initScrollContainer(node) {
    scrollContainer = node
    
    // Listen for scroll to dismiss hint
    const handleScroll = () => onUserScrolled()
    node.addEventListener('scroll', handleScroll, { passive: true })
    
    return { 
      destroy() {
        node.removeEventListener('scroll', handleScroll)
      }
    }
  }

  function drawCanvas() {
    if (!ctx) return

    const effectivePixelSize = pixelSize * zoom
    const cellSize = Math.round(effectivePixelSize)
    const actualWidth = width * cellSize
    const actualHeight = height * cellSize

    if (canvasElement.width !== actualWidth || canvasElement.height !== actualHeight) {
      canvasElement.width = actualWidth
      canvasElement.height = actualHeight
    }

    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, actualWidth, actualHeight)

    // Draw grid - use uniform cell size to prevent wide/tall pixels
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.06)'
    ctx.lineWidth = 1
    ctx.beginPath()

    for (let x = 0; x <= width; x++) {
      const px = x * cellSize + 0.5
      ctx.moveTo(px, 0)
      ctx.lineTo(px, height * cellSize)
    }

    for (let y = 0; y <= height; y++) {
      const py = y * cellSize + 0.5
      ctx.moveTo(0, py)
      ctx.lineTo(width * cellSize, py)
    }

    ctx.stroke()

    // Draw pixels - use uniform cell size for consistent appearance
    pixels.forEach(pixel => {
      // Add glow effect for massive pixels
      if (pixel.is_massive) {
        ctx.shadowBlur = 8
        ctx.shadowColor = pixel.color
      } else {
        ctx.shadowBlur = 0
      }

      ctx.fillStyle = pixel.color
      ctx.fillRect(
        pixel.x * cellSize + 1,
        pixel.y * cellSize + 1,
        cellSize - 2,
        cellSize - 2
      )
    })

    // Reset shadow
    ctx.shadowBlur = 0

    // Preview hovered pixel(s)
    if (hoveredPixel && canPlace && !isPanning) {
      ctx.globalAlpha = 0.5
      ctx.fillStyle = selectedColor

      if (isMassiveMode && userStats.massive_pixels_available > 0) {
        // Draw 3x3 preview for massive pixel
        for (let dx = -1; dx <= 1; dx++) {
          for (let dy = -1; dy <= 1; dy++) {
            const px = hoveredPixel.x + dx
            const py = hoveredPixel.y + dy
            if (px >= 0 && px < width && py >= 0 && py < height) {
              // Add subtle glow to preview
              ctx.shadowBlur = 6
              ctx.shadowColor = selectedColor
              ctx.fillRect(
                px * cellSize + 1,
                py * cellSize + 1,
                cellSize - 2,
                cellSize - 2
              )
            }
          }
        }
        ctx.shadowBlur = 0
      } else {
        // Draw single pixel preview
        ctx.fillRect(
          hoveredPixel.x * cellSize + 1,
          hoveredPixel.y * cellSize + 1,
          cellSize - 2,
          cellSize - 2
        )
      }

      ctx.globalAlpha = 1.0
    }
  }

  function getCoords(clientX, clientY) {
    const rect = canvasElement.getBoundingClientRect()
    const cellSize = Math.round(pixelSize * zoom)
    const x = Math.floor((clientX - rect.left) / cellSize)
    const y = Math.floor((clientY - rect.top) / cellSize)
    return { x, y }
  }

  function handleMouseDown(event) {
    if (event.button === 1) {
      event.preventDefault()
      startPan(event.clientX, event.clientY)
    }
  }

  function handleMouseUp(event) {
    if (isPanning) {
      isPanning = false
      return
    }
  }

  function handleClick(event) {
    if (isPanning || !canPlace) return
    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      if (isMassiveMode && userStats.massive_pixels_available > 0) {
        // Place massive pixel (3x3 grid)
        live.pushEvent("place_massive_pixel", { x, y })
      } else {
        // Place normal pixel
        live.pushEvent("place_pixel", { x, y })
      }
    }
  }

  function toggleMassiveMode() {
    if (userStats.massive_pixels_available > 0) {
      live.pushEvent("toggle_massive_mode")
    }
  }

  function handleMove(event) {
    if (isPanning) {
      doPan(event.clientX, event.clientY)
      return
    }

    const { x, y } = getCoords(event.clientX, event.clientY)
    if (x >= 0 && x < width && y >= 0 && y < height) {
      if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
        hoveredPixel = { x, y }
        drawCanvas()
        sendCursorPosition(x, y)
      }
    }
  }

  function startPan(clientX, clientY) {
    isPanning = true
    panStart = { x: clientX, y: clientY }
    if (scrollContainer) {
      scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
    }
  }

  function doPan(clientX, clientY) {
    if (!scrollContainer) return
    const dx = panStart.x - clientX
    const dy = panStart.y - clientY
    scrollContainer.scrollLeft = scrollStart.x + dx
    scrollContainer.scrollTop = scrollStart.y + dy
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

  // Touch handling
  let lastTouchDistance = 0
  let touchPanStart = null
  let singleTouchStart = null  // Track single touch start position
  let touchMoved = false       // Track if touch moved significantly
  const TAP_THRESHOLD = 10     // Max pixels moved to count as tap

  function handleTouchStart(event) {
    if (event.touches.length === 2) {
      event.preventDefault()
      singleTouchStart = null  // Cancel single touch if second finger added
      touchMoved = true
      const touch1 = event.touches[0]
      const touch2 = event.touches[1]
      const centerX = (touch1.clientX + touch2.clientX) / 2
      const centerY = (touch1.clientY + touch2.clientY) / 2
      touchPanStart = { x: centerX, y: centerY }
      if (scrollContainer) {
        scrollStart = { x: scrollContainer.scrollLeft, y: scrollContainer.scrollTop }
      }
      lastTouchDistance = Math.hypot(
        touch2.clientX - touch1.clientX,
        touch2.clientY - touch1.clientY
      )
    } else if (event.touches.length === 1) {
      const touch = event.touches[0]
      singleTouchStart = { clientX: touch.clientX, clientY: touch.clientY }
      touchMoved = false
      
      const { x, y } = getCoords(touch.clientX, touch.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        hoveredPixel = { x, y }
        drawCanvas()
      }
    }
  }

  function handleTouchMove(event) {
    if (event.touches.length === 2) {
      event.preventDefault()
      const touch1 = event.touches[0]
      const touch2 = event.touches[1]
      
      const centerX = (touch1.clientX + touch2.clientX) / 2
      const centerY = (touch1.clientY + touch2.clientY) / 2
      if (touchPanStart && scrollContainer) {
        const dx = touchPanStart.x - centerX
        const dy = touchPanStart.y - centerY
        scrollContainer.scrollLeft = scrollStart.x + dx
        scrollContainer.scrollTop = scrollStart.y + dy
      }

      const distance = Math.hypot(
        touch2.clientX - touch1.clientX,
        touch2.clientY - touch1.clientY
      )
      if (lastTouchDistance > 0) {
        const scale = distance / lastTouchDistance
        if (Math.abs(scale - 1) > 0.02) {
          const newZoom = Math.max(0.5, Math.min(3, zoom * scale))
          if (newZoom !== zoom) {
            zoom = newZoom
            drawCanvas()
          }
          lastTouchDistance = distance
        }
      }
    } else if (event.touches.length === 1) {
      const touch = event.touches[0]
      
      // Check if moved beyond tap threshold
      if (singleTouchStart) {
        const dx = touch.clientX - singleTouchStart.clientX
        const dy = touch.clientY - singleTouchStart.clientY
        if (Math.hypot(dx, dy) > TAP_THRESHOLD) {
          touchMoved = true
        }
      }
      
      const { x, y } = getCoords(touch.clientX, touch.clientY)
      if (x >= 0 && x < width && y >= 0 && y < height) {
        if (!hoveredPixel || hoveredPixel.x !== x || hoveredPixel.y !== y) {
          hoveredPixel = { x, y }
          drawCanvas()
          sendCursorPosition(x, y)
        }
      }
    }
  }

  function handleTouchEnd(event) {
    // Place pixel only if it was a tap (no significant movement) and can place
    if (singleTouchStart && !touchMoved && canPlace && event.changedTouches.length > 0) {
      // Use changedTouches to get the exact position where the finger was lifted
      const touch = event.changedTouches[0]
      const { x, y } = getCoords(touch.clientX, touch.clientY)

      if (x >= 0 && x < width && y >= 0 && y < height) {
        if (isMassiveMode && userStats.massive_pixels_available > 0) {
          // Place massive pixel (3x3 grid)
          live.pushEvent("place_massive_pixel", { x, y })
        } else {
          // Place normal pixel
          live.pushEvent("place_pixel", { x, y })
        }
      }
    }

    touchPanStart = null
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
    showPalette = false
  }

  function adjustZoom(delta) {
    zoom = Math.max(0.5, Math.min(3, zoom + delta))
    drawCanvas()
    // Recheck scrollability after zoom change
    setTimeout(checkScrollability, 100)
  }

  function handleKeyDown(event) {
    if (event.key >= '1' && event.key <= '9') {
      const index = parseInt(event.key) - 1
      if (colors[index]) {
        selectColor(colors[index])
      }
    }
    if (event.key === '0' && colors[9]) {
      selectColor(colors[9])
    }
  }

  function handleClickOutside(event) {
    if (showPalette && !event.target.closest('.palette-container')) {
      showPalette = false
    }
  }

  function openPalette() {
    showPalette = true
    showUI = true
    if (uiTimeout) clearTimeout(uiTimeout)
  }
</script>

<svelte:window on:keydown={handleKeyDown} on:mouseup={handleMouseUp} on:click={handleClickOutside} />

<div class="fixed inset-0 flex flex-col bg-neutral-100">
  <!-- Canvas Area - full screen -->
  <div 
    class="flex-1 overflow-auto"
    use:initScrollContainer
    use:initContainer
  >
    <div class="flex items-center justify-center min-h-full" style="min-width: max-content; padding: 2rem;">
      <div class="relative">
        <canvas
          use:initCanvas
          class="shadow-2xl rounded-sm bg-white {isPanning ? 'cursor-grabbing' : 'cursor-crosshair'}"
          on:mousedown={handleMouseDown}
          on:click={handleClick}
          on:mousemove={handleMove}
          on:mouseleave={handleLeave}
          on:touchstart={handleTouchStart}
          on:touchmove={handleTouchMove}
          on:touchend={handleTouchEnd}
          on:contextmenu|preventDefault
        ></canvas>

        <!-- Live Cursors -->
        {#each cursors as cursor (cursor.id)}
          <div
            class="absolute pointer-events-none transition-all duration-100"
            style="left: {cursor.x * Math.round(pixelSize * zoom)}px; top: {cursor.y * Math.round(pixelSize * zoom)}px;"
          >
            <div
              class="w-2 h-2 rounded-full border border-white shadow"
              style="background-color: {cursor.color}"
            ></div>
          </div>
        {/each}
      </div>
    </div>

    <!-- Scroll hint overlay -->
    {#if showScrollHint && canScroll}
      <div class="absolute inset-0 pointer-events-none flex items-center justify-center">
        <div class="bg-black/70 text-white px-4 py-3 rounded-2xl flex items-center gap-3 animate-hint">
          <svg class="w-6 h-6 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4"/>
          </svg>
          <span class="text-sm">Drag to explore</span>
        </div>
      </div>
    {/if}
  </div>

  <!-- UI Container -->
  <div class="contents">
    
    <!-- Color picker - bottom center on mobile, bottom left on desktop -->
    <div
      class="fixed z-50 {isMobile ? 'bottom-4 left-1/2 -translate-x-1/2' : 'bottom-6 left-6'}"
    >
      <div class="palette-container relative flex items-end gap-3">

        <!-- Expanded palette -->
        {#if showPalette}
          <div class="absolute {isMobile ? 'bottom-16 left-1/2 -translate-x-1/2' : 'bottom-16 left-0'} bg-white rounded-2xl shadow-2xl p-4 animate-in">
            <div class="flex flex-wrap gap-2 justify-center" style="width: 200px;">
              {#each colors as color, i}
                <button
                  class="group relative w-9 h-9 rounded-lg transition-all active:scale-95 {selectedColor === color ? 'ring-2 ring-neutral-900 ring-offset-2' : ''}"
                  style="background-color: {color};"
                  on:click={() => selectColor(color)}
                >
                  {#if i < 10 && !isMobile}
                    <span class="absolute -top-1 -right-1 w-4 h-4 bg-neutral-900 text-white text-[10px] font-medium rounded-full opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                      {i < 9 ? i + 1 : 0}
                    </span>
                  {/if}
                </button>
              {/each}
            </div>
            {#if !isMobile}
              <p class="text-[10px] text-neutral-400 mt-3 text-center">1-0 for first 10 colors</p>
            {/if}
          </div>
        {/if}

        <!-- Current color button -->
        <button
          class="w-14 h-14 sm:w-12 sm:h-12 rounded-full shadow-lg transition-all active:scale-95 relative overflow-hidden"
          style="background-color: {selectedColor};"
          on:click={openPalette}
        >
          <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 36 36">
            <circle cx="18" cy="18" r="16" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="3"/>
            <circle cx="18" cy="18" r="16" fill="none" stroke="white" stroke-width="3"
              stroke-dasharray="100" stroke-dashoffset={100 - cooldownProgress * 100} stroke-linecap="round"
              class="transition-all duration-1000 ease-linear"/>
          </svg>
          {#if !canPlace}
            <span class="absolute inset-0 flex items-center justify-center text-white text-sm font-bold drop-shadow">
              {secondsRemaining}
            </span>
          {/if}
        </button>

        <!-- Zoom controls - inline on mobile -->
        {#if isMobile}
          <div class="bg-white rounded-full shadow-lg flex items-center overflow-hidden">
            <button class="w-10 h-10 text-neutral-600 active:bg-neutral-100 text-lg font-medium" on:click={() => adjustZoom(-0.25)}>−</button>
            <button class="w-10 h-10 text-neutral-600 active:bg-neutral-100 text-lg font-medium" on:click={() => adjustZoom(0.25)}>+</button>
          </div>
        {/if}
      </div>
    </div>

    <!-- Desktop zoom controls - bottom right -->
    {#if !isMobile}
      <div class="fixed bottom-6 right-6 flex items-center gap-2">
        <div class="bg-white rounded-full shadow-lg flex items-center overflow-hidden">
          <button class="w-10 h-10 text-neutral-600 hover:bg-neutral-50 text-lg font-medium transition-colors" on:click={() => adjustZoom(-0.25)}>−</button>
          <span class="text-xs text-neutral-500 w-12 text-center font-medium">{Math.round(zoom * 100)}%</span>
          <button class="w-10 h-10 text-neutral-600 hover:bg-neutral-50 text-lg font-medium transition-colors" on:click={() => adjustZoom(0.25)}>+</button>
        </div>
      </div>
    {/if}

    <!-- Mysterious raven icon - top left -->
    <a
      href="/"
      class="fixed z-50 {isMobile ? 'top-3 left-3' : 'top-6 left-6'} group"
      title="Kruk.live"
    >
      <div class="bg-neutral-900 {isMobile ? 'w-8 h-8' : 'w-10 h-10'} rounded-full shadow-lg flex items-center justify-center transition-all hover:scale-110 hover:shadow-xl">
        <svg class="{isMobile ? 'w-5 h-5' : 'w-6 h-6'} text-white" viewBox="0 0 1344 768" fill="currentColor">
          <path d="M -0.00 764.79 C-0.00,761.64 0.04,761.62 1.75,763.54 C2.71,764.62 4.15,766.06 4.94,766.75 C6.14,767.79 5.85,768.00 3.19,768.00 C0.26,768.00 -0.00,767.73 -0.00,764.79 ZM 1341.50 766.00 C1342.50,764.90 1343.47,764.00 1343.66,764.00 C1343.84,764.00 1344.00,764.90 1344.00,766.00 C1344.00,767.38 1343.33,768.00 1341.84,768.00 C1339.75,768.00 1339.74,767.94 1341.50,766.00 ZM 474.00 757.90 C474.00,757.30 478.84,751.92 484.75,745.93 L 495.50 735.03 L 505.00 733.94 C517.99,732.45 525.33,731.42 533.00,730.02 C536.58,729.36 541.54,728.51 544.04,728.12 C551.01,727.03 549.67,728.36 578.32,694.00 C582.22,689.33 593.59,676.28 603.59,665.00 C613.59,653.72 623.51,642.39 625.63,639.81 C628.23,636.66 630.30,635.11 631.93,635.06 C633.26,635.03 635.74,634.59 637.43,634.08 C642.83,632.46 679.20,625.86 679.74,626.40 C680.30,626.97 656.85,649.25 629.48,674.19 C620.66,682.21 608.32,693.69 602.05,699.69 L 590.65,710.60 L 595.58,717.17 C600.48,723.72 600.52,723.75 606.40,724.37 C609.64,724.72 617.19,725.00 623.18,725.00 L 634.07,725.00 L 644.07,731.24 C649.58,734.68 655.30,738.47 656.79,739.66 L 659.50,741.84 L 647.50,741.36 C640.90,741.09 629.88,740.45 623.00,739.93 C579.82,736.66 578.40,736.60 571.41,737.83 C560.57,739.73 507.09,747.00 503.97,747.00 C501.38,747.00 494.42,749.69 479.75,756.36 C476.59,757.80 474.00,758.49 474.00,757.90 ZM 452.00,745.85 C452.00,744.33 462.87,734.27 466.87,732.10 C469.47,730.69 486.05,726.72 486.69,727.36 C486.88,727.55 486.14,729.68 485.04,732.10 C483.94,734.52 483.03,737.23 483.02,738.12 C483.00,739.79 478.65,740.97 472.43,740.99 C469.84,741.00 460.49,743.76 453.75,746.50 C452.59,746.97 452.00,746.75 452.00,745.85 ZM 489.68,733.29 C489.40,732.83 490.36,729.99 491.83,726.98 C494.34,721.83 494.71,721.51 498.00,721.63 C537.91,723.10 545.25,723.88 532.78,725.33 C513.42,727.58 493.57,731.08 491.98,732.52 C491.00,733.41 489.97,733.75 489.68,733.29 ZM 440.96,722.07 C441.53,721.00 444.28,717.29 447.07,713.82 C449.87,710.34 453.97,704.01 456.19,699.75 L 460.22,692.00 L 464.86,692.04 C469.48,692.07 488.85,693.32 504.38,694.58 C512.40,695.23 512.58,695.19 515.52,692.36 C517.16,690.77 522.33,684.55 527.00,678.52 C531.67,672.50 544.87,655.85 556.31,641.54 L 577.13,615.50 L 582.31,614.18 C585.17,613.46 591.57,611.77 596.54,610.43 C601.51,609.10 606.46,608.00 607.54,608.00 C609.58,608.00 615.00,615.41 615.00,618.20 C615.00,619.01 610.39,624.10 604.75,629.50 C580.76,652.47 549.00,684.29 549.01,685.35 C549.01,685.98 550.85,688.64 553.08,691.25 C556.51,695.24 557.74,696.02 560.83,696.10 C562.85,696.15 565.57,696.50 566.88,696.87 C569.19,697.51 569.10,697.71 563.88,703.18 L 558.50,708.82 L 545.00,708.29 C537.58,708.01 525.88,708.29 519.00,708.92 C512.12,709.55 496.04,710.90 483.24,711.92 L 459.99,713.78 L 451.00,718.89 C441.11,724.52 439.36,725.07 440.96,722.07 ZM 425.04,710.44 C427.49,707.93 431.75,704.60 434.50,703.04 C439.97,699.94 450.63,696.30 451.56,697.22 C452.23,697.90 447.21,708.20 445.74,709.14 C445.19,709.49 442.59,710.06 439.96,710.41 C437.33,710.76 432.60,711.93 429.44,713.02 C420.75,716.01 420.01,715.58 425.04,710.44 ZM 1042.74,680.77 C1040.00,679.27 1037.25,677.63 1036.63,677.13 C1036.01,676.62 1031.00,673.64 1025.50,670.49 C1020.00,667.33 1009.65,661.30 1002.50,657.08 C985.61,647.09 950.70,626.81 946.56,624.57 C944.18,623.28 930.18,615.07 911.50,604.00 C875.23,582.51 868.22,578.39 865.00,576.64 C863.08,575.59 856.78,571.94 851.00,568.52 C841.69,563.02 820.49,550.59 795.00,535.69 C787.01,531.02 776.00,523.93 776.00,523.45 C776.00,523.33 784.44,525.45 794.75,528.15 C822.61,535.46 843.99,540.96 848.50,541.98 C850.70,542.48 856.78,544.07 862.00,545.50 C867.22,546.94 883.65,551.21 898.50,555.00 C913.35,558.79 928.88,562.81 933.00,563.94 C937.12,565.08 947.70,567.87 956.50,570.15 C970.60,573.80 973.21,574.82 978.50,578.66 C981.80,581.06 988.78,586.03 994.00,589.70 C999.22,593.37 1014.30,604.07 1027.50,613.49 C1086.93,655.89 1104.21,668.13 1114.28,674.96 C1120.21,678.98 1124.88,682.45 1124.66,682.67 C1124.44,682.89 1107.04,683.17 1086.00,683.29 L 1047.74,683.50 L 1042.74,680.77 ZM 1023.50,681.31 C1021.85,681.10 1012.17,679.78 1002.00,678.38 C991.83,676.99 979.96,675.42 975.63,674.90 C960.84,673.13 951.07,671.29 949.13,669.89 C948.07,669.13 929.49,655.18 907.85,638.91 C886.21,622.63 858.67,601.93 846.65,592.91 C820.64,573.37 822.00,574.44 822.00,573.64 C822.00,573.29 827.97,573.00 835.27,573.00 L 848.53,573.00 L 855.52,577.15 C859.36,579.43 868.12,584.52 875.00,588.46 C886.31,594.95 931.34,621.32 945.00,629.47 C948.03,631.27 954.10,634.77 958.50,637.25 C962.90,639.73 968.08,642.64 970.00,643.73 C976.14,647.19 1003.16,663.05 1013.00,668.96 C1018.22,672.09 1024.61,675.87 1027.20,677.34 C1029.78,678.82 1032.17,680.47 1032.51,681.01 C1033.11,681.99 1029.65,682.11 1023.50,681.31 ZM 622.84,619.25 C618.86,613.34 612.35,603.55 608.37,597.50 C604.39,591.45 600.31,585.38 599.32,584.00 C594.56,577.45 580.96,555.71 581.36,555.31 C581.80,554.86 593.11,556.49 624.50,561.50 C636.94,563.48 651.04,565.63 677.67,569.59 C681.39,570.14 681.15,569.13 683.62,594.50 C686.12,620.14 686.18,619.24 682.00,620.16 C675.40,621.60 631.84,630.00 630.96,630.00 C630.47,630.00 626.82,625.16 622.84,619.25 ZM 573.79,604.51 C570.56,599.13 554.68,574.68 534.49,544.00 C521.45,524.20 518.77,519.89 519.21,519.46 C519.40,519.26 527.87,524.45 538.03,530.99 C548.19,537.53 560.05,545.04 564.38,547.69 L 572.26,552.50 L 588.71,577.37 C597.75,591.05 604.78,602.61 604.33,603.06 C603.70,603.68 579.20,610.00 577.44,610.00 C577.25,610.00 575.61,607.53 573.79,604.51 ZM 1089.50,599.88 C1083.98,598.14 1027.83,583.17 992.00,573.89 C964.97,566.89 947.56,562.33 929.25,557.46 C909.08,552.10 887.60,546.55 837.00,533.63 C825.17,530.62 811.90,527.18 807.50,525.99 C798.24,523.49 761.31,514.07 719.00,503.43 C702.78,499.34 688.38,495.60 687.00,495.10 C685.62,494.61 680.90,493.44 676.50,492.51 C672.10,491.58 664.00,489.69 658.50,488.31 C653.00,486.94 645.12,484.98 641.00,483.96 C636.88,482.95 631.92,481.67 630.00,481.13 C628.08,480.58 625.60,479.89 624.50,479.58 C623.40,479.28 614.04,476.98 603.71,474.47 C593.38,471.96 584.00,469.56 582.87,469.15 C581.19,468.52 587.67,463.81 619.16,442.74 C663.80,412.88 706.43,384.11 737.50,362.88 C749.60,354.61 765.89,343.55 773.70,338.30 L 787.90,328.75 L 794.70,334.11 C798.44,337.06 807.12,343.99 814.00,349.51 C820.88,355.02 830.33,362.43 835.00,365.97 C839.67,369.52 848.22,376.28 854.00,381.01 C859.78,385.74 867.20,391.69 870.50,394.22 C892.62,411.22 916.54,430.16 916.78,430.85 C916.93,431.31 914.35,433.35 911.03,435.40 C907.39,437.65 905.02,439.79 905.06,440.81 C905.09,441.74 909.25,445.94 914.31,450.15 C928.13,461.66 942.12,473.21 945.61,476.01 C947.33,477.38 960.15,488.04 974.11,499.70 C1031.36,547.51 1069.05,578.85 1084.37,591.37 C1095.59,600.54 1096.53,602.10 1089.50,599.88 ZM 757.00,566.97 C688.43,565.56 680.24,565.13 661.50,562.01 C655.45,561.00 645.55,559.42 639.50,558.51 C633.45,557.60 623.33,556.02 617.00,555.01 C610.67,554.00 600.33,552.43 594.00,551.52 C575.21,548.80 575.43,548.90 554.26,535.09 C543.39,528.00 530.73,519.79 526.12,516.85 C517.49,511.33 502.17,501.36 459.14,473.21 C445.45,464.26 433.53,456.14 432.66,455.18 C431.79,454.22 424.62,442.20 416.72,428.47 C399.41,398.38 386.47,376.13 375.74,358.00 C371.35,350.58 365.93,341.35 363.70,337.50 C361.46,333.65 357.33,326.67 354.51,322.00 C343.86,304.36 342.01,300.42 341.50,294.32 C341.23,291.12 340.31,274.10 339.45,256.50 C338.58,238.90 337.53,218.65 337.09,211.50 L 336.31,198.50 L 326.27,178.00 C320.75,166.73 315.32,155.39 314.20,152.81 C312.71,149.38 310.48,146.84 305.85,143.31 C298.56,137.76 289.00,129.05 289.00,127.97 C289.00,127.10 297.04,126.26 313.07,125.45 L 324.64,124.87 L 342.20,138.18 C351.86,145.51 363.65,154.54 368.40,158.25 C378.42,166.08 376.22,165.76 407.22,164.05 C416.72,163.52 429.09,162.89 434.71,162.64 L 444.92,162.19 L 454.04,176.35 C459.05,184.13 464.01,191.62 465.05,193.00 C466.09,194.38 468.36,197.89 470.08,200.81 L 473.22,206.13 L 470.97,212.31 C469.74,215.72 467.51,221.20 466.03,224.50 C464.54,227.80 461.64,235.00 459.57,240.50 C457.51,246.00 455.11,252.07 454.24,254.00 C451.52,260.05 437.00,296.43 437.00,297.21 C437.00,297.61 443.64,306.46 451.75,316.87 C459.86,327.29 468.85,338.89 471.73,342.65 C474.60,346.42 483.96,358.50 492.53,369.50 C501.10,380.50 511.55,394.00 515.75,399.50 C519.96,405.00 527.49,414.67 532.50,421.00 C537.50,427.33 548.24,441.16 556.38,451.74 C564.51,462.33 571.47,471.17 571.84,471.40 C572.54,471.83 619.78,484.10 630.50,486.63 C633.80,487.41 637.85,488.44 639.50,488.91 C641.15,489.38 653.30,492.35 666.50,495.51 C679.70,498.66 691.40,501.60 692.50,502.03 C693.60,502.45 702.83,504.83 713.00,507.31 C751.98,516.79 754.27,517.53 764.76,523.80 C770.12,527.00 779.00,532.25 784.50,535.47 C790.00,538.68 798.43,543.72 803.24,546.66 C808.05,549.60 812.17,552.00 812.41,552.00 C813.20,552.00 832.54,563.47 835.54,565.72 L 838.50,567.94 L 814.50,567.80 C801.30,567.72 775.42,567.35 757.00,566.97 ZM 565.74,455.75 C553.06,438.87 539.94,421.92 507.47,380.50 C499.71,370.60 489.62,357.55 485.04,351.50 C476.19,339.80 468.45,329.87 455.49,313.57 C441.83,296.39 442.48,297.66 444.51,292.19 C445.47,289.61 447.62,284.35 449.30,280.50 C450.97,276.65 454.23,268.55 456.54,262.50 C460.43,252.30 468.98,231.11 471.06,226.50 C471.56,225.40 473.24,221.12 474.80,217.00 L 477.64,209.50 L 485.57,209.75 C489.93,209.88 498.45,210.44 504.50,211.00 C510.55,211.55 524.95,212.67 536.50,213.49 C548.05,214.32 562.45,215.45 568.50,216.02 C585.58,217.62 657.97,222.90 663.66,222.96 C666.10,222.99 669.38,225.04 678.16,232.01 C684.40,236.97 692.19,243.16 695.48,245.76 C703.79,252.34 755.71,294.67 760.07,298.43 C766.00,303.53 768.21,305.33 777.80,312.90 C782.86,316.89 787.00,320.74 787.00,321.45 C787.00,322.71 784.65,324.44 761.50,340.19 C755.45,344.31 740.38,354.58 728.00,363.02 C695.61,385.11 684.29,392.77 649.00,416.49 C587.22,458.00 575.15,466.00 574.30,466.00 C573.82,466.00 569.97,461.39 565.74,455.75 ZM 634.00,215.91 C616.91,214.44 585.78,211.98 572.00,211.02 C535.26,208.44 492.94,204.93 491.00,204.30 C489.01,203.64 495.95,200.35 526.50,187.41 C540.25,181.59 553.89,175.73 556.81,174.40 L 562.12,171.97 L 568.81,175.32 C593.80,187.81 647.67,215.41 648.45,216.13 C649.53,217.12 647.68,217.09 634.00,215.91 ZM 474.40,198.73 C470.22,191.96 467.75,188.05 461.89,179.00 C458.86,174.32 454.66,167.83 452.56,164.56 L 448.73,158.62 L 449.36,143.06 C449.71,134.50 450.29,118.25 450.64,106.94 L 451.29,86.38 L 443.39,84.04 C434.80,81.50 433.52,81.10 405.49,72.07 C389.45,66.90 386.19,65.52 384.63,63.22 C382.78,60.51 376.94,56.28 371.78,53.94 C369.34,52.84 368.26,53.08 361.61,56.28 L 354.17,59.87 L 352.97,65.22 L 351.78,70.58 L 356.37,77.16 L 360.97,83.74 L 368.23,83.23 C378.00,82.55 379.27,81.94 382.51,76.33 C384.04,73.67 385.41,71.35 385.56,71.17 C385.70,70.99 389.80,72.15 394.66,73.76 C399.52,75.36 413.06,79.77 424.75,83.56 L 446.00,90.46 L 446.00,96.48 C446.00,109.50 443.77,155.54 443.11,156.25 C442.47,156.92 392.28,160.00 382.50,159.96 C379.15,159.95 377.32,159.01 371.28,154.22 C358.44,144.06 340.77,130.58 336.05,127.38 C328.42,122.19 328.39,122.06 333.26,115.38 C339.92,106.25 345.00,98.28 345.00,96.96 C345.00,96.31 342.00,90.98 338.34,85.13 C316.11,49.64 315.76,49.00 317.24,47.21 C317.88,46.44 326.30,41.87 335.95,37.05 L 353.50,28.29 L 365.00,27.66 C371.33,27.32 384.53,26.37 394.33,25.56 L 412.17,24.08 L 418.33,26.44 C421.73,27.73 429.00,30.90 434.50,33.47 C440.00,36.04 445.85,38.75 447.50,39.48 C449.15,40.21 453.42,42.15 457.00,43.78 C460.58,45.41 466.44,48.08 470.03,49.72 L 476.56,52.69 L 515.59,104.59 C553.83,155.46 561.00,165.23 561.00,166.49 C561.00,167.15 558.27,168.40 537.50,177.28 C530.35,180.34 516.17,186.45 506.00,190.85 C495.83,195.26 485.14,199.79 482.25,200.92 L 477.01,202.97 L 474.40,198.73 ZM 216.27,121.55 C195.54,117.66 188.78,115.93 188.63,114.50 C188.57,113.95 193.24,112.71 199.01,111.75 C204.78,110.79 211.98,109.56 215.00,109.03 C222.80,107.67 242.46,104.46 258.50,101.93 C267.42,100.53 337.00,99.44 337.00,100.70 C337.00,101.27 334.76,104.83 332.03,108.61 C329.30,112.40 326.39,116.46 325.57,117.64 C323.65,120.38 321.80,120.62 288.00,122.43 C233.50,125.35 236.71,125.39 216.27,121.55 ZM 178.50,106.40 C188.91,96.32 196.99,90.43 216.50,78.68 C231.27,69.78 233.23,68.89 242.00,67.09 C247.23,66.01 255.10,64.20 259.50,63.05 C276.99,58.50 310.39,51.12 311.21,51.63 C312.10,52.18 316.23,58.36 318.96,63.25 C321.46,67.71 329.13,80.01 333.73,86.94 C336.08,90.48 338.00,93.74 338.00,94.19 C338.00,94.63 331.08,95.00 322.61,95.00 C314.15,95.00 295.81,95.48 281.86,96.06 C259.39,97.00 253.48,97.63 230.06,101.59 C201.11,106.49 193.05,108.07 182.50,110.91 C178.65,111.95 174.38,113.10 173.00,113.47 C171.17,113.97 172.63,112.09 178.50,106.40 ZM 359.67,74.13 C357.21,69.61 357.11,68.99 358.33,65.46 C359.45,62.22 360.40,61.38 364.79,59.71 L 369.94,57.75 L 374.98,60.99 C381.20,64.98 381.99,67.47 378.85,73.17 C376.30,77.78 374.29,78.74 366.91,78.90 C362.41,79.00 362.26,78.90 359.67,74.13 ZM 0.00,1.56 C0.00,0.70 0.45,0.00 1.00,0.00 C1.55,0.00 2.00,0.42 2.00,0.94 C2.00,1.46 1.55,2.16 1.00,2.50 C0.45,2.84 0.00,2.42 0.00,1.56 ZM 1342.00,1.50 C1340.98,0.27 1341.05,0.00 1342.38,0.00 C1343.27,0.00 1344.00,0.68 1344.00,1.50 C1344.00,2.33 1343.83,3.00 1343.62,3.00 C1343.41,3.00 1342.68,2.33 1342.00,1.50 Z"/>
        </svg>
      </div>
    </a>

    <!-- Stats & Massive Pixel Progress - top right -->
    <div
      class="fixed z-50 {isMobile ? 'top-3 right-3' : 'top-6 right-6'} flex flex-col gap-2"
    >
      <!-- Stats -->
      <div class="bg-white/90 backdrop-blur rounded-xl shadow-lg {isMobile ? 'px-3 py-1.5' : 'px-4 py-2.5'}">
        <h1 class="{isMobile ? 'text-xs' : 'text-sm'} font-semibold text-neutral-900">Pixels</h1>
        <p class="{isMobile ? 'text-[10px]' : 'text-xs'} text-neutral-500">{stats.total_pixels.toLocaleString()} · {stats.unique_users} artists</p>
      </div>

      <!-- Massive Pixel Progress -->
      <div class="bg-white/90 backdrop-blur rounded-xl shadow-lg {isMobile ? 'px-3 py-1.5' : 'px-4 py-2.5'}">
        <div class="flex items-center justify-between gap-2 mb-1">
          <span class="{isMobile ? 'text-xs' : 'text-sm'} font-semibold text-neutral-900">Massive Pixel</span>
          {#if userStats.massive_pixels_available > 0}
            <span class="bg-gradient-to-r from-purple-500 to-pink-500 text-white text-xs font-bold px-2 py-0.5 rounded-full animate-pulse">
              {userStats.massive_pixels_available}
            </span>
          {/if}
        </div>
        <!-- Progress bar -->
        <div class="relative h-2 bg-neutral-200 rounded-full overflow-hidden">
          <div
            class="absolute inset-y-0 left-0 bg-gradient-to-r from-purple-500 to-pink-500 transition-all duration-300"
            style="width: {(userStats.progress_to_next / 15) * 100}%"
          ></div>
        </div>
        <p class="{isMobile ? 'text-[10px]' : 'text-xs'} text-neutral-500 mt-1">
          {userStats.progress_to_next}/15 pixels
        </p>
      </div>

      <!-- Massive Mode Toggle (only show if available) -->
      {#if userStats.massive_pixels_available > 0}
        <button
          on:click={toggleMassiveMode}
          disabled={!canPlace}
          class="relative bg-gradient-to-r from-purple-500 to-pink-500 text-white font-bold py-2 px-4 rounded-xl shadow-lg transition-all overflow-hidden {canPlace ? 'hover:scale-105' : 'opacity-60 cursor-not-allowed'} {isMassiveMode ? 'ring-4 ring-yellow-400' : ''}"
        >
          {#if !canPlace}
            <svg class="absolute inset-0 w-full h-full -rotate-90" viewBox="0 0 100 100" style="pointer-events: none;">
              <circle cx="50" cy="50" r="45" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="10"/>
              <circle cx="50" cy="50" r="45" fill="none" stroke="rgba(255,255,255,0.6)" stroke-width="10"
                stroke-dasharray="283" stroke-dashoffset={283 - cooldownProgress * 283} stroke-linecap="round"
                class="transition-all duration-1000 ease-linear"/>
            </svg>
            <span class="relative text-lg font-bold">{secondsRemaining}</span>
          {:else}
            <span class="text-sm">{isMassiveMode ? '🔥 MASSIVE MODE' : '⭐ Use Massive'}</span>
          {/if}
        </button>
      {/if}
    </div>

    <!-- Coordinates - only on desktop, below stats -->
    {#if hoveredPixel && !isMobile}
      <div class="fixed top-44 right-6 bg-neutral-900 text-white px-3 py-2 rounded-lg text-xs font-mono shadow-lg">
        {hoveredPixel.x}, {hoveredPixel.y}
      </div>
    {/if}
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

  .animate-in {
    animation: fadeIn 0.15s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.95);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  .animate-hint {
    animation: hintFade 4s ease-out forwards;
  }

  @keyframes hintFade {
    0% { opacity: 0; transform: scale(0.9); }
    10% { opacity: 1; transform: scale(1); }
    80% { opacity: 1; }
    100% { opacity: 0; }
  }

  .animate-bounce-x {
    animation: bounceX 1.5s ease-in-out infinite;
  }

  @keyframes bounceX {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-4px); }
  }
</style>
