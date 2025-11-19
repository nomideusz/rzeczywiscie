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
        { size: 1, label: 'Thin' },
        { size: 3, label: 'Normal' },
        { size: 6, label: 'Medium' },
        { size: 10, label: 'Thick' },
        { size: 15, label: 'Extra' }
    ];

    onMount(() => {
        ctx = canvas.getContext('2d');
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';

        // Listen for loading existing strokes
        window.addEventListener('phx:load_strokes', (e) => {
            loadStrokes(e.detail.strokes);
        });

        // Listen for drawing events from other users
        window.addEventListener('phx:draw_stroke', (e) => {
            drawStroke(e.detail);
        });

        // Listen for clear canvas events
        window.addEventListener('phx:clear_canvas', () => {
            clearCanvas();
        });

        // Listen for cursor updates from other users
        window.addEventListener('phx:cursor_move', (e) => {
            updateCursor(e.detail);
        });

        // Listen for cursor removal
        window.addEventListener('phx:cursor_remove', (e) => {
            delete cursors[e.detail.user_id];
            cursors = cursors;
        });

        // Request existing strokes from server now that we're ready
        live.pushEvent('request_strokes', {});
    });

    function startDrawing(e) {
        isDrawing = true;
        const pos = getMousePos(e);
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);

        // Send starting position to server
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

        // Draw locally
        ctx.strokeStyle = currentColor;
        ctx.lineWidth = brushSize;
        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();

        // Broadcast to other users
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

            // Signal end of stroke
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
        // Replay all strokes from server state
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Strokes are stored newest first, so reverse to get chronological order
        const chronological = [...strokes].reverse();

        chronological.forEach(stroke => {
            drawStroke(stroke);
        });
    }

    function drawStroke(data) {
        if (data.type === 'start') {
            // Start a new path
            ctx.beginPath();
            ctx.strokeStyle = data.color;
            ctx.lineWidth = data.size;
            ctx.moveTo(data.x, data.y);
            return;
        }

        if (data.type === 'end') {
            // End current path
            ctx.beginPath();
            return;
        }

        // Draw stroke
        ctx.strokeStyle = data.color;
        ctx.lineWidth = data.size;
        ctx.lineTo(data.x, data.y);
        ctx.stroke();
    }

    function handleClearCanvas() {
        clearCanvas();
        live.pushEvent('clear_canvas', {});
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

<div class="flex flex-col items-center gap-4 p-4 bg-base-200 min-h-screen">
    <div class="text-center">
        <h1 class="text-4xl font-bold mb-2">🎨 Collaborative Drawing Board</h1>
        <p class="text-base-content/70">Draw together in real-time!</p>
    </div>

    <!-- Toolbar -->
    <div class="flex flex-wrap gap-4 items-center justify-center bg-base-100 p-4 rounded-lg shadow-lg">
        <!-- Color Picker -->
        <div class="flex gap-2 items-center">
            <span class="font-semibold">Color:</span>
            <div class="flex gap-1">
                {#each colors as color}
                    <button
                        class="w-8 h-8 rounded border-2 transition-all hover:scale-110"
                        class:border-primary={currentColor === color}
                        class:border-base-300={currentColor !== color}
                        style="background-color: {color}"
                        onclick={() => currentColor = color}
                    ></button>
                {/each}
            </div>
        </div>

        <!-- Brush Size -->
        <div class="flex gap-2 items-center">
            <span class="font-semibold">Brush:</span>
            <div class="flex gap-1">
                {#each brushSizes as brush}
                    <button
                        class="btn btn-sm"
                        class:btn-primary={brushSize === brush.size}
                        class:btn-ghost={brushSize !== brush.size}
                        onclick={() => brushSize = brush.size}
                    >
                        {brush.label}
                    </button>
                {/each}
            </div>
        </div>

        <!-- Clear Button -->
        <button class="btn btn-error btn-sm" onclick={handleClearCanvas}>
            Clear Canvas
        </button>
    </div>

    <!-- Canvas Container -->
    <div class="relative bg-white rounded-lg shadow-2xl">
        <canvas
            bind:this={canvas}
            width={canvasWidth}
            height={canvasHeight}
            class="border-4 border-base-300 rounded-lg cursor-crosshair"
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
                class="absolute w-4 h-4 rounded-full pointer-events-none transition-all duration-75"
                style="
                    left: {(cursor.x / canvasWidth) * 100}%;
                    top: {(cursor.y / canvasHeight) * 100}%;
                    background-color: {cursor.color};
                    transform: translate(-50%, -50%);
                    box-shadow: 0 0 10px {cursor.color};
                "
            ></div>
        {/each}
    </div>

    <div class="text-sm text-base-content/60">
        Tip: Open this page in multiple browser windows to see real-time collaboration!
    </div>
</div>
