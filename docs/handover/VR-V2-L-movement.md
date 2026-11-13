# VR-V2-L: movement and comfort

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it, then task F's report
`docs/handover/VR-V2-F-report.md` ("how to write a module"): you build on F's framework (the play space, the
client and server movers, the input mapping). [VR-plan.md](VR-plan.md)'s "Movement and comfort" is what the player
should get.

Your branch is `v2l`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2l`.

## What to build (`modules/cl_move.lua`, `modules/sv_move.lua`, and `cl_move_*` / `sv_move_*` files)

1. **Following the head.** When the person walks in the room, the player follows: the player's position stays under
   the head (within a few centimetres) through ordinary movement, so walls, steps and doors stop and lift the player
   as for any player; when the player is stopped (a wall), the view must not go through it (fade it, or shift the
   play space back, or both: your choice, documented). This is the hardest part: get it right before the rest.
2. **Smooth movement** on the off hand's stick, in the direction of that hand or of the head (`nl_vr_move_dir`), at
   walking speed, sprint on the off hand's stick click; jump on the off hand's A.
3. **Turning**: snap turn on the main hand's stick (`nl_vr_snap_angle`), smooth turning as an option
   (`nl_vr_turn`, `nl_vr_turn_speed`), always about the head (its world position unchanged). The mouse's yaw also
   turns the play space, for people at the desk.
4. **Teleport** (`nl_vr_teleport`): hold the main stick up for an arc from the main hand (a ballistic arc that
   stops at what it hits), shown with overlays (a few points along it and a ring at the target; green when the player
   can stand there, red otherwise); release to go. Blink: a short fade (the vignette overlay at full) and the move;
   shift: a quick dash (about 0.15 s). The server checks the target (the player's hull fits, the floor is standable,
   within range, not through a wall) and refuses otherwise. A target on a ledge the player cannot step onto mantles
   onto it when the hull fits there.
5. **Crouching**: physical (the head below a share of the calibrated height crouches the player, with hysteresis) and
   a toggle on the main stick down.
6. **Noclip flight** when the player is noclipping (the engine's own noclip state; never grant noclip): the off
   hand's direction, speed from its trigger.
7. **Height and seating**: height calibration (a button on the page or in the wrist menu, task M places it: stand
   straight, measure the head, set `nl_vr_height`, and from it the scale so the player's eyes are at their eye height
   in the game); seated mode raising the view by `nl_vr_seated_offset`.
8. **The vignette** (`nl_vr_vignette`): a head-locked overlay whose strength follows movement and turning speed.
9. **Debug values** for the probe: positions, the play space, the last teleport's target and result, crouch state.

## Files you may change

`vr/addon/lua/nlvr/modules/cl_move*.lua`, `sv_move*.lua` and their `.md`, your tests in `companion/tests/` (new
files with a `vr_move` prefix), decision records **0165** (the player follows the head) and **0166** (teleport and
comfort) with their lines in `docs/decisions/README.md`, and your report. If F's core needs a change, do not make it:
describe it in your report and work around it in your module meanwhile.

## Proof

- LuaJIT tests: the arc, teleport target rules, snap and smooth turns about the head, the follow logic, crouch
  hysteresis, calibration maths, vignette strength.
- Simulated PoC sessions (task N's `--simulate`, once on `vr2`; until then the Index with both locks), on gm_construct
  with scripted head, hands and sticks: every item of "Done for V2", point 3 and 4, with the probe's numbers (distances,
  angles, positions) and eye captures where a picture shows it (the arc, the vignette, the fade).
- One session on the Index: a timeline with walking, turning and a teleport; the compositor's counters.

## Report

`docs/handover/VR-V2-L-report.md`: what you built, the numbers of each test, the tests and evidence, what is open,
your text for the shared documents. `tools\test.ps1 -Config Release` passing in your worktree.
