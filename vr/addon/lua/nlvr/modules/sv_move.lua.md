# sv_move.lua: authoritative room walking and teleport

Server module, order 10, active only for the framework's validated local single-player/listen host.
Message 24 carries wrap-aware sequence and three float32 components of cumulative horizontal room translation; bounds,
staleness and a 0.15 m/tick cap prevent jumps/backlogs. Priority-100 room follow sweeps/slides/steps
the current hull in move data, discards blocked displacement and leaves ordinary engine movement
running. Message 27 returns blocked/movement mode, cumulative consumed input, cumulative actual
room displacement and the final FinishMove origin through changed-only server transport, all
coordinates float32. Absolute receipts survive coalescing and attribute room movement separately
from stick movement, gravity and teleport; the client predicts only unprocessed room intent.
The receipt additionally carries double-precision simulation/wall timestamps and a discontinuity
generation. Blink/respawn, mode changes or large kinematic jumps advance that generation. Timestamp
changes alone do not generate idle traffic: unchanged positions/velocity/room state are skipped.
The owned FinishMove hook discards input when a higher-priority mover handled the tick; leaving
climbing cannot replay room movement or a queued teleport. Priority-50 flight only runs in already granted noclip,
uses the head-relative user-command vector and caps it to run speed without engine speed multipliers.

Message 25 carries request id, physical hand, blink/shift mode and proposed landing. Recomputes
the ballistic arc from a recent validated hand, requires standing hull/floor, range, mantle height,
matching target and an unobstructed hull route. Priority-20 teleport is below climbing: blink waits
0.075 s behind the client's fade; shift traverses the checked route over 0.15 s. Every movement is
rechecked for moving obstacles. Message 26 returns id/success/reason/actual target. Death, vehicle,
movement mode change and Exit interrupt/discard state. Requests expire after 1.25 seconds of wall
time, so pausing cannot defer movement beyond the client's 1.5-second pending fade timeout.
No player SetPos, noclip permission, file write, global hook or persistent server timer.
Errors go to the framework's module containment.


Review correction: oversized ROOM deltas update sequence/received/consumed baselines without moving the hull; subsequent small steps work. Each validated teleport displacement emits teleport_delta for physical carry.
