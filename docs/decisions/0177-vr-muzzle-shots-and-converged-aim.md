# 0177: VR muzzle shots and converged aim

Status: accepted for V4 implementation on the work branch. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

Follow the binding [V4 plan](../handover/VR-V4-plan.md): eye-based traces converge on
the gun ray's first hit (or T's held distance). Head camera tracking is independent of
the command aim; recoil kicks only the world gun model. Commands retain the core's
movement rebasing. UI claims precede weapons; K can claim A without fighting W.

Message 64 reports class, physical hand, model-local muzzle/foregrip offsets in metres,
two-hand request, pitch and melee setting. Validate finite/range/class, retain no client
absolute muzzle, and transform the geometry from the server's stopped P proxy. Both
hand poses must be current and reachable. A trace from engine eye to muzzle clamps a
blocked start to the eye side with 1 cm skin. Foregrip acquisition/release use 12/25 cm.

W owns EntityFireBullets. Keep spread and original Callback (including its return), set
Src/Dir from that muzzle, and disable native tracers. Send actual hit feedback on 65,
with a sequence so identical repeated shots remain distinct. The client draws a tracer
with explicit Start and no Entity/Attachment, and a world MuzzleFlash plus short light.
Valve's [weapon source](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/c_basecombatweapon.cpp)
GetShootPosition uses the local view model's muzzle attachment; hiding that model alone
does not establish the tracer's start. Source is read for behavior, never copied.

OnEntityCreated queues only the six named HL2 projectiles. At the first tick with an
owner and native launch speed, redirect bolts/rockets/SMG grenades/AR2 orbs to the
checked muzzle, retaining speed. Frag/bugbait instead use P's history throw at release.
The bounded pending queue expires after 250 ms, is removed at Exit and never changes
other players' projectiles. Diagnostic records include actual positions, hits and ticks.
