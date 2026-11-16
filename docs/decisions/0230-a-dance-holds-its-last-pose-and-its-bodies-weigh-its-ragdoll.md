# 0230: A dance holds its last pose, and a dancing NPC's bodies weigh its ragdoll times a push strength

- Status: Accepted 2026-11-16 (the user's requests of 2026-11-16)
- Package only: the character motion importer part (`packages/character-motion-importer`); no loader, runtime or
  native change.

## Context

The user: "In the animation player, add a 3 seconds delay after the animation ends and return to the reference
pose." And: "The physical interaction of the NPC to the world is good, but currently, dancing character's physics
interaction transfer way too much momentum to the object being interacted. Add an option to allow adjustment of the
interaction."

- A dance that ended (not looping) stopped at its last frame: `StopPlayback` put the NPC back at its start spot in
  the reference pose in the same tick, so the end of a motion snapped away at once.
- Since [ADR 0224](0224-the-animation-player-answers-a-click-with-its-built-flags.md) a dancing NPC collides through
  colliders shaped as its ragdoll's main bodies, each a physics shadow its bone drives every tick
  (`MakePhysicsObjectAShadow(false, false)`, `UpdateShadow`). A shadow the physics may not move weighs 50,000 kg
  (`GetMass` in the PoC) and nothing can slow it: a prop in a limb's way is shoved off at the limb's speed and more.
  In the PoC a fast arm swing (out in four frames) threw a 7 kg paint can at 1,177 units/s and broke a watermelon.

Two designs were measured in the PoC and dropped ([report](../handover/qol-2026-11-16-report.md)):

- **Lighter immovable bodies.** With each body weighing its ragdoll body, a slow swing still sent a watermelon off at
  60.6 units/s (44.6 with the 50,000 kg bodies) and a can inside the hand at 151.9 (111.6): the shadow controller puts
  an immovable body on its bone whatever it meets, so its mass does not set the push.
- **Scaling what a hit gave a prop.** Props within reach got a collision callback, and on the next tick kept a share
  of the speed a body's hit gave them (the callbacks fire: one hit per swing). But a slowed prop is overrun by the limb,
  which is still forced onto its bone: at 25 % the paint can reached 564.8 units/s (4 hits), at 0 % 308.2, against
  189.2 at 100 %, and the hit's damage, done at the impact, still broke the watermelon at 0 %.

## Decision

1. **The end hold**: when a non-looping dance reaches its last frame, it keeps applying that frame for
   `MMDVMDNPC.EndHoldSeconds` (3) and then stops as before (start spot, reference pose). Colliders, eye tracking and
   the camera's last key stay through the hold; a pause during it lengthens it by the pause. A player's own dance
   (the self proxy) holds the same way before the player is given back.
2. **Bodies the physics may push back, with a weight the player sets**: each collider is a shadow its bone drives
   that the physics may move (`MakePhysicsObjectAShadow(true, true)`, no gravity), weighing the same body of the
   model's ragdoll (read with its shape from the ragdoll that exists for an instant) times the player's
   `mmd_vmd_npc_ragdoll_push` percent: 100 by default, 0 to 500 (at least VPhysics' smallest mass, 0.1 kg). What a
   body hits gets a body's share of momentum, and a prop heavier than the body slows it; the controller brings it
   back to its bone. The setting is read again twice a second, so the slider acts on a dance already running.
3. **The bodies' own collision rule** (`ShouldCollide`, `SetCustomCollisionCheck`): bodies that may move would push
   each other apart where they overlap at the joints and press against the floor, so they collide with neither each
   other nor the map; every other pair is the engine's. Players and NPCs are blocked by traces, the same at any value.
4. A slider and its help on the tool's Build & Playback tab, in the add-on's nine languages.

## Consequences

- Measured in the PoC with the same fast swing: at 100 % the paint can reached 207.0 units/s (1,177.2 before), at 25 %
  88.4, at 0 % 35.7; the watermelon broke only with the old bodies. The bodies stayed on their bones (largest gap 0)
  and still stopped traces and a player-sized hull.
- The old immovable bodies are not a setting any more: 500 % is five times the ragdoll's weight.
- A model whose ragdoll body reports no mass gets 5 kg per body.
