# 0169: Physical VR hands and grabbing

Date: 2026-11-11. Status: accepted for the V2/V3 task P branch, following the approved
[VR design](../handover/VR-plan.md) and [task interfaces](../handover/VR-V2V3-plan.md). The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

Each server hand owns an invisible `base_anim` with an 8 kg VPhysics sphere, radius 0.075 m.
It is excluded from transmission to every player, including later joins. A bounded velocity
servo and swept hull follow the validated controller. The client resolver at priority 200
uses the server position after H's world stop. No client entity moves gameplay objects.

Grabbing finds the closest point on physics mesh triangles, per bone, inside 0.16 m of the
physical hand. A broad-phase box includes long props whose origin is far away. Missing meshes
fall back to the entity hull for a single body, or the individual bone centre for a ragdoll.
A world visibility trace, motion-enabled body, `sv_playerpickupallowed`, optional
`CPPICanPickup(ply)` and the standard `AllowPlayerPickup(ply, ent)` hook gate acquisition.
This is the ordinary use-key pickup permission, documented by
[Facepunch](https://wiki.facepunch.com/gmod/GM:AllowPlayerPickup); nil permits, false denies.
Inventory pickup uses its separate item hook (0171). The gravity gloves obey the same gates.

The server API is `Grab(ply, hand, ent, bone, localPos, localAng)`, `Release(ply, hand, throw)`
and `Holding(ply, hand) -> ent, bone`. Hands are physical `left`/`right`; offsets are the
controller's position/orientation in the selected physics body's local frame. Omitted offsets
use the nearest surface and controller orientation. Invalid, out-of-reach or non-finite arguments
fail without changing the current grab. Server events include the player; client `grab` and
`release` events carry hand, entity and physics bone. The client fills `Hand.held` and `grip_curls`.

A damped, force-limited spring moves the body, preserving mass, gravity, ownership and world
collisions. Angular velocity follows orientation with bounded acceleration. Two grabs of one
body align the local grip baseline to the world hand baseline; different ragdoll bones get
independent targets. Releasing one hand rebases the remaining orientation. The last release
averages the last 120 ms of the server's hand velocity/spin history with recency weights,
then converts hand velocity to centre velocity using the rigid body's angular contribution.
Spin converts world radians/s to local degrees/s for Source physics.

Only the player and owned proxies enable custom collision checks. A scoped `ShouldCollide`
excludes hands/held bodies from their player and hands from their held bodies; props' collision
groups, flags and owners are untouched. Rule caches are invalidated when pairs change.
`constraint.NoCollide` is unsuitable because it
[does not work with players](https://wiki.facepunch.com/gmod/constraint.NoCollide).
Death, stale/invalid tracking, vehicle entry, Exit and module failure release bodies and remove
proxies/callbacks. Death leaves VR active. Custom checks are restored at session teardown.
