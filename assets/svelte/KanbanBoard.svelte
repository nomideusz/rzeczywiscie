<script>
    import { onMount } from 'svelte';

    export let live;
    export let columns = [];
    export let cards = [];
    export let users = [];

    let draggedCard = null;
    let newCardText = '';
    let newCardColumn = null;
    let newCardImage = null;
    let newCardImagePreview = null;
    let editingCard = null;
    let editText = '';
    let editImage = null;
    let editImagePreview = null;

    const columnColors = {
        'todo': 'bg-red-50 border-red-200',
        'in_progress': 'bg-yellow-50 border-yellow-200',
        'done': 'bg-green-50 border-green-200'
    };

    onMount(() => {
        // Listen for card updates from server
        window.addEventListener('phx:cards_updated', (e) => {
            cards = e.detail.cards;
        });

        // Listen for presence updates
        window.addEventListener('phx:presence_update', (e) => {
            users = e.detail.users;
        });
    });

    function handleDragStart(e, card) {
        draggedCard = card;
        e.dataTransfer.effectAllowed = 'move';
        e.target.style.opacity = '0.4';
    }

    function handleDragEnd(e) {
        e.target.style.opacity = '1';
        draggedCard = null;
    }

    function handleDragOver(e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        return false;
    }

    function handleDrop(e, columnId) {
        e.preventDefault();
        e.stopPropagation();

        if (draggedCard && draggedCard.column !== columnId) {
            // Update locally for instant feedback
            cards = cards.map(c =>
                c.id === draggedCard.id
                    ? { ...c, column: columnId }
                    : c
            );

            // Send to server
            live.pushEvent('move_card', {
                card_id: draggedCard.id,
                to_column: columnId
            });
        }

        return false;
    }

    function showAddCard(columnId) {
        newCardColumn = columnId;
        newCardText = '';
        setTimeout(() => {
            document.getElementById('new-card-input')?.focus();
        }, 100);
    }

    function cancelAddCard() {
        newCardColumn = null;
        newCardText = '';
        newCardImage = null;
        newCardImagePreview = null;
    }

    function addCard(columnId) {
        if (newCardText.trim()) {
            live.pushEvent('add_card', {
                text: newCardText.trim(),
                column: columnId,
                image_data: newCardImage
            });
            cancelAddCard();
        }
    }

    function handleNewCardImage(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (file.size > 3 * 1024 * 1024) {
            alert('Image must be smaller than 3MB');
            return;
        }

        if (!file.type.startsWith('image/')) {
            alert('Please select an image file');
            return;
        }

        const reader = new FileReader();
        reader.onload = (e) => {
            newCardImage = e.target.result;
            newCardImagePreview = e.target.result;
        };
        reader.readAsDataURL(file);
    }

    function removeNewCardImage() {
        newCardImage = null;
        newCardImagePreview = null;
    }

    function startEdit(card) {
        editingCard = card.id;
        editText = card.text;
        editImage = card.image_data;
        editImagePreview = card.image_data;
        setTimeout(() => {
            document.getElementById(`edit-input-${card.id}`)?.focus();
        }, 100);
    }

    function cancelEdit() {
        editingCard = null;
        editText = '';
        editImage = null;
        editImagePreview = null;
    }

    function saveEdit(cardId) {
        if (editText.trim()) {
            live.pushEvent('update_card', {
                card_id: cardId,
                text: editText.trim(),
                image_data: editImage
            });
        }
        cancelEdit();
    }

    function handleEditImage(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (file.size > 3 * 1024 * 1024) {
            alert('Image must be smaller than 3MB');
            return;
        }

        if (!file.type.startsWith('image/')) {
            alert('Please select an image file');
            return;
        }

        const reader = new FileReader();
        reader.onload = (e) => {
            editImage = e.target.result;
            editImagePreview = e.target.result;
        };
        reader.readAsDataURL(file);
    }

    function removeEditImage() {
        editImage = null;
        editImagePreview = null;
    }

    function deleteCard(cardId) {
        if (confirm('Delete this card?')) {
            live.pushEvent('delete_card', { card_id: cardId });
        }
    }

    function getCardsForColumn(columnId) {
        return cards.filter(c => c.column === columnId);
    }

    function getColumnIcon(columnId) {
        const icons = {
            'todo': '📋',
            'in_progress': '⚙️',
            'done': '✅'
        };
        return icons[columnId] || '📌';
    }
