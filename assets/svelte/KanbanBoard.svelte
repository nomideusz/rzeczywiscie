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
    let lightboxImage = null;
    let dragOverColumn = null;
    let dragOverCard = null;  // Track which card we're hovering over for reordering
    let showMagdaWarning = false;
    let magdaMessage = '';
    let isDraggingFile = false;  // Track file drag over the new card form
    let showCelebration = false;
    let celebrationMessage = '';
    let showShameMessage = false;
    let shameMessage = '';
    let completionStreak = 0;

    // Fun celebration messages when completing a task
    const celebrationMessages = [
        "🎉 BOOM! Another one bites the dust!",
        "✨ You're on FIRE! 🔥",
        "💪 Crushing it like a boss!",
        "🏆 Winner winner chicken dinner!",
        "🚀 To infinity and beyond!",
        "🌟 Star performer right here!",
        "😎 Look at you being productive!",
        "🎯 Bullseye! Task completed!",
        "🦸 Superhero mode: ACTIVATED",
        "👏 Standing ovation for you!",
    ];

    // Streak celebration messages
    const streakMessages = [
        "", // 0
        "", // 1
        "🔥 2 in a row! Keep going!",
        "🔥🔥 3 streak! You're unstoppable!",
        "🔥🔥🔥 4 STREAK! Is this even legal?!",
        "⚡ 5 STREAK! LEGENDARY!",
        "💀 6 STREAK! Someone call the fire department!",
        "🌋 7+ STREAK! YOU ARE A MACHINE!!!",
    ];

    // Shame messages when moving tasks back from Done
    const shameMessages = [
        "😬 Oops... wasn't actually done, huh?",
        "🤔 Plot twist: it needs more work",
        "😅 We don't talk about this...",
        "🙈 Pretend this never happened",
        "📝 Back to the drawing board!",
        "🔄 The circle of task life continues...",
        "😏 Someone was a bit optimistic...",
        "🤷 Done? More like 'thought I was done'",
        "⏪ Ctrl+Z in real life",
        "🎭 The task that came back from the dead",
    ];

    // Fun messages for Magda when there are too many TODOs
    const magdaMessages = [
        "🚨 Opamiętaj się, Magda! 🚨",
        "Magda, to już przesada! 😱",
        "Hej Magda, może najpierw dokończ coś? 🤔",
        "Magda... czy Ty chcesz mnie wykończyć? 💀",
        "MAGDA STOP! Lista rośnie szybciej niż moje siły! 😩",
        "Magda, proszę... mam tylko dwie ręce! 🙌",
        "Kolejne zadanie od Magdy... *wzdycha głęboko* 😮‍💨",
        "Magda, czy to zemsta za coś? 🤨",
        "TODO: Porozmawiać z Magdą o jej oczekiwaniach 📝",
        "Magda mode: ACTIVATED 🔥 (wyłącz mnie)",
    ];

    // Check TODO count and show warning
    $: todoCount = cards.filter(c => c.column === 'todo').length;
    $: doneCount = cards.filter(c => c.column === 'done').length;
    $: inProgressCount = cards.filter(c => c.column === 'in_progress').length;
    $: totalCards = cards.length;
    $: progressPercent = totalCards > 0 ? Math.round((doneCount / totalCards) * 100) : 0;
    $: {
        if (todoCount >= 5) {
            magdaMessage = magdaMessages[Math.floor(Math.random() * magdaMessages.length)];
            showMagdaWarning = true;
        } else {
            showMagdaWarning = false;
        }
    }

    const columnColors = {
        'todo': 'border-error',
        'in_progress': 'border-warning',
        'done': 'border-success'
    };

    const columnBgColors = {
        'todo': 'bg-error/5',
        'in_progress': 'bg-warning/5',
        'done': 'bg-success/5'
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

        // Listen for clipboard paste events
        const handlePaste = (e) => {
            const items = e.clipboardData?.items;
            if (!items) return;

            for (let i = 0; i < items.length; i++) {
                if (items[i].type.startsWith('image/')) {
                    e.preventDefault();
                    const file = items[i].getAsFile();
                    if (file) {
                        processImageFile(file);
                    }
                    break;
                }
            }
        };

        document.addEventListener('paste', handlePaste);

        // Listen for ESC key to close lightbox
        const handleKeydown = (e) => {
            if (e.key === 'Escape' && lightboxImage) {
                lightboxImage = null;
            }
        };

        document.addEventListener('keydown', handleKeydown);

        return () => {
            document.removeEventListener('paste', handlePaste);
            document.removeEventListener('keydown', handleKeydown);
        };
    });

    function handleDragStart(e, card) {
        draggedCard = card;
        e.dataTransfer.effectAllowed = 'move';
        // Add visual feedback - slightly faded but still visible
        e.target.style.opacity = '0.8';
        e.target.style.transform = 'rotate(2deg) scale(1.02)';
        e.target.style.boxShadow = '0 10px 25px rgba(0,0,0,0.3)';
    }

    function handleDragEnd(e) {
        e.target.style.opacity = '1';
        e.target.style.transform = '';
        e.target.style.boxShadow = '';
        draggedCard = null;
    }

    function handleDragOver(e, columnId) {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        dragOverColumn = columnId;
        return false;
    }

    function handleDragLeave(e) {
        dragOverColumn = null;
    }

    function handleCardDragOver(e, card) {
        e.preventDefault();
        e.stopPropagation();
        if (draggedCard && draggedCard.id !== card.id) {
            dragOverCard = card.id;
        }
    }

    function handleCardDragLeave(e) {
        dragOverCard = null;
    }

    function handleDrop(e, columnId) {
        e.preventDefault();
        e.stopPropagation();
        dragOverColumn = null;
        dragOverCard = null;

        if (draggedCard && draggedCard.column !== columnId) {
            const fromColumn = draggedCard.column;
            
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

            // Fun messages based on movement
            if (columnId === 'done' && fromColumn !== 'done') {
                showCompletionCelebration();
            } else if (fromColumn === 'done' && columnId !== 'done') {
                showShame();
            }
        }

        return false;
    }

    function handleCardDrop(e, targetCard) {
        e.preventDefault();
        e.stopPropagation();
        dragOverColumn = null;
        dragOverCard = null;

        if (!draggedCard || draggedCard.id === targetCard.id) return;

        const fromColumn = draggedCard.column;
        const targetColumn = targetCard.column;
        const columnCards = getCardsForColumn(targetColumn);
        const targetIndex = columnCards.findIndex(c => c.id === targetCard.id);

        // Reorder locally for instant feedback
        let newCards = cards.filter(c => c.id !== draggedCard.id);
        const updatedDraggedCard = { ...draggedCard, column: targetColumn };
        
        // Find the position to insert
        const insertIndex = newCards.findIndex(c => c.id === targetCard.id);
        newCards.splice(insertIndex, 0, updatedDraggedCard);
        
        cards = newCards;

        // Send to server with position info
        live.pushEvent('reorder_card', {
            card_id: draggedCard.id,
            to_column: targetColumn,
            before_card_id: targetCard.id
        });

        // Fun messages based on movement
        if (targetColumn === 'done' && fromColumn !== 'done') {
            showCompletionCelebration();
        } else if (fromColumn === 'done' && targetColumn !== 'done') {
            showShame();
        }
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
        // Allow card with just text, just image, or both
        if (newCardText.trim() || newCardImage) {
            live.pushEvent('add_card', {
                text: newCardText.trim() || (newCardImage ? '📷 Image' : ''),
                column: columnId,
                image_data: newCardImage
            });
            
            // Show Magda warning when adding to TODO
            if (columnId === 'todo' && todoCount >= 4) {
                magdaMessage = magdaMessages[Math.floor(Math.random() * magdaMessages.length)];
                showMagdaWarning = true;
            }
            
            cancelAddCard();
        }
    }

    function handleFileDragOver(e) {
        e.preventDefault();
        e.stopPropagation();
        isDraggingFile = true;
    }

    function handleFileDragLeave(e) {
        e.preventDefault();
        e.stopPropagation();
        isDraggingFile = false;
    }

    function handleFileDrop(e) {
        e.preventDefault();
        e.stopPropagation();
        isDraggingFile = false;
        
        const files = e.dataTransfer?.files;
        if (files && files.length > 0) {
            const file = files[0];
            if (file.type.startsWith('image/')) {
                processImageFile(file);
            }
        }
    }

    function handleNewCardImage(event) {
        const file = event.target.files[0];
        if (file) {
            processImageFile(file);
        }
    }

    function processImageFile(file) {
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
            // Determine if we're adding a new card or editing
            if (editingCard) {
                editImage = e.target.result;
                editImagePreview = e.target.result;
            } else if (newCardColumn) {
                newCardImage = e.target.result;
                newCardImagePreview = e.target.result;
            }
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
        if (file) {
            processImageFile(file);
        }
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

    // Format relative time (e.g., "2 minutes ago")
    function formatRelativeTime(timestamp) {
        if (!timestamp) return '';
        
        const now = Math.floor(Date.now() / 1000);
        const diff = now - timestamp;
        
        if (diff < 60) return 'just now';
        if (diff < 3600) {
            const mins = Math.floor(diff / 60);
            return `${mins} ${mins === 1 ? 'minute' : 'minutes'} ago`;
        }
        if (diff < 86400) {
            const hours = Math.floor(diff / 3600);
            return `${hours} ${hours === 1 ? 'hour' : 'hours'} ago`;
        }
        if (diff < 604800) {
            const days = Math.floor(diff / 86400);
            return `${days} ${days === 1 ? 'day' : 'days'} ago`;
        }
        const weeks = Math.floor(diff / 604800);
        return `${weeks} ${weeks === 1 ? 'week' : 'weeks'} ago`;
    }

    // Show celebration when completing a task
    function showCompletionCelebration() {
        completionStreak++;
        const streakIndex = Math.min(completionStreak, streakMessages.length - 1);
        const streakMsg = streakMessages[streakIndex];
        
        celebrationMessage = celebrationMessages[Math.floor(Math.random() * celebrationMessages.length)];
        if (streakMsg) {
            celebrationMessage += '\n' + streakMsg;
        }
        showCelebration = true;
        
        setTimeout(() => {
            showCelebration = false;
        }, 3000);
    }

    // Show shame message when un-completing a task
    function showShame() {
        completionStreak = 0; // Reset streak!
        shameMessage = shameMessages[Math.floor(Math.random() * shameMessages.length)];
        showShameMessage = true;
        
        setTimeout(() => {
            showShameMessage = false;
        }, 3000);
    }

    function openLightbox(imageSrc) {
        lightboxImage = imageSrc;
    }

    function closeLightbox() {
        lightboxImage = null;
    }
</script>

<div class="min-h-screen bg-base-100 p-4 sm:p-6">
    <!-- Header - Neo-Brutalist -->
    <div class="container mx-auto px-4 mb-6 sm:mb-8">
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <div class="flex-1">
                <div class="flex items-center gap-3 mb-2">
                    <div class="w-2 h-12 bg-secondary"></div>
                    <h1 class="text-4xl sm:text-5xl font-black uppercase tracking-tight">Kanban</h1>
                    <div class="hidden sm:flex items-center gap-2 ml-4">
                        <div class="px-3 py-1 border-2 border-base-content font-black text-sm">
                            {cards.length} {cards.length === 1 ? 'card' : 'cards'}
                        </div>
                        {#if completionStreak >= 2}
                            <div class="px-3 py-1 bg-warning text-warning-content border-2 border-base-content font-black text-sm animate-pulse">
                                🔥 {completionStreak} streak
                            </div>
                        {/if}
                    </div>
                </div>
                <p class="text-sm sm:text-base opacity-70 font-bold uppercase tracking-wider ml-5">Collaborative Task Board</p>
                
                <!-- Progress Bar -->
                {#if totalCards > 0}
                    <div class="ml-5 mt-3 max-w-md">
                        <div class="flex justify-between text-xs font-bold uppercase tracking-wider mb-1">
                            <span class="opacity-70">Progress</span>
                            <span class="{progressPercent === 100 ? 'text-success' : ''}">{progressPercent}% done</span>
                        </div>
                        <div class="h-3 border-2 border-base-content bg-base-200 relative overflow-hidden">
                            <div 
                                class="h-full transition-all duration-500 {progressPercent === 100 ? 'bg-success' : progressPercent >= 50 ? 'bg-warning' : 'bg-error'}"
                                style="width: {progressPercent}%"
                            ></div>
                        </div>
                        <div class="flex justify-between text-[10px] opacity-50 mt-1">
                            <span>📋 {todoCount} todo</span>
                            <span>⚙️ {inProgressCount} in progress</span>
                            <span>✅ {doneCount} done</span>
                        </div>
                    </div>
                {/if}
            </div>

            <!-- Online Users - Brutalist Style -->
            <div class="border-4 border-base-content bg-base-100 p-4 shadow-[4px_4px_0px_0px_rgba(0,0,0,1)]">
                <div class="text-xs uppercase tracking-widest font-bold opacity-50 mb-2">
                    Online: {users.length}
                </div>
                <div class="flex gap-2">
                    {#each users as user}
                        <div
                            class="w-10 h-10 border-2 border-base-content flex items-center justify-center text-white font-black text-sm"
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

    <!-- Celebration Toast -->
    {#if showCelebration}
        <div class="fixed top-4 right-4 z-50 animate-bounce">
            <div class="border-4 border-success bg-success text-success-content p-4 shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] max-w-sm">
                <div class="text-center">
                    <div class="text-4xl mb-2">🎉</div>
                    <p class="font-black text-lg uppercase whitespace-pre-line">{celebrationMessage}</p>
                    {#if completionStreak >= 2}
                        <div class="mt-2 px-2 py-1 bg-success-content/20 inline-block">
                            <span class="font-bold">🔥 Streak: {completionStreak}</span>
                        </div>
                    {/if}
                </div>
            </div>
        </div>
    {/if}

    <!-- Shame Toast -->
    {#if showShameMessage}
        <div class="fixed top-4 right-4 z-50">
            <div class="border-4 border-warning bg-warning text-warning-content p-4 shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] max-w-sm animate-pulse">
                <div class="text-center">
                    <div class="text-4xl mb-2">😅</div>
                    <p class="font-black text-lg uppercase">{shameMessage}</p>
                    <p class="text-sm opacity-70 mt-1">Streak reset to 0 💔</p>
                </div>
            </div>
        </div>
    {/if}

    <!-- Magda Warning -->
    {#if showMagdaWarning}
        <div class="container mx-auto px-4 mb-4">
            <div class="border-4 border-error bg-error/10 p-4 transition-all shadow-[4px_4px_0px_0px_rgba(239,68,68,1)] animate-pulse">
                <div class="flex items-center justify-between gap-4">
                    <div class="flex items-center gap-3">
                        <span class="text-4xl">⚠️</span>
                        <div>
                            <p class="font-black text-lg uppercase tracking-tight text-error">{magdaMessage}</p>
                            <p class="text-sm opacity-70">Masz już {todoCount} zadań w TODO!</p>
                        </div>
                    </div>
                    <button 
                        class="px-3 py-1 bg-error text-error-content border-2 border-base-content font-bold text-xs uppercase cursor-pointer hover:bg-base-content hover:text-base-100 transition-colors"
                        onclick={() => showMagdaWarning = false}
                    >
                        OK, OK... 😅
                    </button>
                </div>
            </div>
        </div>
    {/if}

    <!-- Kanban Columns - Neo-Brutalist -->
    <div class="container mx-auto px-4 grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-6">
        {#each columns as column}
            <div class="flex flex-col h-full">
                <!-- Column Header - Brutalist -->
                <div class="border-4 border-base-content bg-base-100 p-4 transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5 {column.id === 'todo' && todoCount >= 5 ? 'animate-pulse border-error' : ''}">
                    <div class="absolute top-0 left-0 w-full h-2 {column.id === 'todo' ? 'bg-error' : column.id === 'in_progress' ? 'bg-warning' : 'bg-success'}"></div>
                    <div class="flex justify-between items-center mt-2">
                        <h2 class="text-lg sm:text-xl font-black uppercase tracking-tight">
                            <span class="text-2xl mr-2">{getColumnIcon(column.id)}</span>
                            {column.name}
                            {#if column.id === 'todo' && todoCount >= 5}
                                <span class="text-sm ml-1">🔥</span>
                            {/if}
                        </h2>
                        <div class="px-3 py-1.5 border-2 border-base-content font-black text-sm {column.id === 'todo' && todoCount >= 5 ? 'bg-error text-error-content animate-bounce' : column.id === 'todo' ? 'bg-error/10' : column.id === 'in_progress' ? 'bg-warning/10' : 'bg-success/10'}">
                            {getCardsForColumn(column.id).length}
                            {#if column.id === 'todo' && todoCount >= 7}
                                <span class="ml-1">😱</span>
                            {:else if column.id === 'todo' && todoCount >= 5}
                                <span class="ml-1">😰</span>
                            {/if}
                        </div>
                    </div>
                </div>

                <!-- Cards Container - Brutalist -->
                <div
                    class="flex-1 border-4 border-t-0 border-base-content bg-base-100 p-4 min-h-[500px] transition-colors {columnBgColors[column.id] || 'bg-base-200/30'} {dragOverColumn === column.id ? 'ring-4 ring-primary ring-inset' : ''}"
                    ondragover={(e) => handleDragOver(e, column.id)}
                    ondragleave={handleDragLeave}
                    ondrop={(e) => handleDrop(e, column.id)}
                >
                    <div class="space-y-3 min-h-[400px]">
                        <!-- Empty State -->
                        {#if getCardsForColumn(column.id).length === 0 && newCardColumn !== column.id}
                            <div class="flex flex-col items-center justify-center py-12 opacity-30">
                                <div class="text-6xl mb-4">{getColumnIcon(column.id)}</div>
                                <p class="text-sm font-bold uppercase tracking-wider">No cards yet</p>
                                <p class="text-xs opacity-70 mt-1">Drag a card here or add new</p>
                            </div>
                        {/if}
                        
                        {#each getCardsForColumn(column.id) as card (card.id)}
                            <div
                                draggable="true"
                                ondragstart={(e) => handleDragStart(e, card)}
                                ondragend={handleDragEnd}
                                ondragover={(e) => handleCardDragOver(e, card)}
                                ondragleave={handleCardDragLeave}
                                ondrop={(e) => handleCardDrop(e, card)}
                                class="bg-base-100 border-4 border-base-content p-4 cursor-grab active:cursor-grabbing transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5 {dragOverCard === card.id ? 'border-t-primary border-t-8' : ''}"
                            >
                                {#if editingCard === card.id}
                                    <!-- Edit Mode - Brutalist -->
                                    <div class="space-y-2">
                                        <textarea
                                            id="edit-input-{card.id}"
                                            bind:value={editText}
                                            class="w-full border-2 border-base-content p-2 focus:outline-none focus:border-primary font-mono text-sm"
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
                                                <div class="relative mb-2 border-2 border-base-content bg-base-200 p-1">
                                                    <img src={editImagePreview} alt="Preview" class="w-full h-32 object-contain" />
                                                    <button
                                                        class="absolute top-1 right-1 w-6 h-6 bg-error text-error-content border-2 border-base-content font-bold text-sm cursor-pointer hover:scale-110 transition-transform flex items-center justify-center"
                                                        onclick={removeEditImage}
                                                        type="button"
                                                    >
                                                        ✕
                                                    </button>
                                                </div>
                                            {:else}
                                                <label class="block cursor-pointer">
                                                    <div class="border-2 border-dashed border-base-content/30 hover:border-primary p-3 text-center transition-colors">
                                                        <span class="text-xl">🖼️</span>
                                                        <span class="text-xs font-bold opacity-70 ml-2">Add/Change Image</span>
                                                    </div>
                                                    <input
                                                        type="file"
                                                        accept="image/*"
                                                        onchange={handleEditImage}
                                                        class="hidden"
                                                    />
                                                </label>
                                            {/if}
                                        </div>

                                        <div class="flex gap-2">
                                            <button
                                                class="px-3 py-1 bg-primary text-primary-content border-2 border-base-content font-bold text-xs uppercase hover:bg-secondary hover:text-secondary-content transition-colors cursor-pointer"
                                                onclick={() => saveEdit(card.id)}
                                            >
                                                Save
                                            </button>
                                            <button
                                                class="px-3 py-1 bg-base-200 border-2 border-base-content font-bold text-xs uppercase hover:bg-base-300 transition-colors cursor-pointer"
                                                onclick={cancelEdit}
                                            >
                                                Cancel
                                            </button>
                                        </div>
                                    </div>
                                {:else}
                                    <!-- View Mode - Brutalist -->
                                    <!-- Drag Handle -->
                                    <div class="flex items-center justify-between mb-2">
                                        <div class="flex items-center gap-1 opacity-30 hover:opacity-60 transition-opacity cursor-grab active:cursor-grabbing">
                                            <div class="w-1 h-1 bg-base-content"></div>
                                            <div class="w-1 h-1 bg-base-content"></div>
                                            <div class="w-1 h-1 bg-base-content"></div>
                                            <div class="w-1 h-1 bg-base-content"></div>
                                            <div class="w-1 h-1 bg-base-content"></div>
                                            <div class="w-1 h-1 bg-base-content"></div>
                                        </div>
                                        <div class="flex gap-1">
                                            <button
                                                class="px-2 py-1 bg-base-100 border-2 border-base-content hover:bg-primary hover:text-primary-content transition-colors cursor-pointer"
                                                onclick={() => startEdit(card)}
                                                title="Edit card (E)"
                                            >
                                                ✏️
                                            </button>
                                            <button
                                                class="px-2 py-1 bg-base-100 border-2 border-base-content hover:bg-error hover:text-error-content transition-colors cursor-pointer"
                                                onclick={() => deleteCard(card.id)}
                                                title="Delete card (Del)"
                                            >
                                                🗑️
                                            </button>
                                        </div>
                                    </div>
                                    {#if card.image_data}
                                        <img
                                            src={card.image_data}
                                            alt="Card"
                                            class="w-full h-32 object-contain bg-base-200 border-2 border-base-content mb-2 cursor-pointer hover:opacity-80 transition-opacity"
                                            onclick={() => openLightbox(card.image_data)}
                                            role="button"
                                            tabindex="0"
                                            onkeydown={(e) => e.key === 'Enter' && openLightbox(card.image_data)}
                                        />
                                    {/if}
                                    <p class="whitespace-pre-wrap break-words font-medium leading-relaxed">
                                        {card.text}
                                    </p>
                                    <div class="text-xs uppercase tracking-wider opacity-50 mt-3 font-bold border-t-2 border-base-content/10 pt-2 flex justify-between items-center">
                                        {#if card.created_by}
                                            <span>👤 {card.created_by}</span>
                                        {/if}
                                        {#if card.created_at}
                                            <span class="text-[10px] normal-case">🕐 {formatRelativeTime(card.created_at)}</span>
                                        {/if}
                                    </div>
                                {/if}
                            </div>
                        {/each}

                        <!-- Add New Card - Brutalist -->
                        {#if newCardColumn === column.id}
                            <div 
                                class="relative bg-base-100 border-4 border-primary p-4 {isDraggingFile ? 'ring-4 ring-secondary ring-inset' : ''}"
                                ondragover={handleFileDragOver}
                                ondragleave={handleFileDragLeave}
                                ondrop={handleFileDrop}
                            >
                                <div class="absolute inset-0 bg-primary/10 translate-x-1 translate-y-1 -z-10"></div>
                                
                                <!-- Text Input -->
                                <textarea
                                    id="new-card-input"
                                    bind:value={newCardText}
                                    class="w-full border-2 border-base-content p-2 mb-3 focus:outline-none focus:border-primary font-mono text-sm"
                                    placeholder="Enter card text (optional if adding image)..."
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

                                <!-- Image Upload Zone -->
                                <div class="mb-3">
                                    {#if newCardImagePreview}
                                        <!-- Image Preview -->
                                        <div class="relative border-4 border-base-content bg-base-200 p-2">
                                            <img src={newCardImagePreview} alt="Preview" class="w-full h-40 object-contain" />
                                            <button
                                                class="absolute top-2 right-2 w-8 h-8 bg-error text-error-content border-2 border-base-content font-bold text-lg cursor-pointer hover:scale-110 transition-transform flex items-center justify-center"
                                                onclick={removeNewCardImage}
                                                type="button"
                                            >
                                                ✕
                                            </button>
                                            <div class="absolute bottom-2 left-2 px-2 py-1 bg-success text-success-content border-2 border-base-content text-xs font-bold uppercase">
                                                ✓ Image ready
                                            </div>
                                        </div>
                                    {:else}
                                        <!-- Upload Drop Zone -->
                                        <label class="block cursor-pointer">
                                            <div class="border-4 border-dashed border-base-content/30 hover:border-primary p-6 text-center transition-colors {isDraggingFile ? 'border-secondary bg-secondary/10' : ''}">
                                                <div class="text-4xl mb-2">{isDraggingFile ? '📥' : '🖼️'}</div>
                                                <p class="text-sm font-bold uppercase tracking-wider opacity-70">
                                                    {isDraggingFile ? 'Drop image here!' : 'Drop image or click to upload'}
                                                </p>
                                                <p class="text-xs opacity-50 mt-1">
                                                    Or press <kbd class="px-1 py-0.5 bg-base-200 border border-base-content/30 rounded text-xs">Ctrl+V</kbd> to paste
                                                </p>
                                            </div>
                                            <input
                                                type="file"
                                                accept="image/*"
                                                onchange={handleNewCardImage}
                                                class="hidden"
                                            />
                                        </label>
                                    {/if}
                                </div>

                                <!-- Action Buttons -->
                                <div class="flex gap-2">
                                    <button
                                        class="flex-1 px-4 py-2 bg-primary text-primary-content border-2 border-base-content font-bold text-xs uppercase hover:bg-secondary hover:text-secondary-content transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                                        onclick={() => addCard(column.id)}
                                        disabled={!newCardText.trim() && !newCardImage}
                                    >
                                        {newCardImage && !newCardText.trim() ? '📷 Add Image Card' : '+ Add Card'}
                                    </button>
                                    <button
                                        class="px-4 py-2 bg-base-200 border-2 border-base-content font-bold text-xs uppercase hover:bg-base-300 transition-colors cursor-pointer"
                                        onclick={cancelAddCard}
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </div>
                        {:else}
                            <div class="flex gap-2">
                                <button
                                    class="flex-1 px-4 py-3 border-4 border-base-content bg-base-100 font-bold text-sm uppercase tracking-wide transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5 cursor-pointer"
                                    onclick={() => showAddCard(column.id)}
                                >
                                    + Add Card
                                </button>
                            </div>
                        {/if}
                    </div>
                </div>
            </div>
        {/each}
    </div>

    <!-- Instructions & Tips - Brutalist -->
    <div class="container mx-auto px-4 mt-6 sm:mt-8">
        <div class="grid md:grid-cols-3 gap-4">
            <!-- Tip 1 -->
            <div class="border-4 border-base-content bg-base-100 p-4 transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5">
                <div class="text-2xl mb-2">🖱️</div>
                <p class="text-xs font-bold uppercase tracking-wider">
                    Drag & Drop Cards
                </p>
                <p class="text-xs opacity-60 mt-1">Between columns to update status</p>
            </div>
            
            <!-- Tip 2 -->
            <div class="border-4 border-base-content bg-base-100 p-4 transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5">
                <div class="text-2xl mb-2">⚡</div>
                <p class="text-xs font-bold uppercase tracking-wider">
                    Real-Time Sync
                </p>
                <p class="text-xs opacity-60 mt-1">Open in multiple windows to collaborate</p>
            </div>
            
            <!-- Tip 3 -->
            <div class="border-4 border-base-content bg-base-100 p-4 transition-all shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] hover:shadow-[2px_2px_0px_0px_rgba(0,0,0,1)] hover:-translate-x-0.5 hover:-translate-y-0.5">
                <div class="text-2xl mb-2">📸</div>
                <p class="text-xs font-bold uppercase tracking-wider">
                    Paste Images
                </p>
                <p class="text-xs opacity-60 mt-1">Ctrl+V to attach screenshots</p>
            </div>
        </div>
    </div>

    <!-- Image Lightbox - Brutalist -->
    {#if lightboxImage}
        <div
            class="fixed inset-0 bg-base-content bg-opacity-95 flex items-center justify-center z-50 p-4"
            onclick={closeLightbox}
            role="dialog"
            aria-modal="true"
        >
            <button
                class="absolute top-4 right-4 px-4 py-2 bg-base-100 border-4 border-base-100 font-black text-2xl hover:bg-error hover:text-error-content hover:border-error transition-colors z-10 cursor-pointer"
                onclick={closeLightbox}
                aria-label="Close"
            >
                ×
            </button>
            <div class="border-8 border-base-content bg-base-100 p-2 max-w-[90vw] max-h-[90vh]">
                <img
                    src={lightboxImage}
                    alt="Enlarged view"
                    class="max-w-full max-h-full object-contain"
                    onclick={(e) => e.stopPropagation()}
                />
            </div>
        </div>
    {/if}
</div>
