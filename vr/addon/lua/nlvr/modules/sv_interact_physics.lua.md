# sv_interact_physics.lua

`New(server, ctx)` returns physical helpers used only by the active server module. Creates
hidden, non-transmitting VPhysics hand spheres and bounded velocity followers, rebuilding
their radii after a session scale/calibration change. Queries the closest per-bone mesh
surface and protected nearest reachable props; drives held bodies
with a force spring and angular servo. Weak physics-mesh cache dies with the module.
ApplyForceCenter takes kg*unit/s impulse: the bounded spring/gravity force is multiplied by the tick interval.
WorldTarget preserves H's 18 cm wrist/finger envelope in the server's world sweep; the
velocity-following sphere still pushes movable bodies. Climbing bypasses the extended stop.
World/prop sweep hits also queue the contact witness when base_anim supplies no collision
callback. It follows the same outside-solver handling and pulse throttle as native callbacks.

Track/Untrack reference-count held bodies and own their contact callbacks. BeginPull/EndPull
also exclude the assisted body's player pair until catch, miss or cleanup. The scoped
released-body pair exclusion lasts at most 0.2 s, preventing the opening hand from colliding
with and punching its own throw; MaintainReleased expires it and ClearReleased removes it
immediately on cleanup. World/other-entity collisions and prop collision flags stay active.
ShouldCollide hook excludes hands/held bodies from their player. PlayerInitialSpawn excludes
existing proxy entities from a new recipient. Neither changes any prop's owner, collision
group, mass or gravity. Start/Stop ownership belongs to sv_interact.lua. No convars or files
are written. Assertions/errors propagate to F's resource registry; no process exit code.

Q integration: BodyTrace(ply,ent) mirrors owned-player collision exclusions for explicit body/eye/teleport traces; world, NPCs and unrelated bodies remain solid.


Review correction: proxies spawn only after an eye-side sweep. Follow feeds forward world velocity and reports actual obstruction, not locomotion lag. Drive uses mass-normalised backward-Euler critically damped gains (slower heavy-body transient). Transport translates proxies and every held physics body once per validated teleport step. GloveClosest caches targeting hints for at most 100 ms; exact grab geometry remains uncached.


The stable PD numerator uses kd + kp*dt, with denominator 1 + kd*dt + kp*dt*dt. Tests require monotone critically damped settling, not merely bounded oscillation. Target-hint caches are separate per hand so pointing both free hands at one entity does not evict the other query. Teleported proxies sweep again from the destination eye side.


Verification correction: feed-forward and hold damping use wvel (legacy standalone calls fall back to vel). Bare proxy contact subtracts player locomotion. Transport releases externally constrained entities and sweeps whole held world bounds before carrying; blocked bodies stay on the original side and are released. Moving target hints reuse local contacts for the full 100 ms per-hand interval, with exact grabs uncached. Heavy omega minimum is 2.5 rad/s, restoring perceptible 250 kg lag while retaining stable mass-normalised critical gains.

Heavy mass response uses omega = clamp(24 / (max(mass,1)/10)^0.75, 2.5, 40); 250 kg uses 2.5/s. Backward-Euler damping stays stable while preserving perceptible transient lag with world-velocity feed-forward.

Post-crash verification tuning: omega = clamp(24 / (max(mass,1)/10)^0.75, 2.5, 40), giving 250 kg 2.5/s and 10 kg 24/s. World-velocity feed-forward and stable mass-normalized backward-Euler damping remain. The moving-heavy regression also requires >3 units for at least .36 s of its .5 s gesture, rather than a brief peak.

Held PhysicsCollide contacts, like bare proxies, subtract the owning player velocity from OurOldVelocity and derive speed from that relative vector. Walking with a still held prop is not a melee strike; a real relative strike still hits.

Q4 integration centralises armed-hand ownership and released-projectile grace in P; passive touch honours the claim mask. W no longer edits P cooldowns or vetoes proxy damage. Camera override users share a lease and restore on module failure/Exit, preserving other config writers.

Explicit external projectile registration also blocks immediate self-repickup during its <=250 ms grace. Ordinary thrown props keep the existing immediate API re-grab behaviour.
