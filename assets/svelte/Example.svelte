<script>
    // The number prop is reactive
    // This means if the server assigns the number, it will update in the frontend
    export let number = 1
    // live contains all exported LiveView methods available to the frontend
    export let live

    function increase() {
        // This pushes the event over the websocket
        live.pushEvent("set_number", {number: number + 1}, () => {})
    }

    function decrease() {
        live.pushEvent("set_number", {number: number - 1}, () => {})
    }
</script>

<div class="p-8 max-w-md mx-auto">
    <h1 class="text-3xl font-bold mb-6 text-gray-800">
        LiveSvelte Counter Example
    </h1>

    <div class="bg-white rounded-lg shadow-lg p-6">
        <p class="text-xl mb-4 text-center">
            The number is <span class="font-bold text-blue-600">{number}</span>
        </p>

        <div class="flex gap-4 justify-center">
            <button
                on:click={decrease}
                class="px-6 py-2 bg-red-500 text-white rounded hover:bg-red-600 transition-colors"
            >
                -
            </button>
            <button
                on:click={increase}
                class="px-6 py-2 bg-green-500 text-white rounded hover:bg-green-600 transition-colors"
            >
                +
            </button>
        </div>
    </div>
</div>
