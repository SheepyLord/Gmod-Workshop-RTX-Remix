# sv_interact_math.lua

Damage(speed,scale,held) keeps the legacy two-argument 65-cap curve. A.Hit always supplies
an explicit boolean: false caps actual bare hands at 25; true keeps held-object/weapon damage
up to 65. This preserves existing W callers without changing P's measured bare/held behavior.

Pure helpers for task P: closest point on a triangle/segment, vector clamp/cross/normalization,
120 ms recency-weighted throw/spin history, inverse grab offsets, two-hand rigid orientation,
inward flick, ballistic launch velocity, climbing error average and melee damage curve.
Included by the server interaction modules; callable directly in the LuaJIT harness.
Inputs/outputs are Source vectors/angles, game units, seconds and world XYZ radians/s.
No hooks, resources, engine mutation or file I/O; no process exit code.

Integration: Damage(speed, scale, held) caps bare contact at 25 and held-object contact at 65; the 1.5 m/s threshold and curve remain.

ClimbRelative calibrates a per-grip contact offset from hand-minus-head positions, cancelling common delayed body translation. Pull displacement applies once; acquisition does not jump. Existing Climb signature remains for direct callers.


Throw averages opt into enriched world velocity (wvel), falling back to vel for legacy standalone histories. Gesture/melee helpers continue to receive relative velocity.
