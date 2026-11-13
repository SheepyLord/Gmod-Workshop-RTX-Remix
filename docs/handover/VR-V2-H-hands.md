# VR-V2-H: hands

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it, then task F's report
`docs/handover/VR-V2-F-report.md` ("how to write a module"): you build on F's framework. The plan's sections
"Hands" and "Holding things" in [VR-plan.md](VR-plan.md) describe what the player should get.

Your branch is `v2h`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2h`.

## What to build (`modules/cl_hands.lua`, and `cl_hands_*.lua` if you split it)

1. **The models.** Both hands from the local player's model (`player_manager.TranslatePlayerHands`: model, skin,
   bodygroups; the default hands when it has none), as client-side world models (never the view-model pass, which the
   session suppresses), placed at `NLVR.Hand[hand].shown`. One model per hand or one shared, as works best: only the
   hand and forearm show; nothing of the arms above the forearm is drawn. They follow a changed player model.
2. **The fingers.** Each finger's joints from the curls (and splay when task N supplies it), smoothed a little so a
   tracked hand does not shiver; a grip pose (`NLVR.Hand[hand].grip_curls`) overrides them when something is held.
   Find the bones by name across the HL2 and GMod hands (`ValveBiped.Bip01_L_Finger0` ...), and fall back gracefully
   when a model lacks some.
3. **The dominant hand** (`nl_vr_dominant`) changes nothing in the models (left is left), only what F's mapping
   does; check that both work.
4. **Ghost hands.** Your resolver in F's chain: a hand that would be inside the world is stopped at the surface (a
   swept hull from the shoulder or the head to the controller; your choice, documented), `blocked` set, and the model
   drawn where it stopped. With `nl_vr_ghost_hands` on, an overlay outline of the hand (a silhouette painted once
   into an RT) shows at the real controller while it is blocked, faint. Task P will add the server proxies'
   positions as a later resolver; yours stays as the client's fallback.
5. **Under RTX.** The hands are path traced (shadows, reflections). Check that they light like the world and that
   nothing of them reaches the desktop mirror's 2D. Hands come close to the eyes: task R brings the warp's near
   limit to 0.2 m; with the runtime of `vr2` at the time, record how hands at 0.2, 0.3 and 0.5 m look in both eyes.
6. **Debug values** for the probe: each hand's bone count found, curls applied, shown vs target distance, blocked.

## Files you may change

`vr/addon/lua/nlvr/modules/cl_hands*.lua` and their `.md`, your tests in `companion/tests/` (new files with a
`vr_hands` prefix), decision record **0164** (the hands: models, fingers, ghost hands) with its line in
`docs/decisions/README.md`, and your report. If F's core needs a change, do not make it: describe it in your report
(Q makes core changes at integration), and work around it in your module meanwhile.

## Proof

- LuaJIT tests: bone lookup on a stand-in skeleton, curls to angles, smoothing, the grip override, the resolver
  (stopped at a surface, outline shown only while blocked).
- Simulated PoC sessions (task N's `--simulate`, once on `vr2`; until then the Index with both locks) with a
  timeline that moves both hands, curls the fingers one by one, and pushes the right hand into a wall: eye captures
  showing the hands, the fingers bending, the hand at the wall with the outline overlay; the probe's debug values.
- One session on the Index: the same timeline, the compositor's counters (nothing refused or unmatched).

## Report

`docs/handover/VR-V2-H-report.md`: what you built, pictures (paths) of each item, the tests and evidence, what is
open, your text for the shared documents. `tools\test.ps1 -Config Release` passing in your worktree.
