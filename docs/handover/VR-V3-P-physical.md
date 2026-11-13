# VR-V3-P: physical interaction (milestone V3)

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it, then task F's report
`docs/handover/VR-V2-F-report.md` ("how to write a module"): you build on F's framework (the server core, the
sync with its hand history, server movers, the hand resolver chain, module messages). [VR-plan.md](VR-plan.md)'s
"Hands" and "Holding things" are what the player should get, Half-Life: Alyx-like, adjusted for the sandbox. gVRMod's
`physics/`, `pickup/`, `input/sh_climbing.lua` and `combat/` in `out\vr-plan\src` (main checkout) show one way to do
it: read them for behaviour only, copy nothing.

Your branch is `v3p`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v3p`.

## What to build (`modules/sv_interact.lua`, `modules/cl_interact.lua`, and `sv_interact_*` / `cl_interact_*`)

1. **Physical hands.** On the server, a physics proxy per hand (not networked, invisible) that follows the
   controller by velocity: it pushes props and ragdolls, stops at walls, never collides with its own player. Living
   NPCs are pushed (their velocity), not grabbed. The proxies' positions go back to the client as a resolver in F's
   chain, after task H's client-side stop: the hand is drawn where its proxy is. Floor and ceiling never stop a hand
   that holds a climbing grip.
2. **Grab and throw.** Grip takes the nearest prop within reach at the touched point (closest point of its hull, not
   its origin); it follows the hand physically, so a heavy prop lags and nothing passes through a wall; it does not
   push its own player. Letting go throws with the hand's velocity and spin averaged over the last frames of the
   server's history. Two hands on one prop hold it along the line between them. Respect what other add-ons allow
   (decide which hook a sandbox prop-protection add-on answers for a pickup, and document it).
3. **The grab API** (V4's weapons and your gloves use it): `NLVR_SV.Grab(ply, hand, ent, bone, localPos, localAng)`,
   `NLVR_SV.Release(ply, hand, throw)`, `NLVR_SV.Holding(ply, hand) -> ent, bone`; events `grab` and `release` to
   the client (task H closes the fingers: set `NLVR.Hand[hand].held` and a grip pose).
4. **Ragdolls.** Grip takes the nearest physics bone; one or two hands drag and pose; NPCs' death ragdolls too (if
   that needs server ragdolls, set what is needed for the session only and put it back at Exit).
5. **Use by hand.** Touching or gripping a usable entity (buttons, doors, levers, the sandbox's buttons) uses it; ammo,
   health and armour kits are taken by grabbing them. No use key needed.
6. **Gravity gloves** (`nl_vr_gloves`). Point at a loose prop within range (about 6 m): it is marked (an overlay marker
   at it, no `halo`); hold grip; flick the hand toward the body: it flies to the hand on an arc that arrives at the
   hand; grip still held catches it (a grab). Without a catch it falls.
7. **Climbing** (`nl_vr_climb`). Grip on world geometry within reach of the hand (a ledge, a wall's edge, a ladder)
   holds the player there: a server mover moves the player so the gripping hand stays on its point, without gravity;
   two hands alternate; letting go of both falls, keeping the last velocity.
8. **Melee** (`nl_vr_melee`). A hand (or what it holds) hitting something faster than a threshold damages it (club
   damage, scaled by speed) and pushes it; a melon breaks, an NPC is hurt.
9. **Haptics** on contact, grab, release, a catch and a hit (short pulses, stronger for harder).
10. **Clean ends.** Everything held is released and every proxy removed at Exit, when the player dies (VR goes on),
    when the server part unloads; no prop is left without collisions or with a changed owner.
11. **Debug values** for the probe: per hand the proxy's position, what is held, the last throw's velocity, climbing
    state, the gloves' target.

## Files you may change

`vr/addon/lua/nlvr/modules/sv_interact*.lua`, `cl_interact*.lua` and their `.md`, your tests in `companion/tests/`
(new files with a `vr_interact` prefix), decision records **0169** (physical hands: server proxies and grabbing),
**0170** (gravity gloves and climbing) and **0171** (use by hand and melee) with their lines in
`docs/decisions/README.md`, and your report. If F's core needs a change, do not make it: describe it in your report
and work around it in your module meanwhile.

## Proof

- LuaJIT tests: reach and nearest point, throw velocity from a history, two-hand orientation, the flick detector, the
  gloves' arc (arrives at the hand), climbing's mover maths, melee damage scaling, release on death and Exit.
- Simulated PoC sessions (task N's `--simulate`, once on `vr2`; until then the Index with both locks) on gm_construct
  with fixtures the probe spawns at known places relative to the scripted hands (a barrel, a long plank, a heavy
  crate, a ragdoll, an NPC, a melon, a sandbox button, a ledge): every item of "Done for V3" with numbers (positions
  before and after, the release velocity against the scripted hand's, health before and after) and eye captures.
- One session on the Index: grab, throw and a gloves pull, with the compositor's counters.

## Report

`docs/handover/VR-V3-P-report.md`: what you built, the numbers of each test, the tests and evidence, what is open,
your text for the shared documents. `tools\test.ps1 -Config Release` passing in your worktree.
