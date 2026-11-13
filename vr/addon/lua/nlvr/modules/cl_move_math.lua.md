# cl_move_math.lua

Pure shared movement rules; included by both move modules. No hooks or persistent state.
Uses Source vectors/angles and a supplied trace for the ballistic curve. Engine adapters query
the player's current hull, standing hull, step size and `MASK_PLAYERSOLID` world collision.

Exports: finite checks, bounded vectors, yaw rotation, radial stick deadzone, crouch hysteresis,
the continuous virtual crouch offset capped by the standing-to-duck height difference,
calibration, vignette and turn rules; segmented arc, landing/route checks and room-scale sweep,
slide and step. Constants reserve messages 24 (room input), 25 (teleport request), 26 (result),
27 (follow receipt). Distances are game units; calibration/tracking input uses metres;
angles are degrees; times seconds. Landing requires standing clearance, standable floor,
8 m range, at most 1.5 m upward mantle, and an unobstructed standing-hull route.
The direct route is tried first, preserving usable low doorways and a level dash. A blocked
direct route tries the raised route for a ledge, still without crossing any solid.
No files written. Returns the helpers; raises only for invalid engine interfaces.
`SweepRoute` includes the exact route corners between fractions, so a coarse server tick cannot
cut through a ledge on a diagonal. Blocked-follow feedback detects residuals above 0.01 game units.

Q integration: movement/eye/teleport TraceHull uses the active server BodyTrace filter. Explicit traces otherwise hit the non-transmitting hand proxies inside the player even though ShouldCollide excludes them.

The matching client BodyTrace predicate keeps render prediction/eye sweeps from fading against the player's own held prop, matching server collision authority.
