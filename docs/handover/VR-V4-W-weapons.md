# VR-V4-W: weapons in the hand

Read [VR-V4-plan.md](VR-V4-plan.md) first, all of it, then [VR-V2V3-plan.md](VR-V2V3-plan.md) and the reports of
tasks F, H, P and S in `docs/handover/` (`VR-V2-F-report.md`, `VR-V2-H-report.md`, `VR-V3-P-report.md`,
`VR-V4-S-report.md`), and Q's `VR-V2V3-Q-report.md` when it exists. You build on F's core, H's hands and P's server
hands. The plan's section "Weapons and tools" in [VR-plan.md](VR-plan.md) describes what the player should get.

Your branch is `v4w`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4w`. Tasks K
(reloading) and T (tools) build on your `NLVR.Weapon` in parallel: keep its interface exactly as the plan's section
3 says, commit it early (even before the models look right), and say in your report what K and T can rely on.

## What to build (`modules/cl_weapons*.lua`, `sv_weapons*.lua`, `sh_weapons*.lua`)

1. **The gun in the hand.** The active weapon's world model at the main hand's shown pose (plan: "The gun in the
   hand"), drawn as world geometry in the hands' stage, the hand's fingers around the grip (`grip_curls`, index
   finger on the trigger), `nl_vr_gun_angle` applied. Calibrate each HL2 weapon, the physgun, the toolgun and the
   camera by captures; a rule for SWEPs (the world model's hand bone; a SWEP's own `DrawWorldModel` where it draws at
   our pose). A short visual kick of the model when it fires. Models follow weapon switches, the dominant hand and
   the player's death; Exit removes them.
2. **`NLVR.Weapon`** (plan section 3), the events, `ConvergeAt`, and `NLVR_SV.Weapon(ply)` on the server.
3. **Firing.** The main trigger presses `IN_ATTACK` in your mover while armed; A presses `IN_ATTACK2` unless K
   claims it; the main grip and trigger are claimed while armed, so P's grab stays on the off hand.
4. **Aim convergence** through `NLVR.Aim` every tick a weapon is out (from the engine's eye to the gun ray's first
   hit, ignoring the player, the hands and what the physgun holds; `ConvergeAt` overrides the distance).
5. **Shots from the muzzle on our server.** `EntityFireBullets` for the VR player's active weapon: `Src` at the
   muzzle from the server's own hand pose (P's stopped hand, the client's reported muzzle offset relative to the hand
   when the weapon or grip changes), `Dir` along the gun (one or two hands), spread kept; a trace from the eye to the
   muzzle so no shot starts beyond a wall (start at the eye's side of the wall instead). The HL2 projectiles (rocket,
   bolt, SMG grenade, AR2 orb) moved to the muzzle along the gun on the tick they appear. Tracers and a muzzle flash
   (with its light) at the gun in the hand, not in front of the face: find how the engine places first-person tracers
   (it uses the view model's attachment for the local player) and record it in your report.
6. **No punch on the head.** Show that a weapon's view punch moves neither the camera nor the aim; the model kicks.
7. **`nlvr_hands`** (plan: "The hands weapon"): registered at Start in both realms, given on our server at Start and
   after each spawn, selected first at Start only if the player held nothing; stripped at Stop with the previous
   weapon selected again.
8. **Foregrip** (plan: "Foregrip", `nl_vr_foregrip`): per-weapon points, the two-hand aim line, the off hand's
   shown pose snapped to the foregrip with its fingers closed (your resolver, after P's), the off trigger on the
   foregrip pressing `IN_ATTACK2`.
9. **Melee weapons** (plan: "Melee weapons", with P's melee path; read how P scales damage and reuse it, do not fork
   it): the crowbar's and the stunstick's heads hit by swinging, with their sounds and impact effects.
10. **The frag grenade** (plan: "The frag grenade"): on our server the thrown grenade starts at the hand with the
    hand's throw velocity (P's averaging over the history); the bug bait the same way.
11. **Debug values** for the probe: the active class and kind, the model and its pose, the muzzle, the converged aim
    point, the last shot's server `Src`, `Dir` and hit position, the foregrip state.

## Files you may change

`vr/addon/lua/nlvr/modules/cl_weapons*.lua`, `sv_weapons*.lua`, `sh_weapons*.lua` and their `.md`, your tests in
`companion/tests/` (new files with a `vr_weapons` prefix) and their bridge in `tools/tests/` as S's report names it,
decision records **0176-0178** (the gun in the hand; shots and aim; the hands weapon, foregrip, melee and grenade)
with their lines in `docs/decisions/README.md`, and your report. If F's, H's or P's code needs a change, do not make
it: describe it in your report (Q makes those changes) and work around it meanwhile.

## Proof

- LuaJIT tests: kinds, grip placement maths, convergence (eye, muzzle, hit point), the two-hand line, the server's
  `Src` and `Dir` (including the wall case), projectile redirection, `nlvr_hands` lifecycle, claims, throw velocity.
- Simulated PoC sessions with timelines: each weapon held in turn (captures of every one in the hand), the head
  turned 45 degrees away while firing at a wall at 5 m and 20 m (impact positions measured against the gun's ray),
  the hand pushed into a wall while firing, a foregrip hold, crowbar swings fast and slow at a breakable, a grenade
  throw, a switch to Hands and a grab with the main hand, a death and respawn, Exit.
- One session on the Index (both locks) with the same timeline: the compositor's counters, the eye captures.

## Report

`docs/handover/VR-V4-W-report.md`: what you built, pictures (paths) of each item, the measurements (Done for V4
points 1, 2, 3, 9, 10, 11 and 12), the tests and evidence, what K and T can rely on, what is open, your text for the
shared documents. `tools\test.ps1 -Config Release` passing in your worktree.
