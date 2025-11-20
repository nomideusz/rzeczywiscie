<script>
    export let counter_id
    export let value = 0
    export let name = "Counter"
    export let live

    let syncing = false

    function increment() {
        syncing = true
        live.pushEvent("increment", {}, () => {
            syncing = false
        })
    }

    function decrement() {
        syncing = true
        live.pushEvent("decrement", {}, () => {
            syncing = false
        })
    }

    function reset() {
        syncing = true
        live.pushEvent("reset", {}, () => {
            syncing = false
        })
    }
</script>

<div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-8">
    <div class="card bg-base-100 shadow-2xl max-w-2xl w-full">
        <div class="card-body items-center text-center">
            <h2 class="card-title text-4xl mb-2">
                🔄 Persistent Counter
            </h2>
            <p class="text-sm text-gray-500 mb-6">
                Real-time sync across all connected clients
            </p>

            <div class="stats shadow mb-6">
                <div class="stat place-items-center">
                    <div class="stat-title">Current Value</div>
                    <div class="stat-value text-primary text-7xl py-4 transition-all duration-300">
                        {value}
                    </div>
                    <div class="stat-desc">
                        {#if syncing}
                            <span class="loading loading-spinner loading-sm"></span> Syncing...
                        {:else}
                            ✓ Saved to database
                        {/if}
                    </div>
                </div>
            </div>

            <div class="flex gap-4 mb-6">
                <button
                    class="btn btn-error btn-lg gap-2"
                    on:click={decrement}
                    disabled={syncing}
                >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4" />
                    </svg>
                    Decrement
                </button>

                <button
                    class="btn btn-success btn-lg gap-2"
                    on:click={increment}
                    disabled={syncing}
                >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    Increment
                </button>
            </div>

            <button
                class="btn btn-outline btn-sm gap-2"
                on:click={reset}
                disabled={syncing}
            >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                Reset to Zero
            </button>

            <div class="divider"></div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 w-full text-left">
                <div class="alert alert-info">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <div>
                        <h3 class="font-bold">Database Backed</h3>
                        <div class="text-xs">Counter ID: {counter_id}</div>
                        <div class="text-xs">Name: {name}</div>
                    </div>
                </div>

                <div class="alert alert-success">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                    </svg>
                    <div>
                        <h3 class="font-bold">Real-time Sync</h3>
                        <div class="text-xs">Opens this page in another tab to see live updates!</div>
                    </div>
                </div>
            </div>

            <div class="mt-6 text-sm text-gray-600">
                <p>💡 <strong>Try it:</strong> Open this page in multiple browser tabs</p>
                <p>All tabs will update in real-time when you click any button!</p>
            </div>
        </div>
    </div>
</div>
