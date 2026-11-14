# "Crash detected ... 0xC0000005": what crashes, and the runtime fixes (2026-11-14)

The user's request: "Please trace what is the cause of 0xC0000005 error, since most users also experience this error."
A read-only investigation by Claude (crash dumps, event logs, the loader's session evidence, public reports; its
scripts and outputs stay in `out\crash`, its full write-up is `out\crash\report.md`), then the fix: runtime patches 0091
and 0092, built with the Moon by day (0090) into one `d3d9.dll` on the branch `qol-moon` (worktree
`out\worktrees\q-moon`). Package only, no loader (`winmm.dll`) change; nothing merged or published; no game started.
[ADR 0216](../decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md); facts in
[RESEARCH.md](../RESEARCH.md) ("0xC0000005: the pipeline-handle race and the in-Present dispatch").

## What the dialog says

"Garry's Mod closed unexpectedly ... The cause could not be identified ... Exit code 0xC0000005 (Access violation)" is
the loader's exit observer reporting an access violation for which it found no stronger evidence
(`loader/proxy/ui/labels.json`). It names no module: any access violation in any module ends there.

## Evidence

- Windows' Application log since 2026-10-11 (36 gmod.exe crashes; most are GMod's own handler failing after a first
  fault), its reporting events, WER's local dumps, the field install's five session archives (three crashes, each with
  a Remix dump), GMod's own `crashes\` folder, 84 dump files under `out\` and the worktrees (many copies), the PoC.
- cdb from the installed WinDbg app with Microsoft's public symbols (`out\crash\symcache`) and the r17 runtime's PDB,
  which matches the runtime published since 2026-11-13. Older runtime builds' PDBs were overwritten; GMod and NVIDIA
  ship none. Driver NVIDIA 617.42 on an RTX 5090.
- Public: GitHub issues 1-6 (none reports 0xC0000005), the Workshop item's comments and discussions. One player
  reported a crash with this code shortly after launch, others "random crashing"; none gave a GPU, a driver or a dump.

## The clusters (since 2026-10-28, distinct crashes)

| # | Signature | Crashes | When | Status |
|---|---|---|---|---|
| A | `nvoglv64.dll+0xe622f8` on the `dxvk-cs` thread: a bad VkPipeline in `vkCmdBindPipeline` | 8 dumps (2 field, 6 PoC) and at least 9 recorded without dumps; every runtime build since 2026-10-31 | 7-35 s after start | **fixed by patch 0091** |
| B | `engine.dll+0xf979d`, `shaderapidx9.dll+0xd7ff`/`+0xd759`: Source's IPC release/reacquire mid-frame | 1 field, 2 PoC, 3 lab | when another Source game creates its device | **the RTX-specific part fixed by patch 0092**; the message itself open |
| C | `studiorender.dll+0x6603b`: a Lua render mesh drawn by DrawModel under queued rendering | 6 | when drawn | fixed for the package's code (ADR 0152, 0153); open for third-party add-ons |
| D | the RTX fixes' queued draws (IP=0, `client.dll+0x5744c`) | 4 | entity removals | fixed (ADR 0192) |
| E | `studiorender.dll+0x5d353`: the fixes' late model flush | 7 | 1 s after InitPostEntity | mitigated 2026-10-31 |
| F | `materialsystem.dll+0x265bb`, a null read on the main thread | 2 (field) | 21-23 min into RTX play | open |
| G | `ntdll+0x1a12d`: gmod.exe's CEF thread-exit callback | 2 | thread exit | GMod's own |

