# 0173: VR integration review fixes

Post-W integration clarification: preserve Damage(speed,scale)'s legacy 65-cap curve for
existing weapon callers. P's real A.Hit always passes source=="held" explicitly, so false
still caps bare hands at25 and true retains held damage65. The first post-W gate exposed
the old two-argument test/API assumption (32 vs25); fix Q's optional argument compatibility,
not W's owned code or its test. This does not change any measured V2/V3 call, which is explicit.

Accepted for the V2/V3 branch on 2026-11-11, task Q. Amends
[0164](0164-vr-hands-fingers-and-ghosts.md) and [0171](0171-vr-use-by-hand-and-melee.md).

An unresolved hand or shoulder cast beginning in solid has no safe shown placement. Suppress
that frame's hand model by clearing shown validity, retaining the controller target and ray.
The next core frame resets validity; a later proxy position alone cannot reveal an unsafe hand.
Placing it at the head made the world model fill an eye. Offline solid/draw tests cover this.

Bare punches keep the 1.5 m/s threshold and P's speed curve, capped at 25 damage (a crowbar hit).
Held-object impacts retain the curve to 65. A 6.5 m/s bare punch previously dealt 65 and could
kill a citizen in a single high-speed contact sequence. Tests exercise both mathematical caps
and the authoritative damage application, cooldown and NPC push path.

Reuse debug tables in the hands, movement, network and interaction modules. Debug remains plain
probe data with current values, without rebuilding its nested tables each frame. Identity tests
run repeated frames/receipts. UI inventory allocations are reviewed after M's follow-up lands.

Help states that VR enables server NPC death ragdolls for the session and restores the original
ai_serverragdolls at Exit. Height calibration changes the next session's latched native scale;
the page displays an explicit Exit/Start notice only while calibration.restart is true. No
automatic restart interrupts a player's session. Catalog updates use UTF-8 scripts and the page
test covers notice appearance/removal. No trust, loader or SteamVR setting changes are involved.

## Combined-run findings

The first combined simulation exposed explicit body TraceHull queries hitting the player's own
non-transmitting hand proxies even though ShouldCollide excludes those contacts. Room input was
consumed as blocked, and teleport said solid. P now owns a BodyTrace predicate matching only
its already-suppressed player/proxy/held/pulled/released pairs; L uses it for server body/eye/
teleport sweeps. World, NPCs and unrelated props remain solid. Both module suites cover the
bridge; no movement permission or reach check changes.

Fifteen retained physics/movement canvases plus a wrist menu and laser exceeded the native
16-overlay budget, stopping UI. Raise the owned session bound to 32, keeping overflow rejection
and normal cleanup. C++ tests exercise all 32, overflow, replacement and two sessions. This is a
resource allowance for the agreed UI, not a path/trust/off-switch change. R/M's pending imported
module must be brought current again after the shared-header switch and this fix.

The role checker must recognise L's seven extra move_arc_2..8 dot keys explicitly. The P cleanup
witness must follow server processing of STOP, not run inside client module teardown. Empty Lua
tables can encode as JSON arrays; a missing UI change is a failed check, not a checker exception.
Failed combined-sim-01 stays unchanged, with all its positive and negative measurements.

After M's reviewed follow-up landed, Q also reuses UI panel/keyboard/laser debug tables.
The collision bridge must exist on the client too: non-transmitting proxies are server-only,
but the player's held prop is visible to client prediction. Exclude only known own held/pulled
bodies and the same 0.2-second release grace, remove the predicate at Stop, and leave unrelated
solids blocking. The combined heavy-body phase walks while holding, with a required clear view.
Native Resume evidence records menu visibility before the posted down event; fallback typing
uses real laser-key hit tests, with the actual platform failure preserved.

## Shared-wire motor cadence and climbing

With P active, the full-rate combined test retained same-frame head response but exposed
215.8/213.3/276.2% normalized walking/sprint/flight step spread and tick holds. F's one-message
per-player/tick policy fairly coalesces FOLLOW with physical-hand state; L's one-tick motor
buffer could run out of source samples. Keep that wire policy and learn a bounded motor-only
buffer from recent FOLLOW source cadence plus tick-quantized delivery padding. Reset it on
mode/generation discontinuities, retain a monotonic non-extrapolating cursor, and keep room
tracking outside that delay. Debug/measurements report the extra motor delay explicitly.

The same delayed common body translation fed back into P's absolute-world climbing constraint,
turning a scripted 12-unit pull into 36 units. Calibrate contact at grip acquisition and solve
from hand-minus-head positions, which cancel that shared translation. Authoritative body hull
sweeps, two-hand averaging, reach/staleness rules and bounded launch remain. Independent delayed-
body tests require exactly 12 units and zero further movement after the hands stop. This changes
implementation feedback, not the agreed physical-hand/climbing design or network protocol.

The buffer removes tick holds; a remaining 24-31% normalized spread exposed motor positions
being frame-cached at an earlier CreateMove/resolver call. Cache only room sweep correction,
and sample the non-room trajectory at the actual view lookup. The same-frame 3-ms/0.6-unit
regression checks this independently of frame rate and source receipt cadence.

A shared per-player/entity Use cooldown prevents simultaneous hands from toggling the same
button on then off. It retains the existing 0.3-second bound, permission hooks and native Use,
with weak keys and a two-hand/later-press regression.
