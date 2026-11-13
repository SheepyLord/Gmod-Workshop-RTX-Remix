# 0201: VR's Auto reads the GPU's work, not the frame's span

- Status: Accepted 2026-11-13 for V6 on the branch `vr6`; reaching `main` needs the user's approval. The user approved V6 and V7 on 2026-11-13 and they were merged to `main`.
- Decided by: Claude, from V6's first run on the Index.
- Amends: [ADR 0199](0199-vr-auto-quality-ladder.md) point 3 and [ADR 0200](0200-vr-auto-counts-only-the-gpus-misses.md),
  which both judged the GPU by `gpuMsTotal`.

## Context

`gpuMsTotal` is the span from the VR frame's first GPU timestamp to its last. In the simulated headset it equals the
work (12.8 ms at the top step), but on the Index at 90 Hz it filled the frame interval at every step: 22 ms at 45 fps
and 11 ms at 90 fps, even at the floor, whose work is under 5 ms. The runtime's own profile shows why: 6 to 10 ms of
each frame is the queue waiting for the CPU (the frame's pacing against SteamVR), which it already separates from the
passes' work (`gpu_queue_wait_cpu_ms`). Judged by the span, Auto saw no headroom at any step SteamVR holds at half rate:
on the Index it climbed back from the floor only to step 3 (`balanced`), although steps 1 to 3 all held 45 fps.

## Decision

- Runtime patch 0088 adds `gpuMsWork` to `rtxvr_Status`: the span without the queue's waits for the CPU (the sum of
  the passes' covered work; the span itself when the recordings' coverage is unknown).
- The add-on's Auto controller reads `gpuMsWork`, and `gpuMsTotal` only when a runtime reports no work. Its
  thresholds are unchanged: a miss counts while the work fills 70 % of the budget; climbing needs it inside 80 %.
- The same patch reserves `stereoActive` in the status for true stereo (V7); it stays 0 until then.

## Consequences

- At a step SteamVR holds at half rate, the work (12 to 17 ms at `balanced` on the Index) shows the headroom the span
  hid, so Auto can climb to the highest step that still holds the target.
- The work includes whatever the compositor ran on the GPU while a pass was executing (its Motion Smoothing among it):
  that contention is real cost to the frame, so it stays in.
- The status grows to 496 bytes within API 4, which no release has shipped; the module and the runtime are built
  from the same branch.
