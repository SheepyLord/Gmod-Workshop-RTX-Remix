# 0171: VR use by hand and melee

Date: 2026-11-11. Status: accepted for V3 task P under the
[VR interaction design](../handover/VR-plan.md). The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

Touching a button, door, lever or Lua usable within 0.13 m activates its normal Use with the
player as activator/caller. Grip/trigger can reactivate it; touch identity and a 0.3 s cooldown
prevent continuous toggling. A world trace rejects use through walls. `PlayerUse` and optional
`CPPICanUse` may deny it. Inventory items require a grip and `PlayerCanPickupItem` permission.
The engine/entity performs use/pickup; the module does not invent health or ammo grants.
Use checks start at the physical hand, so an occluded controller cannot reach through a wall.

`nl_vr_melee` enables server contact damage above 1.5 m/s. Damage is
`min(65, 5 + (speedInMetresPerSecond - 1.5) * 12)` club damage, with a per-hand/per-target
0.35 s cooldown. Hand sweeps and queued held-object physics contacts supply the impact;
damage is applied outside the physics callback. Ordinary damage hooks still run. A slow
living NPC contact pushes its velocity; a living NPC can never be grabbed. Physics props
and ragdolls receive impulses through VPhysics. Settings/claims cannot nominate a target.

`ai_serverragdolls` is enabled only for this server module's session so an NPC's death body
can be posed. Its exact old string is restored at teardown if it still has our value.
No global scripted entity, network receiver, timer or archived setting is added by this module.
Short haptic pulses distinguish contact, grab, release, catch and hit; stronger impacts give
stronger pulses. The changed-state packet carries sequence numbers so unchanged packets do
not repeat a pulse. Native haptics remain owned by the existing `nlvr` session.
