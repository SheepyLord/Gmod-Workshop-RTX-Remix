# 0166: VR teleport and comfort

Accepted for task L on the V2/V3 task branches, 2026-11-11; milestone review/approval remains separate.
Implements [the movement brief](../handover/VR-V2-L-movement.md) and the binding
[VR design](../handover/VR-plan.md), using F's existing modules, input and overlay services.

The dominant stick's upward hold traces a segmented ballistic arc from the dominant controller:
6 m/s forward plus 2 m/s up, 9.81 m/s squared gravity, 0.04 s segments, at most 8 m range.
Every segment is traced. Eight overlay points and an overlay landing ring show green only when the
standing hull fits on standable ground. Releasing requests a blink or 0.15 s shift. Losing tracking,
input claims, changing dominant hand/mode or entering another movement type cancels aiming.

The server recomputes from a recent validated physical hand. It checks the proposed target against
that arc, the standing hull, floor normal, range and a 1.5 m upward mantle limit. An up/across/down
standing-hull route admits an open ledge while refusing a slit, wall or closed ceiling. Blink waits
0.075 s under full fade and rechecks the whole route. Shift sweeps that same route, including exact
corners, every tick. Moving obstructions, death and movement changes interrupt. The server returns
the request id, result, reason and actual destination; the client never teleports itself.

Physical crouch enters below 68% of standing height and exits above 78%; the dominant stick's down
toggle lowers head and hands by the player's standing-to-duck eye-height difference. The physical
crouch does not lower twice. Seated mode adds its configured height and disables physical crouch.
Off-stick movement is radial-deadzoned and relative to the off hand or head; off click sprints and
off A jumps. Existing noclip flies along the off hand, at trigger fraction of run speed. The server
uses the already granted noclip state and exact command velocity; no permission is introduced.

The optional head-locked vignette follows movement/turn speed. Full black blink and collision fades
work even with its strength set to zero. Every dot, ring and comfort surface is an owned SteamVR
overlay fed from a canvas. No such UI is perspective/path-traced geometry, and Exit destroys it.

Calibration measures tracking eye height and archives the corresponding height/scale pair, using
the player's standing game-eye height. Native stereo world scale is latched at Start and has no
live setter in V1/F. L therefore keeps the active Lua and stereo scales equal and marks a changed
calibration as requiring another Start. M can call `NLVR.Move.Calibrate()` or emit `calibrate`;
`calibrated` supplies height, scale and restart. A live native scale setter or page-level restart is
an integration change for its owner, not an unannounced change to another task's framework.

Measurements, test receipts and remaining integration work: [L's report](../handover/VR-V2-L-report.md).
