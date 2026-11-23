# 0261: Queued render calls run before the map-exit cleanup

- Status: Accepted 2026-11-23 (the user's report: "The game still face a fast termination crash after some playing on
  disconnect. Please investigate this issue, launch Opus 5.5 sub agents to resolve it and validate its work and write
  documentations."). Supersedes [ADR 0254](0254-queued-render-calls-checked-again-while-the-game-runs-them.md)'s
  reading of the crash of 2026-11-22 (an element written over during the run) and changes its decision 7 ("Lua reads,
  never switches"); extends [ADR 0247](0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md)
  and ADR 0254, whose mechanisms stay as they are.
- Package only: the engine guard (`gmcl_`/`gmsv_nlengineguard_win64.dll`, the fixes part,
  [engine_guard/queue_check.h](../../engine_guard/queue_check.h), [run_check.h](../../engine_guard/run_check.h),
  [target_check.h](../../engine_guard/target_check.h)) and the RTX fixes' Lua
  ([cl_rtx.lua](../../packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua.md), the hook
  `RTXTextureCleanup_MapExit`). No `winmm.dll` change: the user rejected loader changes (2026-11-17).

## Context

Three more field games closed at `disconnect` with exit 0xC0000409 ("Fail-fast termination") after ADR 0254 was
published: 2026-11-22 05:17 UTC, 2026-11-23 05:57 UTC and 06:39 UTC, after sessions of 75, 9 and 41 minutes. The facts
with offsets are in [RESEARCH.md](../RESEARCH.md), "The crash at disconnect: queued material-variable setters on
destroyed variables".

- **The path.** All three dumps: the `disconnect` callback (`Host_Disconnect`) > the guard's `AllowThreading` wrapper
  > `AllowThreading(false)` > `ForceSingleThreaded` > `EndQueue` > `CallQueued` (its dispatch rewritten by ADR 0254) >
  the run check's step > the queued functor's call. The run check ran the call: nothing about its element or its
  functor had changed.
- **The functor was intact; its target was gone.** The call was a queued material-variable setter:
  `CMemberFunctor1<CMaterialVar*, void (CMaterialVar::*)(int), int>` on 2026-11-22 (the call went to address 0) and
  `CMemberFunctor1<CMaterialVar*, void (CMaterialVar::*)(ITexture*), ITexture*>` on 2026-11-23 twice (a read of
  address 0 in `CMaterialVar::CleanUpData`). In queued rendering a Lua `IMaterial:SetTexture`, `SetInt`, `SetFloat` ...
  on the main thread does not write the variable: it queues such a functor holding the raw variable pointer, and
  nothing keeps the variable alive (`CRefCountServiceNull`).
- **What destroys the variables.** The RTX fixes' `ShutDown` hook `RTXTextureCleanup_MapExit` calls the fixes'
  binary module's `RTX_CleanupMapTextures` (upstream since 2026-08-08), which does `IMaterialSystem::Flush(true)`, then
  `UncacheAllMaterials()`. `Flush` does not run the calls the main thread has recorded in queued rendering;
  `UncacheAllMaterials` then destroys every variable of every file-based material at once, on the main thread. Every
  setter queued since the last frame (by a `ShutDown` hook that ran before the fixes' one, or by a hook earlier in that
  frame) is left pointing at freed memory, and `AllowThreading(false)` runs it a moment later. When the memory was
  reused the call goes through a heap link (address 0 or garbage); when it was not, `SetTextureValue` finds a texture
  variable whose texture is NULL and reads address 0. GMod's crash handler then fails (exit 0xC0000409).
- **Who sets variables at `ShutDown`.** The companion itself: it puts imported characters' file-based materials back
  (`$basetexture` for the eye whites, `$flags` and `$allowalphatocoverage` for solid hair, then `Recompute`), hence
  "after some playing" with characters spawned. Any other add-on that sets a material parameter at `ShutDown` or in
  the last frame does the same.
- **Reproduced on the PoC**, the published package `0.0.0-dev.20261123002706+24c6839a`: a client `ShutDown` hook that
  sets file-based materials' variables as the companion does crashed the game at `disconnect` 4 of 4 times, with the
  field's dump (a read of address 0 in `CleanUpData` under the guard's step). The same session with the fixes' cleanup off
  (`rtx_flush_textures_on_map_exit 0`) went through 2 of 2 times; with materials made by `CreateMaterial` only
  (referenced, so `Uncache` keeps their variables) and without the hook it did not crash. One screen read-back
  (`render.CapturePixels()`, which makes the queued context run its list on the main thread) before the cleanup made
  the crashing session clean, 2 of 2: running the queued calls before the uncache is enough.
- **Why ADR 0247 and ADR 0254 could not catch it.** ADR 0247 judges a call's object, which for these calls is the
  functor in the context's own arena: a live object of a loaded image, so it passed. ADR 0254 looks for an element or
  an object that changed after the walk; neither changed. Both look at the call, and the dead thing was the call's
  argument. And the run check wrote its log only after the engine's function returned: a run that crashed left none,
  which is why the field never had a `render-queue-check.log`.
- **ADR 0254's reading corrected.** Its dumps (2026-11-19 and 2026-11-22 01:50 UTC) read again: both are
  `CMaterialVar::SetIntValue` entered through its vcall thunk (`mov rax,[rcx]; jmp [rax+20h]`) with `rcx` a heap
  address whose first word was another heap address. ADR 0254 took `rcx` for the functor, and concluded that the
  element had been written over; `rcx` was the functor's target, the material variable, loaded by the functor's own
  call (`mov rcx,[rcx+18h]; jmp [rax+10h]`). GMod's queued calls do live in the context's arena, as ADR 0254 found;
  the variables they act on live on tier0's heap. The element at arena +0x2938 is position 219 of its list (0 first;
  each call takes 48 bytes, its 32-byte functor and its 16-byte element), not the 660th.

