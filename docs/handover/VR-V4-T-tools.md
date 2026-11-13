# VR-V4-T: the physgun, the toolgun and the weapon wheel

Read [VR-V4-plan.md](VR-V4-plan.md) first, all of it, then [VR-V2V3-plan.md](VR-V2V3-plan.md) and the reports of
tasks F, L, M, P and S in `docs/handover/` (`VR-V2-F-report.md`, `VR-V2-L-report.md`, `VR-V2-M-report.md`,
`VR-V3-P-report.md`, `VR-V4-S-report.md`), and W's `VR-V4-W-report.md` and Q's `VR-V2V3-Q-report.md` when they
exist. The plan's section "Weapons and tools" in [VR-plan.md](VR-plan.md) describes what the player should get.

Your branch is `v4t`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4t`. Task W builds the
gun in the hand (`NLVR.Weapon`, plan section 3) in parallel: until W is merged into `vr2`, test offline against your
own stand-in of it; when Claude has merged W into `vr2`, merge `vr2` into your branch for PoC runs.

## What to build (`modules/cl_tools*.lua`, `sv_tools*.lua`, `sh_tools*.lua`)

1. **The physgun** (plan: "Physgun"). The engine's physgun stays the weapon, so prop protection and add-ons' hooks
   (`PhysgunPickup`, `OnPhysgunPickup`, `PhysgunDrop`, `OnPhysgunFreeze`, `OnPhysgunReload`) still decide and hear.
   While it holds a prop: `NLVR.Weapon.ConvergeAt(held distance)` so the prop sits on the gun's line; the prop turns
   with the hand; the main stick's up and down push and pull it (the stick claimed while holding; the mouse wheel in
   the user command, or what measures best); A freezes (W's `IN_ATTACK2`), tap B unfreezes (K's `IN_RELOAD`).
   **Turning with the hand** is the hard part: first measure what the engine's physgun does with the user command
   (it keeps a held prop's angles relative to the view; with use held, mouse movement rotates it about the view's
   axes); if driving it that way cannot follow the hand in yaw, pitch and roll within 5 degrees, hold the prop's
   orientation on our server while the engine's physgun keeps holding it (show that the two do not fight: no
   jitter, the prop settles), or another approach you measure. Decide by numbers and record why. The beam: find
   where the engine starts it for the local player (likely the view model's muzzle) and make it start at the gun in
   the hand.
2. **The toolgun** (plan: "Toolgun"): aimed by the hand through W's convergence; trigger, A and tap B through W's
   and K's buttons; check that the tool chosen on M's spawn menu panel (its tool list) becomes the toolgun's tool.
   The **tool overlay** (`tool`, 643 x 133) beside the gun while the toolgun is out: the tool's name and what
   trigger, A and B do (the tool's own information lines where it has them), painted on change.
3. **The weapon wheel** (plan: "Weapon wheel"): holding the main B 0.3 s opens the `wheel` overlay (1035 x 1037) at
   the hand, facing the head; entries `nlvr_hands` then the player's weapons by slot and slot position, each with its
   selection icon where one exists (SWEPs' `WepSelectIcon`, the HL2 weapons' icons; find how the HUD draws them)
   and its name; the hand's movement in the ring's plane picks an entry (dead zone 3 cm; your layout for many
   weapons, documented); releasing B selects it through the user command; the trigger is claimed while the wheel
   is open; Exit and death close it. A tap of B never opens it.
4. **Debug values** for the probe: the physgun's held entity, its distance, the hand's and the prop's orientation
   and their difference; the toolgun's tool; the wheel's entries, highlighted entry and the selection made.

## Files you may change

`vr/addon/lua/nlvr/modules/cl_tools*.lua`, `sv_tools*.lua`, `sh_tools*.lua` and their `.md`, your tests in
`companion/tests/` (new files with a `vr_tools` prefix) and their bridge in `tools/tests/` as S's report names it,
decision records **0181-0182** (the physgun in VR; the toolgun and the weapon wheel) with their lines in
`docs/decisions/README.md`, and your report. Core, W's, K's, L's, M's or P's code: describe needed changes in your
report, do not make them.

## Proof

- LuaJIT tests: the held distance and convergence, the orientation following (the maths of whichever approach you
  take), stick to distance, the wheel's layout and picking (dead zone, many weapons), tap versus hold, the tool
  overlay's repaint on change.
- Simulated PoC sessions with timelines: pick up a prop with the physgun, turn the hand 90 degrees about each axis
  (the prop's orientation measured on the server after settling), push and pull it (distances measured), freeze and
  unfreeze; choose the remover and the colour tool on the spawn menu panel and apply them where the hand points (the
  pointed prop removed, coloured); open the wheel, pick a weapon, release (the active class measured); a tap of B.
  Captures of the beam at the gun, the tool overlay and the wheel.
- One session on the Index: the overlays as SteamVR shows them, the compositor's counters.

## Report

`docs/handover/VR-V4-T-report.md`: what you built, pictures (paths), the measurements (Done for V4 points 6, 7 and
8), the physgun's approach and why, the tests and evidence, what is open, your text for the shared documents.
`tools\test.ps1 -Config Release` passing in your worktree.
