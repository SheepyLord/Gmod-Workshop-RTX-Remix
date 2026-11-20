# The crash when the game leaves threaded rendering: report

By Claude, 2026-11-19, on the branch `render-queue-check`; package only (the engine guard). Decision:
[ADR 0247](../decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md). Facts and
offsets: [RESEARCH.md](../RESEARCH.md), "The crash when the game leaves threaded rendering".

## What the user reported

The field game closed with "Garry's Mod closed unexpectedly", exit code 0xC0000409 (fail-fast termination), and the
loader's evidence folder. The user: "I typed disconnect to attempt to go back to the main menu and led to the crash."
The start (2026-11-18 23:03Z) had deployed the package published that evening (220 changes); the game ran 1 h 56 min.

## What it was

- **The path.** `disconnect` runs Host_Disconnect: the client side closes (its Lua state; the Model Hotloader, the RTX
  fixes, glass, the material bridge, the debug module and the load accelerator's client module unload), then
  `IMaterialSystem::AllowThreading(false)` makes `ForceSingleThreaded` run what both queued render contexts still hold
  on the main thread. Its `CallQueued` reached the 660th call of the list being recorded (context 1) and called through
  the call's object: the object had been freed and its memory reused, so its first word, the vtable, was another heap
  address and the call went to address 0. GMod's crash handler then failed while writing its report (the 0xC0000409
  at `engine.dll`+0x34b9dc the dialog shows).
- **The same as the parked level-change crash.** The three field crashes of 2026-11-15 still in the field's session
  folders take the same path (`map` disconnects first), and the investigation of 2026-11-15 had six of them, all in
  starts that had just deployed new RTX content, as this one did.
- **Not this package's own queued calls.** That investigation had suspected the Model Hotloader, whose calls (and RTX
  Water's) are heap objects that free themselves when they run. The memory maps that RTX Remix's crash reporter keeps
  with its dumps say otherwise: in all four field dumps the freed object lay in GMod's own allocator (tier0's
  dlmalloc, which takes memory in 64 KB blocks), while the Hotloader and RTX Water allocate from the Windows heap (1 MB
  and 0xFD0000 segments). Of this package's modules only the RTX fixes' binary and the debug module allocate through
  tier0, and neither touches the render list.
- **Not memory pressure, not the DirectX level change.** The machine's commit was at 81 % of its limit at the crash
  (98-99 % earlier, from other programs); the RTX client module of ADR 0246 never touches the render queue.
- **Unknown:** which code of GMod's frees an object while its call is still queued, and why only after a deployment.
  No dump holds the queue's memory.

## What was built

- `engine_guard/queue_check.h`, `queue_check.cpp`: the engine guard wraps `AllowThreading`'s vtable slot. On `false`
  it takes the material system's lock (the render thread finishes its frame), walks both queued contexts' call lists
  and unlinks every call whose object's first word is not a vtable in a loaded module's read-only data with its call
  slot (3) in code, keeping the live calls in order; then the engine's own function runs. Everything is found by
  machine code, only where sure (the slot by its two "Queued Material System" messages, Lock and Unlock by theirs,
  `ForceSingleThreaded`'s loop over the contexts, `EndQueue`, `CallQueued`'s loop and reset, the RTTI classes); Remix
  starts only. A check that drops calls writes `garrysmod/data/native-loader/render-queue-check.log` (each call's
  place, why, its memory, its first words, the classes of the live calls around it) and says so in the console.
- `engine_guard/module.cpp`: every realm installs it; `nlengineguard.queue_check` (how the install went) and
  `nlengineguard.QueueCheck() -> checks, dropped`, read only.
- `engine_guard/tests/test_queue_check.cpp`: ten tests (the layout found once in the installed game's
  `materialsystem.dll`: slot 122, Lock 106, Unlock 107, two contexts at +0x27d0 every 0x10003a8, the list at +0x2b0;
  the judge on real memory; unlinking first, last, all and several lists; broken lists left alone; appending; RTTI
  names; nothing outside a Remix start; the module's contract). The engine guard's 59 tests pass.
- `tools/qa/queue_check_session.py`: PoC sessions under the shared lock: a test session launched with
  `-nl_queue_check_test` (each check first queues one call whose object is gone and must drop it) and a plain one,
  each changing level and disconnecting.
- The fixes part's `gmcl_` and `gmsv_nlengineguard_win64.dll`, built from the branch.

## Tests

- **Unit tests** (CTest `nl_engine_guard_tests`): the engine guard's 59 tests pass, the ten in `test_queue_check.cpp`
  among them. The layout test reads the installed game's `materialsystem.dll`; on a machine without the game (CI) it
  returns without checking.
- **PoC** (`tools/qa/queue_check_session.py`, 2026-11-19, under `out\r10\poc.lock`; evidence in
  `out\queue-check\run1`): the branch's package installed with `poc_session.py install --allow-local`; each session
  RTX on with the package's add-ons, `gm_construct`, `map gm_flatgrass`, then `disconnect` and quit.
  - **Test session** (`-nl_queue_check_test`; the package's first start, 1712 changes deployed): exit 0 after 71.9 s,
    no crash, no Lua error. The check was in place once, from the main menu on (the menu realm's `gmsv_` copy; one
    console line). The level change's check walked context 1's list (1587 calls) and the disconnect's walked context
    0's (1016 calls); each dropped the test call, the last in its list, and nothing else. Two checks in between, while
    the second map loaded, found the main thread outside the queued contexts and walked nothing. The log names the call
    queued just before the test call, the material system's own `CMemberFunctor0<CMatRenderContextBase, ...>`, so a
    real drop will come with its neighbours' classes.
  - **Plain session** (the same steps without the option, the package already deployed): exit 0 after 54.0 s, no
    crash, nothing dropped and no log written; the console line that the check is in place.
  - Afterwards the PoC was restored and verified vanilla (2878 depot files), its `user.conf` unchanged.
- **What this shows:** the patterns match in the running game, the walk reads the real lists and unlinks a call
  without disturbing the rest, and an ordinary level change and disconnect pass through untouched. It does not show
  that the field crash is gone: the PoC never reproduced it (the series of 2026-11-15).

## Not covered

- A freed object whose memory still holds a live-looking vtable is called as before.
- Stale calls run by the render thread, or by the material system's other runners (a `mat_queue_mode` change, its own
  flushes); every crash seen came through `AllowThreading(false)`.
- The root cause. If the log ever shows a drop in a player's game, the classes around the dropped call name the code
  that queued it; a whole-memory dump of an occurrence would name the owner (the watcher is in `out/crash-34b9dc`).