</script>

<div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-6">
    <!-- Header -->
    <div class="max-w-7xl mx-auto mb-6">
        <div class="flex justify-between items-center">
            <div>
                <h1 class="text-4xl font-bold text-gray-800 mb-2">🗂️ Kanban Board</h1>
                <p class="text-gray-600">Collaborative task management in real-time</p>
            </div>

            <!-- Online Users -->
            <div class="bg-white rounded-lg shadow-md p-4">
                <div class="text-sm font-semibold text-gray-600 mb-2">Online ({users.length})</div>
                <div class="flex gap-2">
                    {#each users as user}
                        <div
                            class="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-lg"
                            style="background-color: {user.color}"
                            title={user.name}
                        >
                            {user.name.charAt(0).toUpperCase()}
                        </div>
                    {/each}
                </div>
            </div>
        </div>
    </div>

    <!-- Kanban Columns -->
    <div class="max-w-7xl mx-auto grid grid-cols-1 md:grid-cols-3 gap-6">
        {#each columns as column}
            <div class="flex flex-col h-full">
                <!-- Column Header -->
                <div class="bg-white rounded-t-lg shadow-md p-4 border-b-4 {column.id === 'todo' ? 'border-red-400' : column.id === 'in_progress' ? 'border-yellow-400' : 'border-green-400'}">
                    <div class="flex justify-between items-center">
                        <h2 class="text-xl font-bold text-gray-800">
                            {getColumnIcon(column.id)} {column.name}
                        </h2>
                        <span class="badge badge-lg">{getCardsForColumn(column.id).length}</span>
                    </div>
                </div>

                <!-- Cards Container -->
                <div
                    class="flex-1 bg-white rounded-b-lg shadow-md p-4 min-h-[500px] {columnColors[column.id] || 'bg-gray-50'}"
                    ondragover={handleDragOver}
                    ondrop={(e) => handleDrop(e, column.id)}
                >
                    <div class="space-y-3">
                        {#each getCardsForColumn(column.id) as card (card.id)}
                            <div
                                draggable="true"
                                ondragstart={(e) => handleDragStart(e, card)}
                                ondragend={handleDragEnd}
                                class="bg-white rounded-lg shadow-md p-4 border-2 border-gray-200 hover:border-blue-400 cursor-move transition-all hover:shadow-lg"
                            >
                                {#if editingCard === card.id}
                                    <!-- Edit Mode -->
                                    <div class="space-y-2">
                                        <textarea
                                            id="edit-input-{card.id}"
                                            bind:value={editText}
                                            class="textarea textarea-bordered w-full"
                                            rows="2"
                                            onkeydown={(e) => {
                                                if (e.key === 'Enter' && !e.shiftKey) {
                                                    e.preventDefault();
                                                    saveEdit(card.id);
                                                } else if (e.key === 'Escape') {
                                                    cancelEdit();
                                                }
                                            }}
                                        ></textarea>

                                        <!-- Image Upload for Edit -->
                                        <div>
                                            {#if editImagePreview}
                                                <div class="relative mb-2">
                                                    <img src={editImagePreview} alt="Preview" class="w-full h-32 object-cover rounded" />
                                                    <button
                                                        class="absolute top-1 right-1 btn btn-xs btn-error"
                                                        onclick={removeEditImage}
                                                        type="button"
                                                    >
                                                        ✕
                                                    </button>
                                                </div>
                                            {:else}
                                                <input
                                                    type="file"
                                                    accept="image/*"
                                                    onchange={handleEditImage}
                                                    class="file-input file-input-bordered file-input-sm w-full"
                                                />
                                            {/if}
                                        </div>

                                        <div class="flex gap-2">
                                            <button
                                                class="btn btn-sm btn-primary"
                                                onclick={() => saveEdit(card.id)}
                                            >
                                                Save
                                            </button>
                                            <button
                                                class="btn btn-sm btn-ghost"
                                                onclick={cancelEdit}
                                            >
                                                Cancel
                                            </button>
                                        </div>
                                    </div>
                                {:else}
                                    <!-- View Mode -->
                                    {#if card.image_data}
                                        <img src={card.image_data} alt="Card" class="w-full h-32 object-cover rounded mb-2" />
                                    {/if}
                                    <div class="flex justify-between items-start gap-2">
                                        <p class="text-gray-800 flex-1 whitespace-pre-wrap break-words">
                                            {card.text}
                                        </p>
                                        <div class="flex gap-1">
                                            <button
                                                class="btn btn-xs btn-ghost"
                                                onclick={() => startEdit(card)}
                                                title="Edit card"
                                            >
                                                ✏️
                                            </button>
                                            <button
                                                class="btn btn-xs btn-ghost text-red-500"
                                                onclick={() => deleteCard(card.id)}
                                                title="Delete card"
                                            >
                                                🗑️
                                            </button>
                                        </div>
                                    </div>
                                    {#if card.created_by}
                                        <div class="text-xs text-gray-500 mt-2">
                                            Created by {card.created_by}
                                        </div>
                                    {/if}
                                {/if}
                            </div>
                        {/each}

                        <!-- Add New Card -->
                        {#if newCardColumn === column.id}
                            <div class="bg-white rounded-lg shadow-md p-4 border-2 border-blue-400">
                                <textarea
                                    id="new-card-input"
                                    bind:value={newCardText}
                                    class="textarea textarea-bordered w-full mb-2"
                                    placeholder="Enter card text..."
                                    rows="2"
                                    onkeydown={(e) => {
                                        if (e.key === 'Enter' && !e.shiftKey) {
                                            e.preventDefault();
                                            addCard(column.id);
                                        } else if (e.key === 'Escape') {
                                            cancelAddCard();
                                        }
                                    }}
                                ></textarea>

                                <!-- Image Upload for New Card -->
                                <div class="mb-2">
                                    {#if newCardImagePreview}
                                        <div class="relative">
                                            <img src={newCardImagePreview} alt="Preview" class="w-full h-32 object-cover rounded" />
                                            <button
                                                class="absolute top-1 right-1 btn btn-xs btn-error"
                                                onclick={removeNewCardImage}
                                                type="button"
                                            >
                                                ✕
                                            </button>
                                        </div>
                                    {:else}
                                        <input
                                            type="file"
                                            accept="image/*"
                                            onchange={handleNewCardImage}
                                            class="file-input file-input-bordered file-input-sm w-full"
                                        />
                                    {/if}
                                </div>

                                <div class="flex gap-2">
                                    <button
                                        class="btn btn-sm btn-primary"
                                        onclick={() => addCard(column.id)}
                                    >
                                        Add Card
                                    </button>
                                    <button
                                        class="btn btn-sm btn-ghost"
                                        onclick={cancelAddCard}
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </div>
                        {:else}
                            <button
                                class="btn btn-outline btn-block btn-sm"
                                onclick={() => showAddCard(column.id)}
                            >
                                + Add Card
                            </button>
                        {/if}
                    </div>
                </div>
            </div>
        {/each}
    </div>

    <!-- Instructions -->
    <div class="max-w-7xl mx-auto mt-6 text-center text-sm text-gray-600">
        💡 Tip: Drag cards between columns to update their status. Open in multiple windows to see real-time collaboration!
    </div>
</div>
