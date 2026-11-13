# vr_move_check.py

Q integration can call `check(folder, timing_scale=0.4)` for its explicitly shortened combined
sequence: only expected stick distances and smooth-turn amounts scale. Room distance, speeds,
collision, turn-pivot, teleport, comfort, restoration and required-record checks do not. The
command-line/default full-rate checker continues to use 1.

Run `python companion/tests/vr_move_check.py out/vr/v2l/<session>` after a completed standard/L
session. Reads console-derived summary and rollback receipts, checks task L's actual named
milestones and writes `movement-acceptance.json` beside them. Does not change game files or settings.
Reports measured distances/directions, head/body error, turns/pivot error, crouch/view heights,
including the combined physical/toggle crouch height,
calibration, jump height, noclip speeds and wall/backlog; or checked teleport landing errors,
mantle, invalid target/server refusal and intermediate shift frames. Missing records fail.
Also verifies coloured ring pixels, a transparent-centre vignette and a fully opaque black fade
from `L-capture-metrics.json`; combined mode requires both sets of semantic checks.
Tolerances cover Source acceleration/friction, network tick sampling and a 1 cm pivot/body bound;
the expected scripted one metre is 40 units, 2 s walking/1 s sprint 400 units, flight 100/300 units/s.
Native acceptance and verified settings/rollback must pass too. No third-party Python dependencies.
After locomotion buffering, head/hull alignment is checked at room-follow/wall milestones. All
other separations (including active flight) remain recorded by milestone; their allowed motor
delay is checked independently by the rendered-frame motion analysis, not forced to zero.
Exit 0 passes, 1 fails; bad arguments/input raise normal CLI errors.
