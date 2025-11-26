<script>
    import { onMount, onDestroy } from 'svelte';

    export let live;
    export let canvasWidth = 1200;
    export let canvasHeight = 800;

    let canvas;
    let ctx;
    let canvasContainer;
    let isDrawing = false;
    let currentColor = '#000000';
    let brushSize = 3;
    let cursors = {};
    let isMobile = false;
    let lastPos = null;

    const colors = [
        '#000000', '#FF0000', '#00FF00', '#0000FF',
        '#FFFF00', '#FF00FF', '#00FFFF', '#FFFFFF',
        '#FFA500', '#800080', '#FFC0CB', '#A52A2A'
    ];

    const brushSizes = [
        { size: 2, label: 'XS' },
        { size: 4, label: 'S' },
        { size: 8, label: 'M' },
        { size: 14, label: 'L' },
        { size: 22, label: 'XL' }
    ];

    onMount(() => {
        isMobile = 'ontouchstart' in window || navigator.maxTouchPoints > 0;
        
        ctx = canvas.getContext('2d');
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';

        window.addEventListener('phx:load_strokes', (e) => {
            loadStrokes(e.detail.strokes);
        });

        window.addEventListener('phx:draw_stroke', (e) => {
            drawStroke(e.detail);
        });

        window.addEventListener('phx:clear_canvas', () => {
            clearCanvas();
        });

        window.addEventListener('phx:cursor_move', (e) => {
            updateCursor(e.detail);
        });

        window.addEventListener('phx:cursor_remove', (e) => {
            delete cursors[e.detail.user_id];
            cursors = cursors;
        });

        live.pushEvent('request_strokes', {});

        // Prevent scrolling on touch
        const preventScroll = (e) => {
            if (isDrawing) {
                e.preventDefault();
            }
        };
        document.addEventListener('touchmove', preventScroll, { passive: false });

        return () => {
            document.removeEventListener('touchmove', preventScroll);
        };
    });

    function getMousePos(e) {
        const rect = canvas.getBoundingClientRect();
        const scaleX = canvas.width / rect.width;
        const scaleY = canvas.height / rect.height;

        let clientX, clientY;
        if (e.touches && e.touches.length > 0) {
            clientX = e.touches[0].clientX;
            clientY = e.touches[0].clientY;
        } else if (e.changedTouches && e.changedTouches.length > 0) {
            clientX = e.changedTouches[0].clientX;
            clientY = e.changedTouches[0].clientY;
        } else {
            clientX = e.clientX;
            clientY = e.clientY;
        }

        return {
            x: (clientX - rect.left) * scaleX,
            y: (clientY - rect.top) * scaleY
        };
    }

    function startDrawing(e) {
        e.preventDefault();
        isDrawing = true;
        const pos = getMousePos(e);
        lastPos = pos;
        
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);

        live.pushEvent('draw_stroke', {
            x: pos.x,
            y: pos.y,
            color: currentColor,
            size: brushSize,
            type: 'start'
        });
    }

    function draw(e) {
        if (!isDrawing) return;
        e.preventDefault();

        const pos = getMousePos(e);

        // Draw locally
        ctx.strokeStyle = currentColor;
        ctx.lineWidth = brushSize;
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);

        // Broadcast to other users
        live.pushEvent('draw_stroke', {
            x: pos.x,
            y: pos.y,
            color: currentColor,
            size: brushSize,
            type: 'draw'
        });

        lastPos = pos;
    }

    function stopDrawing(e) {
        if (isDrawing) {
            if (e) e.preventDefault();
            isDrawing = false;
            lastPos = null;
            ctx.beginPath();

            live.pushEvent('draw_stroke', {
                type: 'end'
            });
        }
    }

    function loadStrokes(strokes) {
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        const chronological = [...strokes].reverse();

        chronological.forEach(stroke => {
            drawStroke(stroke);
        });
    }

    function drawStroke(data) {
        if (data.type === 'start') {
            ctx.beginPath();
            ctx.strokeStyle = data.color;
            ctx.lineWidth = data.size;
            ctx.moveTo(data.x, data.y);
            return;
        }

        if (data.type === 'end') {
            ctx.beginPath();
            return;
        }

        ctx.strokeStyle = data.color;
        ctx.lineWidth = data.size;
        ctx.lineTo(data.x, data.y);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(data.x, data.y);
    }

    function handleClearCanvas() {
        if (confirm('Clear the entire canvas? This cannot be undone.')) {
            clearCanvas();
            live.pushEvent('clear_canvas', {});
        }
    }

    function clearCanvas() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    }

    function handleMouseMove(e) {
        const pos = getMousePos(e);
        live.pushEvent('cursor_move', {
            x: pos.x,
            y: pos.y
        });
    }

    function updateCursor(data) {
        cursors[data.user_id] = {
            x: data.x,
            y: data.y,
            color: data.color || '#999'
        };
        cursors = cursors;
    }

    // Touch handlers that prevent default and handle properly
    function handleTouchStart(e) {
        e.preventDefault();
        e.stopPropagation();
        startDrawing(e);
    }

    function handleTouchMove(e) {
        e.preventDefault();
        e.stopPropagation();
        draw(e);
    }

    function handleTouchEnd(e) {
        e.preventDefault();
        e.stopPropagation();
        stopDrawing(e);
    }
