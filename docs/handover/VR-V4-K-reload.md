# VR-V4-K: reloading and ammo on the gun

Read [VR-V4-plan.md](VR-V4-plan.md) first, all of it, then [VR-V2V3-plan.md](VR-V2V3-plan.md) and the reports of
tasks F, H, P and S in `docs/handover/` (`VR-V2-F-report.md`, `VR-V2-H-report.md`, `VR-V3-P-report.md`,
`VR-V4-S-report.md`), and W's `VR-V4-W-report.md` and Q's `VR-V2V3-Q-report.md` when they exist. The plan's
section "Weapons and tools" in [VR-plan.md](VR-plan.md) describes what the player should get: "Physical reload for
the HL2 weapons: eject with A, take ammo from over the shoulder, put it into the gun's magazine well (shotgun shells
one by one, the crossbow's bolt, the RPG's rocket); every other weapon reloads on tap B", and "Ammo on the gun".

Your branch is `v4k`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4k`. Task W builds the
gun in the hand (`NLVR.Weapon`, plan section 3) in parallel: until W is merged into `vr2`, test offline against your
own stand-in of `NLVR.Weapon`; when Claude has merged W into `vr2`, merge `vr2` into your branch for PoC runs. Your
points on the gun (the magazine well, the eject port, the shell port, the overlay's place) are in the gun model's
local frame, from your own data, so W's placement can change without breaking them.

## What to build (`modules/cl_reload*.lua`, `sv_reload*.lua`, `sh_reload*.lua`)

1. **Holding the engine's reload off** (plan: "Physical reload"): on our server, in `StartCommand`, for a VR
   player's HL2 gun under `nl_vr_physical_reload`: drop the reload button; while the clip is empty or ejected, hold
   the next primary fire far in the future (and only the primary). Show per weapon (pistol, .357, SMG1, AR2,
   shotgun, crossbow, RPG) that for 5 seconds with an empty clip and reserve ammo nothing fires, the engine's reload
   never starts and the game does not switch weapons; record in your report how HL2's automatic reload and empty
   switch work and why the hold stops them. The shotgun's and the crossbow's own states (pump, `m_bMustReload` and
   the like) must stay consistent: a gun reloaded your way fires and cycles as after a normal reload.
2. **Eject** (main A, claimed for weapons with an ejectable magazine: pistol, .357, SMG1, AR2): a tap ejects (the
   rounds left go back to the reserve on the server, clip 0), a magazine model drops from the eject port as a
   client-side physics model for 10 seconds; a hold of 0.3 s presses `IN_ATTACK2` instead (the SMG1's grenade, the
   AR2's orb).
3. **Ammo from over the shoulder**: the off hand gripping in a zone behind the head (your measured zone, either
   shoulder) takes the ammo of the active gun (a magazine, a shell, a bolt, a rocket: base-game models, plan) when the
   reserve has any; the off hand's grip is claimed while it is in the zone or holding ammo, so P does not grab;
   letting go away from the gun drops it (gone).
4. **Insertion**: the held ammo within 6 cm of the gun's port (and roughly aligned, your tolerance) goes in: the
   client sends the insertion, the server checks it against its own hand poses (the off hand near the port computed
   from the main hand's server pose, with a tolerance for latency), the weapon is still active, the reserve has
   rounds; then `SetClip1` (the smaller of clip size and reserve plus what is in the clip; the shotgun +1; the
   crossbow 1; the RPG releases the hold) and `RemoveAmmo`, the next primary fire released, the weapon's reload sound
   on the gun. Haptics on the off hand.
5. **The button reload** (main B, tap): `IN_RELOAD` for one tick in your mover for every weapon without physical
   reload (all of them while `nl_vr_physical_reload` is off; the toolgun's reload and the physgun's unfreeze too).
   Never on a hold (T's wheel).
6. **Ammo on the gun** (`nl_vr_ammo_counter`): the `ammo` overlay (387 x 129) attached to the weapon hand's device,
   placed beside the gun (your offset), showing clip / reserve and the secondary reserve, painted only when they
   change, hidden for weapons without ammo and while the wheel is open.
7. **Debug values** for the probe: the weapon's physical-reload state, clip, reserve, the hold's time, the zone
   check, what the off hand holds, the last insertion (accepted or why refused).

## Files you may change

`vr/addon/lua/nlvr/modules/cl_reload*.lua`, `sv_reload*.lua`, `sh_reload*.lua` and their `.md`, your tests in
`companion/tests/` (new files with a `vr_reload` prefix) and their bridge in `tools/tests/` as S's report names it,
decision records **0179-0180** (holding the engine's reload; the physical reload's gestures and checks) with their
lines in `docs/decisions/README.md`, and your report. Core, W's, H's or P's code: describe needed changes in your
report, do not make them.

## Proof

- LuaJIT tests: the hold and its release, eject and the reserve, the zone, insertion checks (accepted, too far,
  wrong weapon, empty reserve, stale), clip arithmetic per weapon, tap versus hold, the counter's repaint on change.
- Simulated PoC sessions with timelines for each HL2 gun: fire, eject, wait 5 s, take ammo, insert, fire again
  (clip and reserve measured on the server at each step; captures of the magazine in the hand and at the well); the
  shotgun shell by shell; the crossbow and the RPG; physical reload off with tap B; a SWEP's reload on tap B; an
  empty reserve.
- One session on the Index: the counter overlay as SteamVR shows it, the compositor's counters.

## Report

`docs/handover/VR-V4-K-report.md`: what you built, pictures (paths), the measurements (Done for V4 points 4 and 5),
how the engine's reload is held and why, the tests and evidence, what is open, your text for the shared documents.
`tools\test.ps1 -Config Release` passing in your worktree.