## Decision

1. **The engine guard runs the main thread's queued calls on request, through the engine's own flush.** At install it
   finds, in the live `CMatQueuedRenderContext`'s vtable, the one slot whose code is the engine's flush of a queued
   context: the material system's `Lock`, `CallQueued(this, 0)`, `Unlock`, with nothing called between `CallQueued` and
   `Unlock` (the engine itself calls this slot in the middle of a frame when the list grows too large, "Render queue
   too large, flushing!"). Only where sure: the exact code shape, its `Lock` call within 0x60 bytes of the function's
   start (a match further in may lie in the next function); the `Lock` and `Unlock`
   slots and `CallQueued` that ADR 0247's layout already found; both loads of the material system pointer the same;
   exactly one such slot (two synchronous methods of the same shape call something between `CallQueued` and `Unlock`
   and are refused). The calls run with the same walk (ADR 0247) and the same watched run (ADR 0254) as at
   `AllowThreading(false)`. Main thread only; the copy of the module that did not install forwards to the one that did.
   Lua, client and server realms: `nlengineguard.RunQueuedRenderCalls() -> ok, calls, why`. `ok` means the flush ran
   (or this thread records into no queued context): inside a render block the engine's flush itself queues one call of
   its own around it, so the list need not be empty afterwards, but every call queued before it has run.
2. **The fixes' map-exit cleanup runs only after them.** The hook `RTXTextureCleanup_MapExit` calls
   `RunQueuedRenderCalls()` under `pcall` before `RTX_CleanupMapTextures`. When it returns false or raises, or the
   engine guard is absent while `mat_queue_mode` is not 0, the cleanup is skipped and one console line says why. A
   skipped cleanup costs memory until the next map; an uncache with calls still queued can crash the game.
3. **The net: a call on a material variable that is gone is skipped.** While queued calls run under the guard's watch
   (the flush above, and the engine's own `AllowThreading(false)`), the run check asks right before each call whether
   it is a setter on a material variable and whether that variable is still a variable of its material: its first word
   must be `CMaterialVar`'s vtable, its owner's first word `CMaterial`'s, and the owner's parameter array must list it.
   Otherwise the call is skipped and logged. The offsets come from the public interface slots by their exact getter
   code (`GetOwningMaterial`, slot 24; `ShaderParamCount`, slot 40; `GetShaderParams`, slot 41) and are cross-checked
   against `CMaterial::CleanUpShaderParams`' two stores; the owner's offset counts as proven only once some variable's
   owner has been a `CMaterial` in the process, and until then a variable whose owner is no `CMaterial` runs. A
   functor class is judged when its RTTI name is a `CMemberFunctorN` on a `CMaterialVar*` and its call has the
   engine's shape (the string setter's own shape included). A variable whose owner is another material class of the
   image (`CMaterialSubRect`), or one without an owner, is not judged and runs. No texture reference is lost when a
   texture setter is skipped: the engine takes a reference when it queues the setter and queues the matching release
   right behind it; the skipped setter would have taken the variable's own reference.
4. **The run check's log is written when an event happens**, not after the run: a header line at a run's first event,
   each event as it happens, a summary line at the end, so a run that crashes still leaves its log. At most 32 events
   per run are written, and the routine line each flush writes only for the first 64 flushes of a process, so the
   routine lines cannot rotate evidence out of the log. Nothing it does while the list runs takes the loader lock.
5. **A change of ADR 0254's decision 7** ("Lua reads, never switches"): `RunQueuedRenderCalls` is an action Lua can
   ask for, in the client realm too, where a server's Lua runs. It is acceptable because it only runs calls the engine
   would run anyway a moment later, on the same thread, through the engine's own flush; a screen read-back
   (`render.CapturePixels`) already makes the engine do the same from any Lua; and its routine log line is capped
   (decision 4). The queue check, the run check and the target check still have no switch in Lua.
6. **ADR 0254's mechanism stays** (the watched run, the put-back, the test pair): it costs little and guards a case
   that has not been seen. Its reading of the crash is superseded by this record.
7. **Tests in the real game.** The launch option `-nl_queue_check_no_flush` makes the flush run nothing and report
   success, so a test session reaches `AllowThreading(false)` with the stale setters still queued and exercises the
   net. `tools/qa/queue_check_session.py` gains the kinds `stale` and `stale-net` with
   [`queue_stale_client.lua`](../../tools/qa/queue_stale_client.lua.md) and judges each run PASS or FAIL.

## Consequences

- Leaving a map or disconnecting no longer runs queued material setters on destroyed variables: the fixes' cleanup
  comes after them, and a setter that still finds its variable gone is skipped and logged.
- A player on an older package can avoid the crash with the console variable `rtx_flush_textures_on_map_exit 0`
  (the cleanup skipped, "Skipping map-exit purge" in the console; 2 of 2 clean on the PoC); it costs texture memory
  until the next map.
- `nlengineguard.queue_flush` and `nlengineguard.target_check` say how each install went; `QueueCheck()` returns two
  more numbers, the flushes done and the calls skipped because their variable was gone.
- Cost: one walk and one watched run of the calls queued since the last frame at each map exit (a few hundred calls in
  the PoC), and a few reads per material-variable call while a watched run goes.
- A game update that moves the flush's code shape or the getters turns that part off with the reason; the fixes'
  cleanup is then skipped (decision 2) and ADR 0247's and 0254's checks work as before.
- Not covered: the fixes' console command `rtx_flush_textures` runs the same uncache in the middle of a game, and the
  render thread then runs the list unwatched (the same class of fault; it needs a change in the fixes' native
  module); the render thread's own runs in normal frames are not watched; variables of other material classes are not
  judged; the field's own sessions with imported characters were not replayed (the reproduction is a hook that sets
  variables as the companion does: on the PoC with the field's exact fault, and once in the field install after the
  publish, where the session with it went through its `disconnect` cleanly).
