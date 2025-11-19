# Real-Time Collaboration State Fix

## Problem Fixed ✓

**Issue:** When a new user joined the Kanban board and made any change, it reset the board to their initial state, removing all changes other users had made.

**Root Cause:** Each user's browser maintained its own local copy of the cards in `socket.assigns.cards`. When a user performed an action (add/move/delete card), they broadcasted THEIR local state to all users, overwriting everyone else's changes.

## The Solution

Implemented **server-side state management** using an Elixir Agent (`Rzeczywiscie.KanbanState`). Now there is a single source of truth for all Kanban cards that lives on the server, not in each user's browser.

## Changes Made

### 1. Created Server-Side State Store

**File:** [lib/rzeczywiscie/kanban_state.ex](lib/rzeczywiscie/kanban_state.ex)

This Agent maintains the authoritative state of all Kanban cards:

```elixir
defmodule Rzeczywiscie.KanbanState do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  def get_cards do
    Agent.get(__MODULE__, & &1.cards)
  end

  def add_card(card) do
    Agent.update(__MODULE__, fn state ->
      %{state | cards: [card | state.cards]}
    end)
    get_cards()
  end

  def update_card(card_id, updates) do
    Agent.update(__MODULE__, fn state ->
      cards =
        Enum.map(state.cards, fn card ->
          if card.id == card_id do
            Map.merge(card, updates)
          else
            card
          end
        end)
      %{state | cards: cards}
    end)
    get_cards()
  end

  # ... delete_card/1, move_card/2
end
```

**Key Features:**
- All state mutations return the updated cards list
- Thread-safe (Agent handles concurrent access)
- Single source of truth for all connected users
- Includes the 4 demo cards on startup

### 2. Added to Application Supervision Tree

