# 0165: The player follows the VR head

Accepted for task L on the V2/V3 task branches, 2026-11-11; milestone review/approval remains separate.
Implements [the movement brief](../handover/VR-V2-L-movement.md) within
[F's interfaces](../handover/VR-V2V3-plan.md).

Horizontal physical walking is player movement, so the head cannot wander through a wall while the
body stays behind. L consumes each valid tracking sample's horizontal translation once, rotates it by
the play-space yaw, scales it to game units and sends a sequenced cumulative displacement. The tracking
anchor moves under the head; the camera's translation comes from the player's collision-checked feet.
This deliberately trades one local server tick of translation latency for a single movement authority
and a head that stays over the hull. No client SetupMove is assumed: Source does not call that predicted
hook clientside in single-player. Tracking reacquisition and jumps over 0.25 m/sample rebase without moving.

The server's priority-100 mover sweeps the current hull, slides at walls and tries the ordinary step
height on standable ground, then lets engine movement supply gravity, jumping and ordinary movement.
It applies at most 0.15 m/tick and discards displacement stopped by geometry; it never accumulates a
push that later launches the player through an opened door. Inputs expire after 0.25 s, are finite,
horizontal, sequenced and bounded by the framework's 2.5 m reach. Death, vehicles and other movement
types discard pending walking. Climbing/teleport have higher priority. Nothing writes player position
outside move data or grants noclip.

The play-space translation keeps the view behind the stopped player hull. An additional eye-sized
solid test and blocked-follow receipt request a full black comfort overlay. A person leaning farther
through a physical wall therefore cannot see through map geometry. This is independent of the optional
motion vignette. Vertical tracking remains physical height; steps/lifts change the feet and lift the
view. Snap, smooth and mouse turns use F's head-pivot helper and preserve the head's world position.

Evidence and measured limits belong to [L's report](../handover/VR-V2-L-report.md).
Sources: Facepunch's [SetupMove](https://wiki.facepunch.com/gmod/GM:SetupMove) and
[FinishMove](https://wiki.facepunch.com/gmod/GM:FinishMove) document single-player prediction realms;
[CreateMove](https://wiki.facepunch.com/gmod/GM:CreateMove) documents the command path.

## Follow-up — 2026-11-11: same-frame head translation

Claude's task L review rejects the tick-delayed camera above for comfort. This record has not
reached main; this dated section supersedes that latency tradeoff without rewriting its history.

Actual CalcView returns on open gm_construct ground show **38.53 / 38.76 ms** mean delay at
0.5 / 1.5 m/s and **38.75 ms** sway correlation delay. Maximum horizontal error is **1.152 / 3.149**
game units. The engine interpolates its tick updates (no exact zero holds in this run), but step
error reaches **0.498 / 1.324** units relative to the same-frame tracking increments. Resting
milestone positions cannot expose this. A 25-degree head tilt also reaches the command/player.

L now predicts **render feet = final authoritative feet + room input not yet processed**. The
server sends absolute cumulative consumed/discarded room input, actual room displacement and
final FinishMove origin, all float32. Coalescing/delayed receipts cannot lose attribution. The
origin already contains ordinary stick movement, teleport and other server movement; those are
never subtracted as room motion. Source's current floor Z is retained. The client sweeps the
pending room displacement with the player hull before using it for camera/hands; a blocked sweep
and the existing eye sweep request the full fade. Server collision/permissions remain authoritative.

The sole framework change is the `feet()` accessor's optional owned `ViewFeet(base)` resolver;
CreateMove is untouched because task S owns its angles/aim work. L removes its resolver on Stop.
Default camera-only consumers remain unchanged. The head's render roll stays tracked while L's
command copies only pitch/yaw and explicitly zeros roll until S's final core policy takes over.

Frame-level before/after data, Source-floor/stick/teleport attribution tests, acceptance and the
final gate are recorded in [L's follow-up report](../handover/VR-V2-L-report.md#follow-up).
