<script>
    import { onMount } from 'svelte';

    export let live;
    export let canvasWidth = 1200;
    export let canvasHeight = 800;

    let canvas;
    let ctx;
    let isDrawing = false;
    let currentColor = '#000000';
    let brushSize = 3;
    let cursors = {};

    const colors = [
        '#000000', '#FF0000', '#00FF00', '#0000FF',
        '#FFFF00', '#FF00FF', '#00FFFF', '#FFFFFF',
        '#FFA500', '#800080', '#FFC0CB', '#A52A2A'
    ];

    const brushSizes = [
        { size: 1, label: 'XS' },
        { size: 3, label: 'S' },
        { size: 6, label: 'M' },
        { size: 10, label: 'L' },
        { size: 15, label: 'XL' }
    ];

    onMount(() => {
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
    });

    function startDrawing(e) {
        isDrawing = true;
        const pos = getMousePos(e);
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

        const pos = getMousePos(e);

        ctx.strokeStyle = currentColor;
        ctx.lineWidth = brushSize;
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();

        live.pushEvent('draw_stroke', {
            x: pos.x,
            y: pos.y,
            color: currentColor,
            size: brushSize,
            type: 'draw'
        });
    }

    function stopDrawing() {
        if (isDrawing) {
            isDrawing = false;
            ctx.beginPath();

            live.pushEvent('draw_stroke', {
                type: 'end'
            });
        }
    }

    function getMousePos(e) {
        const rect = canvas.getBoundingClientRect();
        const scaleX = canvas.width / rect.width;
        const scaleY = canvas.height / rect.height;

        let clientX, clientY;
        if (e.touches && e.touches[0]) {
            clientX = e.touches[0].clientX;
            clientY = e.touches[0].clientY;
        } else {
            clientX = e.clientX;
            clientY = e.clientY;
        }

        return {
            x: (clientX - rect.left) * scaleX,
            y: (clientY - rect.top) * scaleY
        };
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
</script>

<div class="min-h-screen bg-base-200">
    <!-- Header -->
    <div class="bg-base-100 border-b-4 border-base-content">
        <div class="container mx-auto px-4 py-4">
            <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
                <div>
                    <h1 class="text-xl md:text-2xl font-black uppercase tracking-tight">Drawing Board</h1>
                    <p class="text-xs font-bold uppercase tracking-wide opacity-60">Collaborative real-time canvas</p>
                </div>

                <!-- Toolbar -->
                <div class="flex flex-wrap items-center gap-3">
                    <!-- Color Picker -->
                    <div class="flex items-center gap-2">
                        <span class="text-[10px] font-bold uppercase tracking-wide opacity-50 hidden sm:inline">Color:</span>
                        <div class="flex border-2 border-base-content">
                            {#each colors as color}
                                <button
                                    class="w-6 h-6 sm:w-7 sm:h-7 transition-all cursor-pointer {currentColor === color ? 'ring-2 ring-offset-1 ring-base-content scale-110 z-10' : ''}"
                                    style="background-color: {color}; {color === '#FFFFFF' ? 'border-right: 1px solid rgba(0,0,0,0.1);' : ''}"
                                    onclick={() => currentColor = color}
                                ></button>
                            {/each}
                        </div>
                    </div>

                    <!-- Brush Size -->
                    <div class="flex items-center gap-2">
                        <span class="text-[10px] font-bold uppercase tracking-wide opacity-50 hidden sm:inline">Size:</span>
                        <div class="flex border-2 border-base-content">
                            {#each brushSizes as brush}
                                <button
                                    class="px-2 sm:px-3 py-1 text-xs font-bold transition-colors cursor-pointer {brushSize === brush.size ? 'bg-base-content text-base-100' : 'hover:bg-base-200'}"
                                    onclick={() => brushSize = brush.size}
                                >
                                    {brush.label}
                                </button>
                            {/each}
                        </div>
                    </div>

                    <!-- Clear Button -->
                    <button 
                        class="px-3 py-1 text-xs font-bold uppercase tracking-wide border-2 border-error text-error hover:bg-error hover:text-error-content transition-colors cursor-pointer"
                        onclick={handleClearCanvas}
                    >
                        Clear
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Canvas Area -->
    <div class="container mx-auto px-4 py-6">
        <div class="bg-base-100 border-2 border-base-content p-2 inline-block">
            <div class="relative">
                <canvas
                    bind:this={canvas}
                    width={canvasWidth}
                    height={canvasHeight}
                    class="bg-white cursor-crosshair max-w-full"
                    style="max-height: calc(100vh - 200px); width: auto; height: auto;"
                    onmousedown={startDrawing}
                    onmousemove={(e) => { handleMouseMove(e); draw(e); }}
                    onmouseup={stopDrawing}
                    onmouseleave={stopDrawing}
                    ontouchstart={startDrawing}
                    ontouchmove={draw}
                    ontouchend={stopDrawing}
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

        <!-- Tip -->
        <div class="mt-4 text-[10px] font-bold uppercase tracking-wide opacity-40">
            Tip: Open in multiple windows to collaborate in real-time
        </div>
    </div>
</div>