**File:** [lib/rzeczywiscie/application.ex:17](lib/rzeczywiscie/application.ex#L17)

```elixir
children = [
  # ... other children
  RzeczywiscieWeb.Presence,
  Rzeczywiscie.KanbanState,  # ← Added this
  RzeczywiscieWeb.Endpoint
]
```

The Agent starts when the application starts and stays alive throughout the app's lifecycle.

### 3. Updated LiveView to Use Server State

**File:** [lib/rzeczywiscie_web/live/kanban_board_live.ex](lib/rzeczywiscie_web/live/kanban_board_live.ex)

**Before (Broken):**
```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:cards, initial_cards())  # ← Each user got fresh demo cards
   |> ...}
end

def handle_event("add_card", %{"text" => text, "column" => column}, socket) do
  cards = [new_card | socket.assigns.cards]  # ← Used local state
  broadcast_cards_update(cards)              # ← Broadcasted local state
  {:noreply, assign(socket, :cards, cards)}
end
```

**After (Fixed):**
```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:cards, Rzeczywiscie.KanbanState.get_cards())  # ← Get server state
   |> ...}
end

def handle_event("add_card", %{"text" => text, "column" => column}, socket) do
  cards = Rzeczywiscie.KanbanState.add_card(new_card)  # ← Update server state
  broadcast_cards_update(cards)                         # ← Broadcast server state
  {:noreply, assign(socket, :cards, cards)}
end
```

**All State Operations Updated:**
- `mount/3`: Gets cards from server state
- `handle_event("add_card", ...)`: Uses `KanbanState.add_card/1`
- `handle_event("update_card", ...)`: Uses `KanbanState.update_card/2`
- `handle_event("delete_card", ...)`: Uses `KanbanState.delete_card/1`
- `handle_event("move_card", ...)`: Uses `KanbanState.move_card/2`

## How It Works Now

### Flow Diagram

```
User A adds card                    User B is viewing board
      ↓                                     ↓
KanbanBoardLive                       KanbanBoardLive
      ↓                                     ↓
handle_event("add_card")              (waiting for updates)
      ↓
KanbanState.add_card(card)  ← Single source of truth
      ↓
Returns updated cards list
      ↓
broadcast_cards_update(cards)
      ↓                ↓
PubSub.broadcast      PubSub.broadcast
      ↓                ↓
User A's socket      User B's socket
      ↓                ↓
handle_info           handle_info
      ↓                ↓
Both see the same cards! ✓
```

### Key Improvements

1. **No More State Conflicts**: Server state is the single source of truth
2. **Concurrent Safety**: Agent handles multiple users modifying state simultaneously
3. **Persistent Across Sessions**: Cards persist as long as the app is running
4. **No Local State Drift**: All users always see the exact same state

## Testing

### Scenario 1: Multiple Users Adding Cards

**Before Fix:**
1. User A opens `/kanban` (sees 4 demo cards)
2. User B opens `/kanban` (sees 4 demo cards)
3. User A adds card "Task 1"
4. User A's board shows 5 cards (4 demo + Task 1)
5. User B adds card "Task 2"
6. ❌ Both boards show only 5 cards (4 demo + Task 2)
7. ❌ "Task 1" disappeared!

**After Fix:**
1. User A opens `/kanban` (sees 4 demo cards from server)
2. User B opens `/kanban` (sees same 4 demo cards from server)
3. User A adds card "Task 1"
4. Server state updated: 5 cards
5. Both boards show 5 cards (4 demo + Task 1)
6. User B adds card "Task 2"
7. Server state updated: 6 cards
8. ✓ Both boards show 6 cards (4 demo + Task 1 + Task 2)

### Scenario 2: Card Movement

**Before Fix:**
- Moving a card could reset other users' boards
- Drag-and-drop conflicts caused cards to disappear

**After Fix:**
- All card movements are synchronized through server state
- No conflicts, all users see cards move in real-time

### Scenario 3: New User Joins

**Before Fix:**
- New user got fresh demo cards
- First action overwrote everyone's work

**After Fix:**
- New user sees current server state (all existing cards)
- New user's actions add to existing state, never replace it

## Deployment

These changes require a redeployment to CapRover:

```bash
# Commit changes
git add .
git commit -m "Fix real-time collaboration state management with server-side Agent"

# Push to trigger CapRover deployment
git push origin master
```

After deployment, the KanbanState Agent will start automatically.

## Important Notes

### State Persistence

⚠️ **Current Limitation:** The Agent stores state in memory. If the application restarts, all cards are reset to the initial demo cards.

**For Production Use:** Consider persisting state to the database:
- Option 1: Use GenServer + periodic database writes
- Option 2: Write to database on every state change
- Option 3: Use ETS with periodic snapshots

### Scalability

The current Agent approach works well for:
- Single-server deployments ✓
- Low to medium traffic ✓
- Non-critical data (demo/prototype) ✓

**Not suitable for:**
- Multi-server deployments (state won't sync across servers)
- High-traffic applications (single Agent is a bottleneck)
- Critical data that must survive restarts

### Future Improvements

1. **Database Persistence:**
   ```elixir
   def add_card(card) do
     Agent.update(__MODULE__, fn state ->
       cards = [card | state.cards]
       # Also save to database
       Kanban.create_card(card)
       %{state | cards: cards}
     end)
   end
   ```

2. **Distributed State:**
   Use Phoenix.Tracker or distributed ETS for multi-server support

3. **Card History:**
   Track who created/modified each card and when

## Verification After Deployment

1. **Open `/kanban` in two browsers**
2. **Add a card in Browser A** - should appear in both
3. **Add a card in Browser B** - should appear in both
4. **Both browsers should show all 6 cards** (4 demo + 2 new)
5. **Move a card** - movement should sync to both browsers
6. **Delete a card** - deletion should sync to both browsers

If all tests pass, the real-time collaboration bug is fixed! ✓

---

**Status:** ✅ Implementation complete, ready for deployment
**Files Changed:** 3
- `lib/rzeczywiscie/kanban_state.ex` (new)
- `lib/rzeczywiscie/application.ex` (modified)
- `lib/rzeczywiscie_web/live/kanban_board_live.ex` (modified)

**Next Steps:**
1. Deploy to CapRover
2. Test multi-user collaboration
3. Consider database persistence for production use
4. Apply similar fix to DrawingBoard (see below)

## DrawingBoard Has the Same Issue (Worse!)

The DrawingBoard (`/draw`) has an even worse version of this problem:

**Current Behavior:**
- Drawing strokes are only broadcast to connected users
- NO server-side state at all
- New users see a **blank canvas** even if others have drawn
- If all users disconnect and reconnect, all drawings are lost

**What Happens:**
1. User A draws a cat
2. User B joins → sees blank canvas (User A's cat is invisible to them!)
3. User B draws a dog
4. User A can see User B's dog being drawn in real-time, but User B never sees the cat

**The Fix Needed:**

Create a similar Agent for drawing strokes:

```elixir
# lib/rzeczywiscie/drawing_state.ex
defmodule Rzeczywiscie.DrawingState do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{strokes: []} end, name: __MODULE__)
  end

  def get_strokes do
    Agent.get(__MODULE__, & &1.strokes)
  end

  def add_stroke(stroke) do
    Agent.update(__MODULE__, fn state ->
      %{state | strokes: [stroke | state.strokes]}
    end)
    get_strokes()
  end

  def clear_strokes do
    Agent.update(__MODULE__, fn _state ->
      %{strokes: []}
    end)
    []
  end
end
```

Then update DrawingBoardLive to:
1. `mount/3`: Send existing strokes to new users
2. `handle_event("draw_stroke", ...)`: Save to DrawingState before broadcasting
3. `handle_event("clear_canvas", ...)`: Clear DrawingState before broadcasting

This is a **separate fix** that can be applied after testing the Kanban fix.
