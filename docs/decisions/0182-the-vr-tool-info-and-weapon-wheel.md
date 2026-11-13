# 0182: The VR tool info and weapon wheel

Date: 2026-11-11. Status: implemented on v4t; real menu/actions and Index sources recorded;
reviewed K's B/reload integration passes simulation; final C/Index acceptance remains open.
Authority: [V4 plan](../handover/VR-V4-plan.md), toolgun and weapon-wheel decisions. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

The real toolgun remains active. W converges the user's command onto the hand ray; W owns
trigger/A and K owns B taps. The tool selected by the stock spawn-menu tool list is read
from the player's gmod_toolmode and the weapon's GetToolObject. T paints its translated
name and left/right/reload information, including current stage/operation variants, in the
reserved 643 x 133 SteamVR canvas beside the shown hand. It repaints only when displayed
content or mode changes. Tool application and permissions stay with stock/add-on callbacks.
No tool action is reimplemented or called directly by T.

Holding main B for 0.3 seconds opens a 42 cm ring at the hand, facing the head. The opening
plane stays fixed; moving the hand in that plane selects after a 3 cm dead zone. Hands is
first, then the player's weapons by HUD slot, slot position and stable class tie-break.
Icons use WepSelectIcon where supplied and the HL2 selection glyphs, otherwise slot/name.
Names are elided at UTF-8 character boundaries; the complete text remains in debug.

There are at most 12 entries on a page, preserving readable sectors for large inventories.
Beyond the ring at 24 cm up/down, within 10 cm horizontally, advances/wraps a page once.
Returning inside 18 cm vertically rearms paging. The header shows the current/total pages.
Releasing B queues SelectWeapon in CUserCmd for the highlighted owned weapon. Neutral release
selects nothing. A selection skips prediction command zero and retries for at most one second
until the engine acknowledges the active weapon; ownership/liveness loss or a new wheel cancels.
An earlier K B tap can retain ownership until native reload readiness. T waits for that claim
to clear before opening a new hold, and cancels an open wheel if it loses B ownership; it
never consumes K's pending reload by masking its command while operating an unowned control.
Lost tracking, death, mirroring and Exit cancel. A cancelled held B must be
released before reopening. A tap never creates a canvas.

Frame order gives W first claim of an armed trigger. T preserves that claim and consumes
both attack bits and reload in its final mover while the wheel is open; it claims the
trigger itself when free. P therefore never receives that trigger as a grab/use. A trigger
held while closing stays consumed until release. NLVR.Tools.WheelOpen exposes the state to
W without changing its binding Weapon interface. No +attack commands or global claim reset.

The engine's [SWEP selection drawing](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/gamemodes/base/entities/weapons/weapon_base/cl_init.lua)
uses WepSelectIcon; HL2 glyphs are documented in the stock weapon scripts, for example
[pistol](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/scripts/weapons/weapon_pistol.txt)
and [physgun](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/scripts/weapons/weapon_physgun.txt).
The stock gmod_tool/cl_init.lua filters Information by stage/operation and uses translated
tool.<mode>.<line> phrases. These are observed interface/data contracts, not copied gVRMod code.

All code is loaded only at Start and resources belong to the tools module. Offline tests
use an independent Weapon stand-in; real tool/menu/command behavior requires the PoC and
compositor receipts in [T's report](../handover/VR-V4-T-report.md). This task changes no
framework/W/K/M source or loader behavior and does not extend multiplayer authority.

## Independent-review corrections, 2026-11-12

The earlier one-second retry rule is superseded: issue one networked SelectWeapon attempt,
then wait up to one second for acknowledgement. Refusal displays a passive two-second
notice in the existing wheel source. SWEP DrawWeaponSelection overrides are used; unsupported
Use-modifier tool lines are excluded from Trigger/A/B. Wheel-consumed physical triggers
stay claimed until release across close, cancel, tracking loss and a dominance change.

Debug objects and remembered entries are reused. Tool info refreshes on mode/object/stage/
operation/language change, otherwise at most every 0.25 s for dynamic text. Open inventory
membership polls at most every 0.25 s (invalid entries immediately), sorting only on change.
Closed inventory does no polling. Exact unchanged visibility/transforms skip native calls;
beam material, Color and debug object are reused. Failing-before and native proof are in
T's report; old frozen-source receipts are not relabelled as this implementation's proof.

## Verification follow-up, 2026-11-12

The placement cache coalesces motion within 1 mm and a wrapped Euler delta norm within
0.1 degree against the last submitted pose; accumulated motion still updates. Visibility
and width changes remain immediate. This supersedes bit-identical placement caching,
which did not reduce native calls for a moving tracked hand. The inherited weapon_base
DrawWeaponSelection is not a custom override; Hands keeps its dedicated glyph.

The generic WepSelectIcon texture is inherited separately from DrawWeaponSelection;
both base defaults are excluded. Stock weapon_base/cl_init.lua line 18 defines that
texture. The stand-in now inherits both, and the first v4t.11 picture retains the failed
paper-icon state before the subsequent fix.
