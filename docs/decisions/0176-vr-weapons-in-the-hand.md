# 0176: VR weapons in the hand

Status: accepted for V4 implementation, on the work branch pending milestone review. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

The binding [V4 plan](../handover/VR-V4-plan.md) puts the active weapon's world model
at the main shown hand, in the same world draw stage as the hands. W owns it; K and T
need an interface before their parallel implementation can use its final placement.

Publish a session-owned `NLVR.Weapon` table with exactly section 3's Active, Kind,
Muzzle, Ray, ConvergeAt and events, and `NLVR_SV.Weapon(ply)` on the host. Distances
are game units, angles Source degrees. Invalid tracking yields no muzzle/ray; switching,
death and Exit invalidate Active and remove the model. K/T compute their own points in
the current model's local frame. The table stays stable for a session; Active changes.

Placement will use the model's own right wrist bone where available, a correction for
each built-in weapon, and controller-local gun pitch. Left dominance changes hand, never
mirrors geometry. Models draw as world geometry, with a brief visual kick only. No
view-model draw or head punch is introduced. First commit establishes the contract before
calibration, firing and the physical mechanics, so K/T do not depend on provisional maths.
