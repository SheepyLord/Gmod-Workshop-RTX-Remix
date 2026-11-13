# cl_weapons.lua

Session-only client weapons, order 44. Included by client.lua at Start VR; Exit removes
its world model, hooks, mover, subscriptions and `NLVR.Weapon`. No files/settings are written.

The stable V4 interface is `Weapon.Active` (nil or ent/class/kind/model/hand/twoHanded),
`Kind(class)`, `Muzzle()` (world position/angles), `Ray()` (world origin/unit direction),
`ConvergeAt(distance or nil)` (game units). `weapon_changed` carries Active, including nil
when unarmed/dead; `weapon_fired` carries Active. K/T derive their local points from model.
Read the current Active rather than retaining an old weapon across switches. Muzzle/Ray
return nil while tracking is invalid. Hands has no model and does not converge engine aim.

Uses the core's frame, owned world-stage hook and mover; never the view-model camera.
The registry owns failures and reverse teardown. No process exit code; include errors
propagate to session startup. The late hand resolver closes fingers and places a foregrip;
claims preserve UI priority and K's A control. The mover sets attack buttons and converges
aim, dropping inherited desktop primary/secondary bits while armed; only the model kicks.
Message 64 sends bounded model-local geometry on change and
retries at 10 Hz until the matching token is acknowledged on 66. Initial/profile changes
wait for acknowledgement; gun-angle updates retain an already accepted profile and do
not pause firing. The profile carries foregrip permission/offset once, not engagement.
Message 65 receives actual shot feedback. The server broadcasts explicit-start tracers;
the owned bullet dispatcher suppresses only the local VR player's initial predicted tracer.
MuzzleEffect consumes explicit origin/angles/scale at the checked server muzzle, with a
short light; weapon_fired follows effect creation. Debug exposes plain poses,
class/kind, aim, grip/draw/fire counts and the last shot. Death/invalid tracking gate work.
If the engine weapon registry is absent the feature stays dormant with zero resources;
the head/hand core remains usable. W's own harness supplies and exercises the registry.


## V4 controller frames

C consumes SteamVR-oriented palm targets, anchors guns with H's measured palm, and closes armed/support hands. Hand curls owned by W clear on release or selecting Hands; corrections are only on shown angles and never feed back into the target aim.

The left grip uses the paired anatomical hand frames to orient the left palm on the opposite side of the same upright weapon. Only hand rotation/anchor change; no negative model scale. Measurement resets model scale and bone cache to authored units before reading, so calibration does not compound a previously rendered scale.

Foregrip snaps the support hand's grasp centre onto the weapon point, retaining the shown palm as a palm. The configuration signature includes all three foregrip components. Debug grip_pos names the model anchor; actual capture analysis independently reads the model and the drawn finger arc.

Review follow-up: per-physical-hand grip latches retain ownership until real release after foregrip pull-away, non-foregrip switch, Hands selection, and dominant mirroring. Trigger ownership is not latched. This prevents P from receiving a fresh grip while it is still squeezed.

## Review correction (2026-11-12)

Physical trigger claims now latch through foregrip exits and weapon/Hands switches until release, under either dominant-hand setting, like grips. Geometry invalidation depends only on its holding frame. A usable tip aims the gun even when the hand component is missing. Debug reports model-measurement count/CPU time.

The optional session-owned WeaponDrawObserver records the rendered model anchor for the private fixture. No callback/table work occurs when absent; the fixture removes its observer at Exit.

The dispatcher supports stock live tables and ULib's separate priority/compatibility
tables, preserving priority order, additions/removals and later writers. An ordinary
hook.Add fallback remains installed for other libraries; a private capability probe
checks whether GetTable really exposes a live root. Global hook.Call stays unchanged.
An owned gamemode method wrapper applies W's modified bullets after a nil-returning
gamemode, preserves false and restores only its own writer. Other players and secondary
starts remain on their original path. No model-decal setting is read or changed.
See decision 0193 and the W report.

The dispatcher guards recursive replay and detects a copied/later event registry. In
that case it prepares once and lets the caller iterate its other callbacks once.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
