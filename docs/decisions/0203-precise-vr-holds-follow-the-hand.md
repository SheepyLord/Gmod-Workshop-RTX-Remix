# 0203: Precise VR holds follow the hand, and held props are drawn where the hand is

- Status: Accepted 2026-11-13 for V8 on the branch `vr8`; reaching `main` needs the user's approval. The user approved V8 on 2026-11-13 and it was merged to `main`.
- Decided by: Claude, at the user's request of 2026-11-13 ("make the grabbing more hands-on and precise. Allow rotate
  using 1 hand and use two hands to grab at the same time").
- Refines: [ADR 0169](0169-physical-vr-hands-and-grabbing.md)'s hold (its "damped, force-limited spring"), keeping its
  acquisition, permissions, API and the mass lag of heavy bodies.

## Context

V3's hold pushed the held body toward a pose taken from the hand's physics proxy, a sphere that itself follows the
controller by velocity (about 45 ms behind). The push was a force spring whose stiffness fell with mass (a 10 kg body
settled in about 40 ms, a 100 kg one in 230 ms), so the body lagged the proxy that lagged the hand. Rotation was a weak
velocity nudge from Euler-angle differences (time constant 0.3 to 1 s), so turning the wrist barely turned what it held,
and the hand's own velocity and spin were not fed forward. The client drew the body where the server's physics had it,
a few ticks after the hand had moved. Nobody had worn the headset; the user then found grabbing imprecise and
one-hand turning missing.

## Decision

- **What a hold follows**: the tracked palm, stopped at world brushes where the proxy's own target stops
  (`P.Anchor`), not the proxy's physics position. A hand inside a wall (where that target falls back to the eye) keeps
  its last anchor.
- **The relation**: a grab stores the body's pose in the hand's frame. The touched point comes to rest against the
  palm (3.5 cm from the palm frame) if it was farther, so the object meets the hand instead of floating at the 16 cm
  reach. An API caller's `localAng` (the hand's orientation in the bone's frame) still sets the body's orientation.
- **The controller** (`sh_grab_math.lua`, shared with the client): velocity control of the body's mass centre and
  orientation toward the hold, with the hand's linear and angular velocity fed forward, so a moving, turning hand is
  followed without a steady error. Rotation error is a quaternion rotation vector. Errors close in two ticks, braking at
  under half the available strength so a hold never overshoots. The hand's strength (900 N and 150 N m, at most
  150 m/s^2 and 400 rad/s^2) limits heavy bodies: up to about 30 kg a body follows a 1 m/s hand within 1.5 mm; a
  250 kg crate still lags as ADR 0169 and its tests require (over 3 units after 0.6 s of a 20-unit step). Closing an
  error is capped (3 m/s and 10 rad/s; 2 m/s and 6 rad/s over three ticks for a ragdoll bone), so a body pressed on a
  wall, or a bone held back by its joints, is never driven hard into it. Gravity is paid in advance each tick.
- **Two hands on one body**: a pair frame (the line between the hands, rolled by the mean of both hands' up) holds the
  body; its relation is captured where the body is when the second hand closes, and re-captured for the remaining hand
  when one lets go, so neither event moves the body. Two hands on different bones of a ragdoll drive them separately.
- **Drawn where the hand is**: the server sends each hold's relation, whether the body follows it now (within 4 cm and
  12 degrees; it lets go past twice that), and whether the entity is one body. The client draws such a prop at the
  hold's pose from this frame's hands through a `RenderOverride` that keeps and calls any override already there;
  ragdolls and held-back bodies are drawn where the physics has them. Every switch between the two blends over 0.12 s,
  so a throw or a blocked body never jumps.

## Consequences

- Light props stick to the hand and turn with the wrist; the drawn hold no longer trails the hand by the server's
  round trip. Heavy bodies keep their weight.
- The client message 41 grows by the hold relation (floats, not quantised), two flags per hand and the pair frame.
- V3's in-game check of the 250 kg crate (phase 4: over 3 units of lag for a whole second at a 0.5 m/s hand) described
  the old spring. With a hand's strength the crate lags while the hand's motion starts and then follows: about 1.6 units
  at that speed, 6.8 at 1 m/s (where the offline checks keep V3's bounds). No acceleration limit meets both of V3's
  checks, so the in-game one now asks for over 1 unit for at least 0.1 s, measured every tick: the PoC's first run
  (`interact-sim-01`) saw 1.44 and 1.51 units where the hand's motion started and stopped and 0.06 in between, windows
  shorter than the probe's 0.25 s samples.
- Untested in the headset until the user allows an in-game run: the offline harness simulates rigid bodies only, not
  ragdoll joints or contacts, so the caps for those are reasoned, not measured.
