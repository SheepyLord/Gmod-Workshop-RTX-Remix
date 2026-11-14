# test_runtime_crash_fixes.py

A static check that the runtime's 0xC0000005 fixes are in the committed patches
([ADR 0216](../../docs/decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md),
[report](../../docs/handover/crash-0xc0000005-report.md)). It reads `runtime/patches/0091-*.patch` and `0092-*.patch`
only: no compiler, no game. Part of `tools\test.ps1` (the `tools` folder's Python tests).

- `PipelineHandleTests` (patch 0091, the port of upstream dxvk-remix `c1a891bf85`): in
  `DxvkGraphicsPipeline::getPipelineHandle` and `DxvkComputePipeline::getPipelineHandle` the new instance's
  `VkPipeline` is copied into a local inside the `m_mutex` scope, after `createInstance`, and that local is returned
  after `writePipelineStateToCache`; the old side still reads `instance->pipeline()` after the lock scope (the race
  with the state-cache workers' `emplace_back`). The patch's message names the upstream commit and its MIT licence.
- `QueueAndFrameGenerationTests` (0091): `DxvkSubmissionQueue::finishCmdLists` resets and recycles the command list
  before `m_pending -= 1` and `m_finishCond.notify_all()`; frame generation's two duplicate
  `addWaitSemaphore(renderedSwapchainImage.sync.acquire)` calls are removed and nothing is added.
- `LatencyPingTests` (patch 0092): `RtxReflex::latencyPing` returns when `GetQueueStatus` reports no posted message,
  peeks only while it reports no sent message (checked before each `PeekMessage`), with
  `PM_REMOVE | PM_QS_POSTMESSAGE`, and adds no other `PeekMessage`; the message says why the flag alone does not stop
  the dispatch.

A hunk is read as its old and new side (context lines on both); git's patch signature is ignored. The checks were
tried against reverted shapes of each fix (the graphics and compute reads moved back after the unlock, the recycle
moved back after the notify, the guard removed), and each fails.

```powershell
cd tools; python -m unittest tests.test_runtime_crash_fixes -v
```

Exit code: unittest's (0 when every test passes).
