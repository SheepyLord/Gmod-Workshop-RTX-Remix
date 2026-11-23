# 0247: Queued render calls checked before the game leaves threaded rendering

- Status: Accepted 2026-11-19 (the user's choice after the investigation of their crash at `disconnect`: "I typed
  disconnect to attempt to go back to the main menu and led to the crash. The guard sounds good."); extended by
  [0254](0254-queued-render-calls-checked-again-while-the-game-runs-them.md) (the calls checked again while the game
  runs them); extended by [ADR 0261](0261-queued-render-calls-run-before-the-map-exit-cleanup.md) (the queued calls
  run before the RTX fixes' map-exit cleanup, and calls on a destroyed material variable skipped)
- Package only: the engine guard (`gmcl_`/`gmsv_nlengineguard_win64.dll`, the fixes part,
  [engine_guard/queue_check.h](../../engine_guard/queue_check.h)). No `winmm.dll` change: the user rejected loader
  changes (2026-11-17).

## Context

Seven field games ended with exit 0xC0000409 at `engine.dll`+0x34b9dc: six at a level change (2026-11-14 and 15), one
on 2026-11-19 when the player typed `disconnect` after 1 h 56 min of play. Each came in a start that had just deployed
new RTX content. +0x34b9dc is GMod's crash handler failing (a fast fail while it writes its report); the first fault
is in the game's own dump (RESEARCH.md, "The crash when the game leaves threaded rendering"):

- The console command (`disconnect`, or `map`, which disconnects first) runs Host_Disconnect: `cl.Disconnect` closes
  the client side (its Lua state, its binary modules), then `Host_AllowQueuedMaterialSystem(false)` calls
  `IMaterialSystem::AllowThreading(false)`, whose `ForceSingleThreaded` waits for the render thread and runs what both
  queued render contexts still hold on the main thread (`EndQueue(true)`, `CallQueued`).
- `CallQueued` reached an element whose object had been freed and its memory reused: the object's first word, its
  vtable, was another address in the same allocator's blocks, and `call [vtable + 0x18]` went to address 0 or garbage.
- Whose object: in the four field dumps whose memory map RTX Remix's crash reporter kept, the freed object lay in
  standalone private blocks of 64 KB (once 128 KB, once the allocator's 82 MB first segment): tier0's allocator
  (dlmalloc, which takes memory from Windows in 64 KB steps), the one GMod's own code uses. The game's only Windows
  heap (segments of 1 MB to 0xFD0000 bytes) holds the queued calls of this package's two modules that queue calls of
  their own, the Model Hotloader and RTX Water, which had been the leading suspects; so neither. Of this package's
  modules only the RTX fixes' binary and the debug module allocate through tier0, and neither touches the render list.
- In the 2026-11-19 game the element was the 660th call of the list being recorded when `disconnect` ran (context 1;
  the last rendered frame, 2.2 MB of calls in context 0, had run) and the render thread was idle.
- Which code of GMod's frees an object while its call is still queued, and why only after a deployment, is not
  known: no dump holds the queue's memory (GMod's handler writes a stacks-only dump; the runtime's keeps memory near
  the threads' stacks only). Vanilla GMod's own queued calls are never freed, so a stale element costs it nothing
  until one points at a freed heap object.

## Decision

1. **The engine guard wraps `AllowThreading`'s vtable slot.** On `AllowThreading(false)`, before the engine's own
   function: the material system's `Lock()` (it waits for the frame the render thread was given and makes the hardware
   context the main thread's: what the Model Hotloader's drain does in the same disconnect), a walk of both queued
   contexts' call lists, `Unlock()`, then the engine's `AllowThreading`. Only when `Lock()` returns one of the queued
   contexts (the main thread was recording): then it waited for the render thread, and no list is being run.
2. **A call is live** when its object is readable, its first word points into a loaded image's read-only data (the 32
   bytes of slots 0 to 3 in one section) and slot 3, the one `CallQueued` calls, points into a loaded image's code.
   VirtualQuery and the images' own section headers decide it, never the loader lock, while the material system's lock
   is held. Every other call is unlinked; live calls keep their order, head and tail follow. A list that cannot be
   walked (an element outside its arena, a cycle, a tail that is not its last element) is left as it was. Under SEH.
3. **Only where sure.** Found by machine code, never by address: the one vtable slot whose function refers to both
   "Queued Material System: ENABLED!" and "...DISABLED!" (AllowThreading), the ones that refer to
   "*CMaterialSystem::Lock:" and "*CMaterialSystem::Unlock:", the call right after "DISABLED!" (ForceSingleThreaded),
   its loop over the contexts (`imul rcx,rax,<stride>; add rcx,<first>; add rcx,rdi; call <EndQueue>; inc ebx;
   cmp ebx,<count>`), EndQueue's call of CallQueued, and CallQueued's loop and reset (`call [rax+18h]`, the list's
   `{head, tail, next free byte}` before its arena); each exactly once. The material system object must be a
   `CMaterialSystem` and both contexts `CMatQueuedRenderContext`s (RTTI). Anything else leaves the game as it was and
   says why. Remix starts only, like the colour cap (ADR 0190); pinned; the second copy reads the first's counts.
4. **It says what it dropped.** The console says how many calls a check dropped; `garrysmod/data/native-loader/
   render-queue-check.log` (its last 128 KiB kept past 256 KiB) has each call's list and place, why, what memory its
   object is in, its first words and the classes (module and RTTI name) of the live calls queued around it, so the
   next field occurrence names the code that queued it.
5. **A test path in the real game.** With the launch option `-nl_queue_check_test` each check first appends one call
   whose object's first word is a heap address to the list being recorded, as the engine's own appenders do, and the
   walk must drop it. Only the user's launch options reach it.
6. **Lua reads, never switches.** `nlengineguard.queue_check` says how the install went and `nlengineguard.QueueCheck()`
   returns the checks and drops, in every realm. There is no switch: a server's Lua runs in the client realm.

## Consequences

- The path all seven crashes took can no longer call an object whose memory was reused; the drop is logged instead.
- A call that is dropped does not run. Whatever it was to do at the disconnect (a state change, a release) is not
  done; the engine resets both contexts right after, and the object it would have used is already gone.
- Not covered: a freed object whose memory still holds a live-looking vtable (it is called as before); a stale call run
  by the render thread or by the material system's other runners (a `mat_queue_mode` change, its own flushes); and the
  root cause, which a whole-memory dump of an occurrence would name (`out/crash-34b9dc` has the watcher).
- Cost: one walk per level change and disconnect, of the calls queued since the last frame.
- A game update that moves any of the patterns turns the check off with the reason in `nlengineguard.queue_check`;
  nothing else changes.
