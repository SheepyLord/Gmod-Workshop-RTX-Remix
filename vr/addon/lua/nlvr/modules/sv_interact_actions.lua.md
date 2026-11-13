# sv_interact_actions.lua

`New(ctx, pulse, grab, release)` returns server use, NPC push/melee, glove target/pull,
climb acquisition and movement helpers. sv_interact.lua supplies `.physics`. Called once
per server tick with validated poses/options and from F's priority-5 mover. Uses physical
hand positions for contact, server ray/visibility for targeting and server history for throws.
An unoccupied squeezed hand can acquire a new touched prop without another button edge;
climbing and glove targeting still begin on the grip edge.
Usables remain claimed while touched so continuing grip cannot convert a button into a prop
grab. Touch uses 0.13 m; a squeezed hand uses 0.16 m. Held grip can consume native kits on contact.

Use invokes ordinary protected entity Use. Only a real scripted Use counts; base_anim's
empty method does not consume a physical grip. Scripted kits keep their author-provided Use.
Native inventory kits instead enter their pickup trigger at the player for at most 0.15 s;
the engine grants inventory through its usual touch
and item hooks. A refused/full kit restores its transform and velocities if still at our
staging point; native respawns and externally moved items are left alone. UpdateItems and
RestoreItems own this temporary state, including Exit/unload. Melee creates club DamageInfo outside the
physics callback; gloves launch/retarget a colliding ballistic body and catch through Grab.
Point ladders are reached through their native mount endpoints; brush ladders use the ladder
contents trace. Save-table keyfields use the map aliases point0/point1/StartDisabled, with
member-name fallbacks for compatible entities. Climbing
sweeps move-data's player hull, owns gravity via Move arbitration, then preserves
release velocity. No player move-type/gravity, prop owner/collision flags, file or convar
mutation. Per-hand cooldowns/targets/anchors live under state.interact. No process exit code;
module errors unwind through F's registry.
Recently released bodies are excluded from that player's melee during the short pair grace,
so a queued hand callback cannot multiply a throw's measured native velocity/spin.
Low-speed swept contact, including living NPCs, still gives contact feedback before the
damage threshold; stronger hit pulses win within the same tick.

Integration: only source="held" selects the 65 damage cap; bare contact caps at 25. NPC pushing and cooldown are unchanged.

Q uses head-relative climbing constraints, retaining authoritative hull sweeps, averaged two-hand anchors and bounded release velocity. World poses carrying delayed motor motion no longer feed body movement back into the next climb step.

Use cooldown is shared per player/entity across both hands (weak-keyed). Simultaneous hand
contacts cannot turn a toggle on and immediately off; permission checks and native Use remain.


Review correction: melee impulse transfers at most 55% of the limited hand velocity to light props and scales down for bodies heavier than 8 kg. Gloves reject excessive mass/range and unsuitable physics before the cached final-candidate mesh query.


Native props receive bounded momentum exactly once: DamageInfo carries zero force for a valid physics body, then ApplyForceOffset applies the computed mass-scaled impulse. Non-physical NPC damage retains bounded force. A.Target accepts optional hand identity for independent left/right target caches.

Q4 integration centralises armed-hand ownership and released-projectile grace in P; passive touch honours the claim mask. W no longer edits P cooldowns or vetoes proxy damage. Camera override users share a lease and restore on module failure/Exit, preserving other config writers.

Independent review: contact is observed while Use is masked, so ending a claim cannot create a contact edge. Physical button history is retained through claims. Whole-hand ownership blocks bare impacts; an off grip claim alone retains off-hand damage, while the authoritative main hand grip mask still gates its bare impacts.


Watch-only contact updates return false: they do not consume an available grip while the menu owns only the trigger.
