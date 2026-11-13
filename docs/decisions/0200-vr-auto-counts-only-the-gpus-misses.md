# 0200: VR's Auto counts only the frames the GPU lost

- Status: Accepted 2026-11-13 for V6 on the branch `vr6`; reaching `main` needs the user's approval. The user approved V6 and V7 on 2026-11-13 and they were merged to `main`.
- Decided by: Claude, from V6's first PoC run.
- Amends: [ADR 0199](0199-vr-auto-quality-ladder.md), point 3 (the controller), which counted every missed window.

## Context

ADR 0199's controller stepped down after two windows below 95 % of the target rate, whatever lost the frames. The
first PoC run showed why that is wrong: with the GPU at 12 ms of a 22 ms budget, frames lost elsewhere (the game's
own thread, a hitch, a frame cap) would have walked the ladder to the floor, and every rung would have cost picture
quality without bringing one frame back. The runtime already reports the GPU time of the VR frame
(`gpuMsTotal`), which the controller reads to decide when it may climb.

## Decision

- A missed window counts toward stepping down only while the GPU time fills at least **70 %** of the frame budget,
  or is unknown (then every miss counts, as before).
- A window that missed while the GPU had room sets `cpuLimited`; Auto holds its step, and the VR page says that
  frames are being missed while the GPU has room, so a lower step would not help.
- Climbing is unchanged: eight settled windows with the GPU inside 80 % of the budget.

## Consequences

- The band between 70 % and 80 % neither steps down on a miss nor climbs, which adds to the hysteresis.
- A game that is slow on the CPU keeps its quality instead of losing it for nothing; the page tells the player why.
- The PoC can no longer make Auto step down with a frame cap (GMod also blocks `fps_max` from Lua); its probe stages
  the measurement instead, and the rest of the path is the production one
  ([`vr_quality_probe.lua`](../../companion/tests/vr_quality_probe.lua.md)).
