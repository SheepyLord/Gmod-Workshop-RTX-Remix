# 0216: The runtime's pipeline-handle race and the in-Present message dispatch fixed

- Status: Accepted 2026-11-14 (the coordinating session's request; the in-game checks are open, see the report)
- Decided by: the coordinating session, from the 0xC0000005 investigation's fix proposals 1 and 3
  (`out\crash\report.md`, written down in [crash-0xc0000005-report.md](../handover/crash-0xc0000005-report.md));
  the form of patch 0092 by the agent, after measuring that the proposed flag alone does not work.
- Runtime patches: `runtime/patches/0091-*` and `0092-*` ([runtime/README.md](../../runtime/README.md)).

## Context

"Crash detected ... Exit code 0xC0000005" is the loader's exit observer reporting an access violation it could not
attribute. The investigation sorted the crashes since 2026-10-28 into clusters. Two of them are made by the runtime:

- **A**, the most common: `nvoglv64.dll+0xe622f8` on DXVK's command-stream thread, 7-35 s after start (8 dumps and at
  least 9 more recorded, field and PoC, every runtime build since 2026-10-31). `vkCmdBindPipeline` reads the vtable of a
  VkPipeline that is not a pointer. `DxvkGraphicsPipeline::getPipelineHandle` created the pipeline instance under
  `m_mutex` and read `instance->pipeline()` through the pointer only after releasing the lock, while DXVK's state-cache
  workers (30 here) `emplace_back` into the same `std::vector` and reallocate it. NVIDIA fixed this upstream on
  2026-10-26 (dxvk-remix `c1a891bf85`, with two other fixes); the fork the package builds from lacks the commit.
  `DxvkComputePipeline::getPipelineHandle` has the same pattern.
- **B**: a Source game that creates its D3D9 device broadcasts WM_COPYDATA (release `0x5E740DE0`, reacquire
  `0x5E740DE1`) to every window. Under RTX, `RtxReflex::latencyPing` drains the PCL stats ping with `PeekMessage` inside
  `D3D9SwapChainEx::Present`, and `PeekMessage` dispatches pending sent messages first: GMod released and reacquired all
  its D3D resources mid-frame and crashed in engine.dll or shaderapidx9.dll.

## Decision

1. **Patch 0091 ports upstream `c1a891bf85dbda78cab979010089c5c9b4256a11`** ("[REMIX-6230] Core fixes:
   pipeline-handle race...", MIT; credited in the patch) with upstream's exact hunks:
   - `getPipelineHandle` copies the new instance's handle into a local while `m_mutex` is held and returns that local
     after writing the state cache (a failed pipeline, handle `VK_NULL_HANDLE`, is no longer written to the cache:
     upstream's choice, kept);
   - `DxvkSubmissionQueue::finishCmdLists` resets and recycles a finished command list before it decrements `m_pending`
     and wakes `waitForIdle`'s waiters, so a zero pending count means the command lists' references are released;
   - frame generation (`rtx_dlfg.cpp`) no longer waits a second time on the swapchain's acquire semaphore that
     `blitRenderedFrame` already waits on: a binary semaphore has one signal for one wait.
   And the same handle fix in `DxvkComputePipeline::getPipelineHandle`, which upstream's commit does not touch.
2. **Patch 0092: the latency ping peeks only while `GetQueueStatus` reports a posted message and no sent one**,
   checked again before each `PeekMessage`, which keeps `PM_REMOVE | PM_QS_POSTMESSAGE`. The proposal was the flag
   alone; measured on this Windows 11 machine, `PeekMessage` dispatched a WM_COPYDATA sent from another process (and
   from another thread) with `PM_REMOVE`, `PM_REMOVE | PM_QS_POSTMESSAGE`, `PM_NOREMOVE | PM_QS_POSTMESSAGE`,
   `PM_QS_INPUT` and `PM_QS_SENDMESSAGE` alike; `GetQueueStatus` reports a pending sent message without dispatching
   it. The PCL ping is a thread message (`PostThreadMessageW(g_PCLStatsIdThread, ...)`
   in `pclstats.h`), still retrieved with the flag. A sent message then waits for GMod's own message loop, where it is
   handled as without RTX, and the ping for the next frame. Run against a pending cross-process WM_COPYDATA over 100
   frames, the patch's logic dispatched nothing; the next frame after the application's loop took the ping.
3. **One build of 0001-0092**, which replaces the Moon-only import of the same branch (ADR 0207): `d3d9.dll`
   418,989,056 bytes, SHA-256 `e242dfdb08486fd97012e3af89b2955fc4f9a11e992902e383cbb844cc857531`.
4. **Verified offline**: the build's disassembly with its PDB (RESEARCH.md, "0xC0000005"): the graphics handle is now
   loaded at `+0xb5 mov r14,[rax+1C8h]`, before the unlock at `+0xbd` (it was `+0x207 mov rax,[rdi+1C8h]`, after the
   unlock at `+0xb4`); compute `+0xa8 mov rsi,[rax+80h]` before `+0xb0` (was `+0x146`, after `+0x9e`); the queue calls
   `reset` and `recycleCommandList` before `lock dec [rbx+10h]` and `WakeAllConditionVariable`; `latencyPing` calls
   `GetQueueStatus(0x100)` and `GetQueueStatus(0x40)` and passes `980001h` to `PeekMessageA`. A static test
   ([`test_runtime_crash_fixes.py`](../../tools/tests/test_runtime_crash_fixes.py.md)) holds both patches to their
   fixes. The runtime's unit tests from the build: 39 of 40 pass; `test_remix_categories` cannot load `d3d9.dll` in its
   own process, with the previous build too.

## Alternatives

- **`PM_QS_POSTMESSAGE` alone** (the proposal): measured not to stop the dispatch (above).
- **A dedicated thread for the PCL ping** (set as `g_PCLStatsIdThread`, with no windows, so no sent message can reach
  it; Present would only read a flag): no `PeekMessage` inside Present at all, closing even the microseconds between
  `GetQueueStatus` and the peek, but a new thread and its lifetime in the runtime for a latency statistic; kept as the
  next step if a crash ever shows that window.
- **Fewer state-cache workers or no state cache** (the investigation's interim proposal 5): hides the race instead of
  removing it, and the state cache is Remix's shader prewarm.
- **Waiting for the fork to merge upstream**: the crash is the one most players report; the port is three small hunks
  that a later rebase onto upstream drops cleanly (they are upstream's own).

## Consequences

- Cluster A's cause is removed; cluster B's in-Present handling is removed. GMod still releases and reacquires its
  resources when another Source program creates its device, in its own message loop, which also crashes without RTX at
  times: an engine-guard filter of those WM_COPYDATA messages is a possible follow-up. Clusters C (third-party render
  meshes under queued rendering) and F (`materialsystem+0x265bb`) are untouched, and the crash dialog still names no
  module.
- Not run (no game): the investigation's fault-injection build, 30 or more PoC cold starts before and after, frame
  generation for 10 minutes, a second `-multirun` game creating its device during an RTX session. The VR crash rule's
  `nvoglv64` retry stays until the fix has proved itself in the field.
- The runtime's provenance (`base.json`) records 0001-0092 on the branch `claude/crash-0xc0000005` at `dd580bc2`.
