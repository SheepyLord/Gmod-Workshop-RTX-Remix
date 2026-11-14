# Reload receipt analysis

`python companion/tests/vr_reload_analyse.py out/vr/v4k/<run> [--button]` reads
reload.json and the unchanged shared driver's summary.json. Checks every observed
class: five-second empty hold, constant reserve/no native reload/no weapon switch,
server token pickup, real clip insertion and subsequent consumption, three shotgun
shell steps, and three capture requests. Button mode checks actual clip refill or
the fixture SWEP's native Reload call count. A repeated phase from the second
Start is excluded from the first contiguous phase explicitly.

Writes reload-checks.json with booleans and actual server samples. Exit 0 requires
all features and shared driver success; otherwise 1. This is a strict starting
check; the handover also audits the exact requested class set, captures, restoration
and compositor. It does not claim time spent in setters is native engine proof.

Counter analysis compares recorded device-local placement and raw hand poses
against the actual native/OpenVR absolute matrix (2 cm maximum error), measures
hand displacement, and checks constant paint counts in unchanged-value intervals.
A run flagged --counter-motion requires at least 15 cm of hand travel. The native mapping is
Source (x,y,z) to OpenVR (-y,z,-x); no image position heuristic substitutes for it.
The hold check records the native primary deadline read back in StartCommand,
then requires real attack-bit attempts, a post-native future deadline during
those attempts, unchanged native clip/reserve, no reload, and no switch for five
wall seconds. The pistol's idle getter rewrites after the base decision remain
in raw receipts; they are not mistaken for the time seen by that decision.

Deploy-lock runs require positive native lock evidence and no reload command while that lock remains, while preserving the ordinary-reload/one-tick checks.

Button tick counting covers the whole first live weapon phase, so delayed RPG/deploy readiness is accepted and late duplicate ticks cannot hide outside a narrow fixture window. Deploy mode still requires the command after the tap and a nonpositive native attack lock.

Full-phase counting exists only to detect duplicates. Acceptance separately requires native readiness evidence and B delivery no later than0.3 s afterward for every class. Client absolute deadlines and server relative countdowns are aligned to the phase clock; deploy mode additionally requires the injected native lock.

Native readiness observations stop at the first client reload bit (or server delivery if earlier), excluding the attack lock created by the reload itself. A retained cross-clock counterexample enforces this without changing the0.3-second bound.

Combined sessions can contain attack observer rows before a reload phase is assigned. Those unclassified rows cannot satisfy the empty-fire witness; they are ignored for per-class matching rather than raising KeyError. All fire/wait/clip/reserve/engine-reload/counter bounds remain unchanged.

V8 (run 1 on the PoC, 2026-11-13): the server stamps its records with `SysTime` from the phase's start and the client
with the fixture's own clock, and in a session's first phase the two parted by 44-75 ms, so B reached the server
"before" its release (latency -0.063 and -0.075 s). Both realms count the same ticks in single-player, so
`button_delivery` now reads the delivery tick on the client's clock, at the first client `button-command` record of
that tick or later, and moves the server's sample deadlines by the same offset (`server_clock_offset` in the result).
Without a client record of the tick the server's own time stands, as before. Readiness evidence now stops at the first
record of B in the console's order (the first client reload bit or the server's delivery), not at a clock reading: a
frame runs several commands at one reading, and those after B already carry the reload's own lock (the 357's 3.66 s).

`HOLD_FLOOR` (3000 s) replaces the 3500 s threshold of the empty-gun and physical-reload hold checks: a hold runs 3600 s
from when it was applied, and an unloaded RPG from the sandbox loadout is held from the session's start, so in a
seven-gun session its phase finds ~3477 s left. Sessions run under ten minutes.
