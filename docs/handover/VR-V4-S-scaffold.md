# VR-V4-S: the scaffold for V4

Read [VR-V4-plan.md](VR-V4-plan.md) first, all of it, then [VR-V2V3-plan.md](VR-V2V3-plan.md) and task F's report
`docs/handover/VR-V2-F-report.md` ("how to write a module"). You prepare the ground so that three tasks (W weapons,
K reloading, T tools) can work in parallel without touching the same files. Keep it small and exact: this task
should take an hour or two, not a day.

Your branch is `v4s`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4s`.

## What to build

1. **Modules.** Stub modules `vr/addon/lua/nlvr/modules/cl_weapons.lua`, `cl_reload.lua`, `cl_tools.lua` (orders
   44, 46, 48) and `sv_weapons.lua`, `sv_reload.lua`, `sv_tools.lua`, each registering and doing nothing, with their
   `.md`; `weapons`, `reload` and `tools` added to the client's fixed list in `client.lua`, the three server modules
   to `server.lua`'s. Make sure the new files reach the client exactly as F's files do (single-player and the
   listen-server host), and say how in your report.
2. **Protocol.** `sh_protocol.lua`: module message types 16..127 (`ModuleType`), ranges `weapons = {64, 79}`,
   `reload = {80, 95}`, `tools = {96, 111}`; check every place that validated 16..63 (client and server), and test
   that 64..127 pass and 128 and above do not.
3. **Overlays.** `cl_overlay.lua`: `wheel = {1035, 1037}`, `tool = {643, 133}`; task M's two sizes moved into the
   central table (`settings = {1283, 963}`, `flat_close = {131, 133}`, now reserved inside `cl_ui*.lua`: change M's
   code to read them from `NLVR.Overlay.Sizes`, nothing else in it); and `keyboard = {1039, 391}` reserved for M's
   coming fallback keyboard. The existing uniqueness and oddness checks cover them.
4. **Settings.** The page's settings table (`nativeloader_vr.lua`): `nl_vr_physical_reload` (1, 0-1),
   `nl_vr_foregrip` (1, 0-1), `nl_vr_ammo_counter` (1, 0-1), `nl_vr_gun_angle` (0, -45 to 45); a "Weapons" group in
   `VR.BuildOptions` (three check boxes and a slider with a one-line help each, in the page's style), the core's
   `Settings` reading them like the others. Translations of the new strings in French, Japanese, Korean, Russian,
   Simplified and Traditional Chinese, written by a Python script with explicit UTF-8 into the companion's catalogs,
   checked for `?` runs, as the V2 page strings were.
5. **The harness.** Stand-ins in `companion/tests/` for what W, K and T will test offline: weapon entities (class,
   `Clip1`/`SetClip1`, `Clip2`, `GetMaxClip1`, `GetPrimaryAmmoType`/`GetSecondaryAmmoType`, `SetNextPrimaryFire`
   and its value, `GetNextPrimaryFire`, `GetWeaponWorldModel`, `GetHoldType`, `IsScripted`), the player's weapons and
   ammo (`GetWeapons`, `GetActiveWeapon`, `GetAmmoCount`, `GiveAmmo`, `RemoveAmmo`, `SetAmmo`, `Give`,
   `StripWeapon`, `SelectWeapon`), `CUserCmd` buttons, mouse wheel and `SelectWeapon`, `EntityFireBullets`' data
   table, `weapons.Register`, attachments (`LookupAttachment`, `GetAttachment`) and bones on client-side models.
   Extend F's harness files in its style; one test per stand-in showing it behaves as GMod does (cite the wiki page).
6. **The gate.** A bridge in `tools/tests/` for each existing feature suite that the gate does not run yet (H's
   `companion/tests/vr_hands_test.py`, L's `vr_move_tests.py`, and M's and P's if theirs are outside `test_vr.py`),
   and one prepared for W, K and T to fill (or tell them the exact file name to add). The gate's log must show each
   suite's count.
7. **The user command's angles** (two core fixes Claude's reviews found). In the core's `CreateMove`: the view
   angles taken from the head keep its pitch and yaw and zero its roll (a tilted head must not roll the player or the
   flat view); and when `NLVR.Aim` replaces them with a different yaw (W's gun aim), the command's forward and side
   movement are rotated by the yaw difference, so the player still moves where the movers meant (task L's note: "V4
   must preserve/rebase command movement if it replaces the final command's head aim with gun aim"). Offline tests
   for both: a head rolled 30 degrees; a mover's world movement direction unchanged under an aim 90 degrees off.
   Task L may change how the core gets the feet (`feet()`, `C.Feet`) at the same time: touch nothing else in
   `cl_core.lua`.

## Files you may change

The files named above (`client.lua`, `server.lua`, `sh_protocol.lua`, `cl_overlay.lua`, `cl_ui*.lua` only for the two
sizes, `cl_core.lua` only for the
settings and `CreateMove`'s angles and movement, the six new stubs, `nativeloader_vr.lua` and its catalogs, the
harness files, the bridges in `tools/tests/`), their `.md`, decision record **0175** (V4's scaffold: module ranges,
the control ownership table, the new settings, the command's angles under aim) with its line in
`docs/decisions/README.md`, and your report. Nothing else.

## Proof

Offline tests for the protocol range, the overlay sizes, the settings (created with the right ranges, read by the
core, on the page), the stubs (started and stopped with the others, no hook left after Exit). One simulated PoC
session (`tools/vr_session.py --simulate`) showing the session still starts, runs and exits cleanly with the stubs
and the page's new controls (a capture of the page at 1920 x 1080 and at 3840 x 2160 with the GUI Scaler's sizes,
as V2 checked M's page). `tools\test.ps1 -Config Release` passing.

## Report

`docs/handover/VR-V4-S-report.md`: what you changed, how the new files reach the client, the bridge file names for
W, K and T, the test counts, your text for the shared documents.