</script>

<div class="h-[calc(100vh-4rem)] bg-base-200 flex flex-col">
    <!-- Sub-header with toolbar -->
    <div class="bg-base-100 border-b-2 border-base-content flex-shrink-0">
        <div class="container mx-auto px-4 py-2">
            <div class="flex flex-wrap items-center justify-between gap-2">
                <!-- Title + Color picker -->
                <div class="flex items-center gap-3">
                    <h1 class="text-base md:text-lg font-black uppercase tracking-tight">✏️ Draw</h1>
                    
                    <div class="flex border-2 border-base-content">
                        {#each colors as color}
                            <button
                                class="w-5 h-5 md:w-6 md:h-6 transition-all cursor-pointer relative {currentColor === color ? 'z-10' : ''}"
                                style="background-color: {color}; {color === '#FFFFFF' ? 'border-right: 1px solid rgba(0,0,0,0.1);' : ''}"
                                onclick={() => currentColor = color}
                            >
                                {#if currentColor === color}
                                    <div class="absolute inset-0 border-2 border-base-content"></div>
                                {/if}
                            </button>
                        {/each}
                    </div>
                </div>

                <!-- Brush Size + Clear -->
                <div class="flex items-center gap-2">
                    <div class="flex border-2 border-base-content">
                        {#each brushSizes as brush}
                            <button
                                class="w-7 h-7 text-[10px] font-bold transition-colors cursor-pointer flex items-center justify-center {brushSize === brush.size ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
                                onclick={() => brushSize = brush.size}
                            >
                                {brush.label}
                            </button>
                        {/each}
                    </div>
                    
                    <button 
                        class="px-2 py-1 text-xs font-bold uppercase tracking-wide border-2 border-error text-error hover:bg-error hover:text-error-content transition-colors cursor-pointer"
                        onclick={handleClearCanvas}
                    >
                        Clear
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Canvas Area - fills remaining space -->
    <div 
        class="flex-1 flex items-center justify-center p-2 md:p-4 overflow-hidden"
        bind:this={canvasContainer}
    >
        <div class="bg-base-100 border-2 border-base-content p-1 max-w-full max-h-full">
            <div class="relative">
                <canvas
                    bind:this={canvas}
                    width={canvasWidth}
                    height={canvasHeight}
                    class="bg-white cursor-crosshair block touch-none"
                    style="max-width: calc(100vw - 32px); max-height: calc(100vh - 160px); width: auto; height: auto;"
                    onmousedown={startDrawing}
                    onmousemove={(e) => { handleMouseMove(e); draw(e); }}
                    onmouseup={stopDrawing}
                    onmouseleave={stopDrawing}
                    ontouchstart={handleTouchStart}
                    ontouchmove={handleTouchMove}
                    ontouchend={handleTouchEnd}
                    ontouchcancel={handleTouchEnd}
                ></canvas>

                <!-- Other users' cursors -->
                {#each Object.entries(cursors) as [userId, cursor]}
                    <div
                        class="absolute w-3 h-3 rounded-full pointer-events-none transition-all duration-75 border-2 border-white"
                        style="
                            left: {(cursor.x / canvasWidth) * 100}%;
                            top: {(cursor.y / canvasHeight) * 100}%;
                            background-color: {cursor.color};
                            transform: translate(-50%, -50%);
                            box-shadow: 0 0 8px {cursor.color};
                        "
                    ></div>
                {/each}
            </div>
        </div>
    </div>

    <!-- Tip bar at bottom -->
    <div class="bg-base-100 border-t border-base-content/20 py-2 text-center flex-shrink-0">
        <p class="text-[10px] font-bold uppercase tracking-wide opacity-40">
            {isMobile ? 'Draw with finger • Pinch to zoom' : 'Open in multiple windows to collaborate'}
        </p>
    </div>
</div>

<style>
    canvas {
        touch-action: none;
        -webkit-touch-callout: none;
        -webkit-user-select: none;
        user-select: none;
    }
</style>
