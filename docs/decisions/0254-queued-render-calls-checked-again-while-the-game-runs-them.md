# 0254: Queued render calls checked again while the game runs them

- Status: Accepted 2026-11-21 (the user's report: "Disconnecting from a map / server still causes fast termination
  crash, when a session is long / with lots of things spawned"); extends
  [ADR 0247](0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md), the guard the user chose on
  2026-11-19, which stays as it is. Its reading of the crash corrected by
  [ADR 0261](0261-queued-render-calls-run-before-the-map-exit-cleanup.md) (the element was intact; its call's material
  variable had been destroyed), which also changes decision 7 below; the mechanism stays.
- Package only: the engine guard (`gmcl_`/`gmsv_nlengineguard_win64.dll`, the fixes part,
  [engine_guard/run_check.h](../../engine_guard/run_check.h)). No `winmm.dll` change: the user rejected loader
  changes (2026-11-17).

## Context

The field game closed again at `disconnect` with exit 0xC0000409 (2026-11-22 01:50 UTC, after 1 h 37 min of play),
in the package that had ADR 0247's check (RESEARCH.md, "The crash at disconnect that the check did not catch"):

- The same path as before: the `disconnect` callback, `AllowThreading(false)`, `ForceSingleThreaded`,
  `EndQueue(true)` on context 1, `CallQueued`. The 660th element of context 1 (element offset +0x2938 in its arena),
  exactly the element of the 2026-11-19 crash. Its object pointer led into a 256 KB heap block whose first word was
  another address in that block (a free list's link); the call went through it to a vcall thunk and faulted.
- **The check ran and passed everything.** The runtime's crash dump keeps the main thread's whole stack. Below the
  engine's frames lies the check's own working memory: its array of the live vtables it saw (14 of them, followed by
  its count, 14), then the material system's `Unlock` return address where the check calls it. The 14 classes are all
  GMod's own queued functors (`CMemberFunctorN<...>` with `CRefCountServiceNull`, from materialsystem.dll, and one of
  studiorender's for `DestroyDecalList`). Nothing was dropped, so no log was written.
- **GMod never puts a queued call on the heap.** Every inline append site in materialsystem.dll, studiorender.dll,
  engine.dll and client.dll (each found by its "CMatRenderCallQueue out of memory!" reference) takes the functor from
  the context's own arena: the pointer at list+0x1000018 is the context's own next-free-byte word (set so in the
  material system's constructor), so a functor and its element sit side by side in the context. A heap pointer in an
  element is therefore not something GMod queued: the element's words were written over **after** the check, while
  `ForceSingleThreaded` ran the 659 calls before it. The stack just below `CallQueued`'s frame holds an allocation's
  frames (tier0's `CStdMemAlloc::Alloc`, the allocator and its lock) from one of those calls.
- Which call writes there, and why only in long sessions with many things spawned, is not known. The fixed element
  points at a write through a stale pointer into the arena, or at heap bookkeeping that reaches it.

## Decision

1. **The check keeps every element.** After its walk (ADR 0247, under the material system's lock, the render thread
   idle) it records each element of both lists: its two words (next, object), the object's first four words and the
   16 bytes before the element (where the engine lays the call's own object). Only when the walk ran and the lists
   could be read; a list that cannot be walked is not kept.
2. **The run goes through the check.** For the length of the engine's own `AllowThreading(false)`, and only then, the
   ten bytes of `CallQueued`'s per-call dispatch (`mov rcx,[rbx+8]; mov rax,[rcx]; call [rax+18h]`) are rewritten in
   memory to `mov rcx,rbx; call [rip+slot]; nop`, the slot (a read-only page within reach) holding the check's step
   function. The render thread is idle (the check's `Lock` waited for its frame and only the main thread hands it
   another), and the bytes are put back as soon as the engine's function returns, only where they are still the
   check's. Nothing on disk changes (AGENTS.md rule 2).
3. **What the step does, per element:**
   - an element whose two words changed since the check is put back as the check saw it, and its call runs if its
     object is unchanged (the field's case);
   - a call whose object's first words, or the 16 bytes before its element, changed is skipped;
   - an element reached a second time in one run is skipped and its list ends there: no call runs twice;
   - after each call, the element's link is put back if the call changed it, unless the element was the list's last
     and the link leads to an element appended in its arena since;
   - an element the check never saw (appended during the run, or from a list it could not keep) runs only if ADR 0247's
     judge finds its object live, and a link out of its list's arena ends the list.
   Unchanged calls run exactly as before, in order, on the same thread.
4. **It says what it found.** The queue check's log (`garrysmod/data/native-loader/render-queue-check.log`) gets each
   event with the element's place, its words when checked and as found, the object's words, and the classes of the
   eight calls run just before it, newest first: the next field occurrence names the code that wrote over the list.
   The console says how many elements were put back and calls skipped.
5. **Only where sure.** The dispatch is the start of the `CallQueued` pattern ADR 0247 already finds once, and must
   hold exactly the engine's ten bytes at install and before each rewrite; the slot must be within a rel32. Otherwise
   the run check stays off (`nlengineguard.run_check` says why) and ADR 0247's check works as before.
6. **A test path in the real game.** With `-nl_queue_check_test`, each check also appends a pair of calls of the
   module's own: the first writes over the second's element with what the field's crash of 2026-11-19 found (a heap
   block whose first word is another, zeroed one: a call through it goes to address 0); the run check must put it back
   and run the second, and the console says so.
7. **Lua reads, never switches.** `nlengineguard.run_check` says how the install went; `nlengineguard.QueueCheck()`
   also returns the runs watched, elements put back, calls skipped and lists ended early.

## Consequences

- An element written over while the game leaves threaded rendering no longer makes it call freed memory: it is put
  back and its call runs, or the call is skipped and the list goes on; the log names the calls that ran before it.
- If the writes come from heap bookkeeping gone wrong, a later step of the disconnect may still fail elsewhere; the log
  will say what ran just before, for the next fix.
- Not covered: the render thread's own runs of the lists in normal frames (the dispatch is rewritten only inside
  `AllowThreading(false)`), the material system's other runners, and a call whose object was written over with
  something that still looks the same in its first 32 bytes.
- Cost: one record per queued call at each level change and disconnect (80 bytes each, a few thousand calls) and a few
  comparisons per call while the lists run.