Engine `0xc0000409` fail-fasts (13) follow any first fault (GMod's handler failing, R28) and are not a cause.

## Cluster A: the pipeline-handle race

The fault: `DxvkCsThread` replays a draw, `DxvkContext::updateGraphicsPipelineState` binds the pipeline, and the driver
(`nvoglv64+0xe62200`, the graphics bind) reads the vtable of the VkPipeline it was given (`+0xe622f8 mov rax,[r14]`). In
all eight dumps that handle is not a pointer (odd, misaligned or non-canonical: `0x300060059`, `0x6e754664657868f6`,
...); two values recur across processes and builds, freed memory reused the same way. The driver is not at fault.

The runtime made the handle. `DxvkGraphicsPipeline::getPipelineHandle` (`src/dxvk/dxvk_graphics.cpp`) looked up or
created the pipeline instance under `m_mutex`, released the lock, wrote the state cache, and only then read
`instance->pipeline()` through the pointer. The instances live in a `std::vector` (`m_pipelines`); DXVK's
state-cache workers (30 on this CPU: the package runs all hardware threads but two,
`packages/runtime/layers/compiler_threads.conf`) compile every cached state of a shader pair in `compilePipeline` and
`emplace_back` into the same vector. A reallocation between the unlock and the read freed the buffer the render
thread's pointer was in. In all eight dumps 2-3 of the 30 workers were inside the driver compiling. The state cache
(10,203-10,415 states read at each start here; Steam's pre-caching points it at
`steamapps\shadercache\4000\DXVK_state_cache`) keeps the workers busy in the first seconds, which is when the crash
comes; a map load reopens the window. NVIDIA fixed exactly this upstream on 2026-10-26 (dxvk-remix `c1a891bf85`);
the fork this project builds from (`gmod-numos3` `c6b48ed1`) lacked it. `DxvkComputePipeline::getPipelineHandle` had the
same pattern. Vendor independent: on Radeon the same bad handle faults in AMD's driver.

## Cluster B: Source's IPC inside Present

A Source game that creates or resets its D3D9 device sends WM_COPYDATA to every top-level window (`EnumWindows`; dwData
`0x5E740DE0` release before, `0x5E740DE1` reacquire after); the receiving GMod releases or reacquires all its D3D
resources in its window procedure. Under RTX, `D3D9SwapChainEx::Present` calls `RtxReflex::latencyPing`, which drained
the PCL stats ping with `PeekMessage(..., PM_REMOVE)`, and any `PeekMessage` dispatches pending sent messages first:
GMod handled the release/reacquire inside Present, mid-frame, and crashed in engine.dll or shaderapidx9.dll (the field
crash of 2026-11-12 18 minutes in, right after a PoC run created its device; R27's two PoC crashes after the issue-2 lab
game's). The message is dangerous without RTX too (one crash with RTX off, four in September before the project), but
only when a second Source program starts during play.

## What was fixed

**Runtime patch 0091** (fork commit `827870ba`, on `claude/crash-0xc0000005`): a port of upstream dxvk-remix
`c1a891bf85dbda78cab979010089c5c9b4256a11` ("[REMIX-6230] Core fixes: pipeline-handle race...", MIT, credited in the
patch), its three fixes with upstream's exact hunks:

- `getPipelineHandle` copies the new instance's handle into a local while `m_mutex` is held and returns that;
- `DxvkSubmissionQueue::finishCmdLists` resets and recycles a finished command list before `m_pending` is decremented
  and `waitForIdle`'s waiters are woken;
- frame generation no longer waits a second time on the swapchain's acquire semaphore that `blitRenderedFrame` has
  already waited on;

and the same handle fix in `DxvkComputePipeline::getPipelineHandle` (not in the upstream commit).

**Runtime patch 0092** (`dd580bc2`): `RtxReflex::latencyPing` no longer dispatches sent messages inside Present. The
task's first idea, `PM_REMOVE | PM_QS_POSTMESSAGE`, was measured and does **not** stop it: on this Windows 11 machine a
WM_COPYDATA sent from another process (and from another thread) was dispatched inside `PeekMessage` with every
`PM_QS_*` choice (`out\crash-probe`, RESEARCH.md). So the queue is peeked only while `GetQueueStatus`, which dispatches
nothing, reports a posted message and no sent one (checked again before each peek); the peek keeps
`PM_QS_POSTMESSAGE`, with which the posted PCL ping (a thread message, `PostThreadMessageW` in `pclstats.h`) is still
retrieved. A sent message now waits for GMod's own message loop, where it is handled as without RTX, and the ping for
the next frame. The same probe ran this logic against a pending cross-process WM_COPYDATA over 100 frames: nothing was
dispatched inside it, and after the application's loop handled the message the next frame took the ping. What remains
is the few microseconds between the check and the peek.

**The build:** one `d3d9.dll` with patches 0001-0092, built and imported by `runtime\build_runtime.ps1`, replacing the
Moon-only import: `d3d9.dll` **418,989,056 bytes, SHA-256
`e242dfdb08486fd97012e3af89b2955fc4f9a11e992902e383cbb844cc857531`** (61,736,412 bytes xz in Git LFS), built from the
fork branch `claude/crash-0xc0000005` at `dd580bc2`; `base.json` records 0001-0092
([runtime/README.md](../../runtime/README.md)).

## Verification (offline)

- **Disassembly** of the new build with cdb and its PDB, against the 0090 build (the same `getPipelineHandle` as the
  shipped runtime: the investigation's offsets); RESEARCH.md has both listings:

  | | Before (0090 build) | After (0001-0092) |
  |---|---|---|
  | Graphics, `DxvkGraphicsPipeline::getPipelineHandle` | unlock `+0xb4 mov dword ptr [rbx],0`; `+0x202 call DxvkStateCache::addGraphicsPipeline`; `+0x207 mov rax,qword ptr [rdi+1C8h]` (the handle, after the unlock) | `+0xab call createInstance`; `+0xb5 mov r14,qword ptr [rax+1C8h]` (the handle, under the lock); unlock `+0xbd`; `+0x208 call ...addGraphicsPipeline`; `+0x20d mov rax,r14` |
  | Compute, `DxvkComputePipeline::getPipelineHandle` | unlock `+0x9e`; `+0x146 mov rax,qword ptr [rdi+80h]` | `+0xa8 mov rsi,qword ptr [rax+80h]`; unlock `+0xb0`; `+0x15b mov rax,rsi` |
  | `DxvkSubmissionQueue::finishCmdLists` | `lock dec [rbx+10h]` (`m_pending`), `WakeAllConditionVariable`, unlock, then `DxvkCommandList::reset`, `recycleCommandList` | `reset`, `recycleCommandList`, then lock, `lock dec`, `WakeAllConditionVariable` |
  | `RtxReflex::latencyPing` | `PeekMessageA(..., PM_REMOVE)` | `GetQueueStatus(100h)` (posted), `GetQueueStatus(40h)` (sent; `shr eax,10h; test al,40h`) before each `PeekMessageA(..., 980001h)` |

  (`m_pipeline` is at `+0x1C8` of the 0x1E0-byte graphics instance and at `+0x80` of the 0xA0-byte compute one;
  `m_mutex` at `+0x80` and `+0x50` of the pipelines.)
- **Static test** [`test_runtime_crash_fixes.py`](../../tools/tests/test_runtime_crash_fixes.py.md): both patches hold
  each fix (the handle read inside the lock scope for graphics and compute, the recycle before the notify, the
  duplicate waits gone, the guarded peek); each check fails on a reverted shape of its fix.
- **The runtime's unit tests** built with it (`meson test -C _CompRelease_x64 --no-rebuild`): 39 of 40 pass,
  `test_documentation` among them (it loads the new `d3d9.dll` and regenerates `RtxOptions.md` to compare). The one
  failure, `test_remix_categories`, cannot load `d3d9.dll` in its own process; it fails the same way with the 0090
  build's DLL, so it is the test's environment, not these patches.
- **The message probes** (`out\crash-probe`, MSVC, run on this machine): `peek_probe` (another thread's sent message),
  `peek_probe_xproc` (another process's WM_COPYDATA): dispatched inside `PeekMessage` with every `PM_QS_*` flag;
  `peek_probe_guard` (patch 0092's logic): nothing dispatched over 100 frames with a cross-process WM_COPYDATA pending,
  the posted ping taken in the next frame after the application's loop handled the message.
- `tools\test.ps1 -Config Release`: passes ("All checks passed"): repo conventions, 35 of 35 CTests, the `tools` Python
  tests 1,910 (2 skipped), `gmapack` 29 and `steam` 26 (1 skipped each).

Not done (no game was started): proposal 1's fault-injection build (a 2 ms sleep between the unlock and the read, which
should crash most starts with the old code and never with the new), 30 or more PoC cold starts before and after (about
2-4 crashes against 0 expected), 10 minutes of frame generation without a device loss, and a second `-multirun` game
creating its device during an RTX session.

## Open

- **Cluster B's message itself.** GMod still releases and reacquires its resources when another Source program
  creates its device, now in its own message loop; that also crashes without RTX at times. A possible follow-up: the
  engine guard drops WM_COPYDATA with dwData `0x5E740DE0`/`1`/`2` in RTX sessions (subclassing `Valve001`, which
  `engine_guard/load_overlay.cpp` already finds; dwData 0, console text, passes). Until then: one Source game at a
  time.
- **Cluster C** for third-party add-ons (GetRenderMesh with DrawModel under queued rendering): the render guard could
  route those draws through the package's direct draw (ADR 0153) after a compatibility pass.
- **Cluster F** (`materialsystem+0x265bb`): unexplained; the next field occurrence should keep the Remix dump too.
- **Naming the crash.** The dialog could name what crashed: at the next start, read the archived Remix dump's exception
  (module and offset, driver version), show it with "Crash detected" and in `exit-report.json`, and map known
  signatures to advice; in the package (engine guard or companion) or in the observer (a loader change, which needs
  the user's approval). A GitHub issue template asking for the session folder would help too.
- After the fix has proved itself in the field: drop the VR crash rule's `nvoglv64` retry.

## What a player can do until the package carries the fix

- A close with 0xC0000005 within about 30 s of start or during a map load: start again (a timing race). Reinstalling,
  verifying files or updating the driver does not change it.
- Do not start a second Garry's Mod, SFM, Hammer or other Source program during an RTX session.
- Crashes with one custom-mesh add-on on screen: disable that add-on.
- When reporting, attach `GarrysMod\native-loader\logs\sessions\<time>-<pid>-crash`, which holds the Remix dump.

## Published

The user asked for the round to be committed and pushed when finished (2026-11-14: "Commit and push after you finish"). `main` was fast-forwarded to `058f28cf` (the round on `qol-1114`, one squashed commit per item, after the gate passed on the combined tree: C++ 35 of 35, Python 1,958 + 29 + 26 tests); the merge's hook built the package from `packages/` and uploaded item 3829070317 as **0.0.0-dev.20261114090900+c46c58b9** (2,088,047,623 bytes, SHA-256 `94061aff390e3ebbddcbbc689610ee7c10439f1c5d3f444c343f714f8b1c9ae4`, content digest `cb36cc1c...`) at 2026-11-14 09:09:20 UTC. Not yet checked in a game: the checks above are open.
