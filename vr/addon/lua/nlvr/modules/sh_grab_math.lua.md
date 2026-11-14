# sh_grab_math.lua

Pure hold maths shared by the server's grab controller ([`sv_interact_physics.lua`](sv_interact_physics.lua.md)) and
the client's held-prop drawing ([`cl_interact_predict.lua`](cl_interact_predict.lua.md)), VR V8
([ADR 0203](../../../../../docs/decisions/0203-precise-vr-holds-follow-the-hand.md)). Included with `include()` by
both realms; it registers nothing (no hooks, entities, convars or files) and returns a table `G`. Units: game units
and seconds; "spin" is radians per second on world axes unless a name says local.

| Function | What |
|---|---|
| `Axes(a)`, `AngleFromAxes(X, Y, Z)` | Source's basis of an angle (X forward, Y left, Z up) and back |
| `Quat(a)`, `RotationError(from, to)`, `Rotate(a, rotation)` | Unit quaternions; the short-way rotation vector that turns `from` into `to`; an angle turned by a rotation vector |
| `WorldSpin(localDegrees, a)`, `LocalSpin(world, a)` | A `PhysObj`'s spin (degrees/s on its own axes) to world radians/s and back |
| `Limits(mass, inertia, scale, linked)` | How hard a hand moves a body: `STRENGTH` (900 N) and `TORQUE` (150 N m) over its mass and largest principal moment, capped at `MAX_ACCEL` (150 m/s^2) and `MAX_SPIN_ACCEL` (400 rad/s^2); error-closing caps `CORRECT`/`CORRECT_SPIN` (3 m/s, 10 rad/s), gentler for a bone of a jointed body (`LINKED_*`: 2 m/s, 6 rad/s over three ticks) |
| `Step(body, goal, limits, dt)` | One hold step: the velocity and spin changes that move `body` with `goal` (its `vel` and `spin` are how the goal moves with the hand) and close the error in `ARRIVE` (two ticks), never faster than it can stop in whole ticks at under half its strength; returns `dv, dw, distance, angle` |
| `Relation(bodyPos, bodyAng, anchorPos, anchorAng)`, `OneHand(rel, anchor)` | A body's pose in a hand's frame, and back |
| `Snap(point, palm, distance)` | Where a touched point rests: where it is, or `distance` from the palm toward it |
| `PairFrame(a, b)`, `TwoHand(two, a, b)`, `PairMotion(a, b)` | Two hands' frame (the line between them, rolled by their mean up, then forward), a body's pose from a pair relation, and how the frame moves (the midpoint's velocity; the line's swing plus the mean roll) |
| `Blend(pos, ang, offsetPos, offsetTurn, k)` | A pose plus a decaying offset |
| `Limit(v, max)`, `Cross(a, b)` | Vector helpers |

Constants: `PALM` (0.035 m), `TRACK_METRES`/`TRACK_DEGREES` (4 cm, 12 degrees: a hold within these is drawn at the
hand), `ARRIVE`, `SPEED`/`SPIN` (20 m/s, 40 rad/s caps). Tests: `companion/tests/vr_interact_harness.lua` (`v8_*`
cases) through [`vr_interact_tests.py`](../../../../../companion/tests/vr_interact_tests.py.md). No exit codes.
