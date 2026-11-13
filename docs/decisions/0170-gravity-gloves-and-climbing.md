# 0170: Gravity gloves and climbing

Date: 2026-11-11. Status: accepted for V3 task P; implements the
[binding design](../handover/VR-plan.md) through F's existing services. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

`nl_vr_gloves` selects the nearest loose, moving, unheld non-ragdoll body on the server hand
ray, at most 6 m away and 150 kg. Grip locks it; moving 0.075 m toward the head with inward
speed at least 0.85 m/s within 1.2 s launches it. This requires displacement as well as speed,
preventing tracking noise or merely squeezing from pulling a prop. The initial velocity solves
the ballistic endpoint under the server's actual gravity; flight is 0.35..0.9 s. The final
0.28 s re-solves for the moving hand. World obstruction, changed permission or released grip
ends assistance without disabling collisions. Grip catches within normal grab reach; an
uncaught prop falls under its existing gravity. A catch uses the public Grab API.

The target marker is a small SteamVR overlay, using F's reserved odd sizes 273x275 and
277x279 and a world-to-tracking conversion. No halo, world UI draw or path-traced marker is used.

`nl_vr_climb` enables a grip on a nearby world lip/side edge or ladder. Acquisition checks the
normal and clearance above or beside the surface; the middle of an uninterrupted wall is
not an anchor. Anchor coordinates remain on the server. The priority-5 mover averages the
error of active grips, sweeps the player's current standing/duck hull, and changes move data.
It suppresses ordinary movement/gravity only while it owns the move. Two hands may alternate;
the last release preserves capped displacement velocity for the next normal gravity step.
Player move type and gravity settings are never rewritten.

Climbing proxies ignore floor/ceiling physics contacts while their explicit sweep still stops
lateral walls. Release restores their ordinary physical collision. H's earlier floor stop is
replaced by the server resolver. Settings and input-claim masks travel in message 40; physics,
targets, held bodies, climb state, throws and haptic sequence travel together in message 41.
F coalesces unchanged output and enforces at most one server packet per player/tick. No
entity, anchor, melee target or pull velocity is accepted from a client module message.
