# 0179: Holding the engine's reload for physical VR reloads

Date: 2026-11-11. Status: accepted for V4 implementation on its task branch,
under [the V4 plan](../handover/VR-V4-plan.md); milestone approval remains separate. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

## Decision

Only the package's admitted VR host, after the reload module's client heartbeat
enables physical reload, uses the seven stock HL2 guns' physical reload path.
StartCommand removes IN_RELOAD. Empty/ejected weapons keep next primary fire an
hour ahead, refreshed each command. No secondary deadline or player attack lock
is changed. Returning to flat mode, disable, stale heartbeat, death, vehicle entry
or module failure releases only deadlines still owned by this module, to at least
CurTime (earlier times can burst accumulated shots).

The engine has paths beyond the reload key: base ReloadOrSwitchWeapons gates
empty auto-reload and empty switching on next primary, and shotgun has its own
equivalent gates. Crossbow's m_bMustReload invokes Reload independently, so it is
cleared while physical reload owns the weapon. An inherited m_bInReload is cancelled.
The pistol can rewrite its primary deadline from m_flSoonestPrimaryAttack, so that
deadline follows/restores the hold too. Shotgun holster auto-reload is held off by
refreshing its holster timestamp while physical reload is enabled. Live-game proof
must accompany these SDK-derived expectations; the harness is not an engine simulator.

Shotgun insertion adds one shell and clears the empty chamber/delayed-fire state
on the first shell; loaded cycling remains the native weapon's. Crossbow insertion
clears must-reload. The RPG consumes reserve directly, not Clip1: a ready latch
releases one native shot and relatches after reserve consumption. Insertion does
not remove an RPG rocket as well as native fire; that would charge twice.

## Evidence and consequences

Reference-only Valve SDK behavior: [base combat weapon](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/basecombatweapon_shared.cpp),
[shotgun](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/hl2/weapon_shotgun.cpp),
[crossbow](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/hl2/weapon_crossbow.cpp),
[RPG](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/hl2/weapon_rpg.cpp).
Facepunch documents the [pistol exception](https://wiki.facepunch.com/gmod/Weapon:SetNextPrimaryFire)
and [save-value API](https://wiki.facepunch.com/gmod/Entity:SetSaveValue).
No SDK/gVRMod code, comments or tables are copied. Weapon-specific fields are
written only when exposed by the engine. Unknown SWEPs keep their ordinary reload.
Task K's report records actual per-class five-second/native-cycle results and limits.
