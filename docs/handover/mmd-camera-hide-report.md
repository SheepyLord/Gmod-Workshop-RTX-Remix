# Hide yourself during camera motion (report)

Claude, 2026-11-21, on the branch `mmd-camera-hide-player` (worktree `out\worktrees\mcam`, from `main` at `14b0accd`).
Package only: the character motion importer part (the Advanced MMD Animation Player) and one file of the RTX fixes
part; no loader (`winmm.dll`), runtime or native change. Decision:
[ADR 0250](../decisions/0250-hide-yourself-during-camera-motion.md). Nothing committed, pushed, merged or published.

## The task

The user, 2026-11-21: "In the advanced mmd player, camera section, add a convenience function, default on, when in
camera motion, hide the player in the world." The main thread's brief: a checkbox in the camera section, on by default
and saved; while a camera motion plays, hide the local player's body, what they hold and anything else of theirs that
shows in the shot (shadow, flashlight), including whatever the RTX fixes or the companion draw for the local body; the
player back when the camera motion ends, is stopped, cancelled or fails, at a map change and when the option is
unticked; client-side only, said in the help; the texts in every language of the panel; unit tests, a PoC run with
screenshots, the gate, the docs.

## What draws you under a camera motion

The add-on deploys only in RTX starts (`--requires-remix`). Facts with file and line references:
[RESEARCH](../RESEARCH.md), "What draws the local player under a camera motion".

- **The engine**: the camera path's view returns `drawviewer = true`, so the game draws you and your active weapon as in
  third person. Under Remix your shadow and reflections are that same geometry.
- **The Model Hotloader**, for an imported character as your player model: a separate clientside entity
  (`mmdhl_native_visual`) draws it, and skips the draw while you are no-draw. Its `PreRender` bookkeeping releases a
  character that stays locally hidden for five seconds (and rebuilds it when it shows).
- **The RTX fixes**: `rtx_pseudoplayer` and `rtx_pseudoweapon`, copies of your body and weapon for first-person shadows
  and reflections. They hide themselves while `ShouldDrawLocalPlayer()` is true, which the camera's view makes it.
- **The RTX flashlight**: a Remix light at your eyes, lit wherever the view is. Not geometry: hiding the body leaves it.
- The companion draws no body of yours (its model layers only sort materials; its tool gun screen draws on the view
  model in first person).

## What changed

- **The option**: `mmd_vmd_npc_cam_hide_player`, default 1, saved; a checkbox in the tool's Camera tab under "Enter
  camera animation automatically": **Hide yourself during camera motion**, with the help "While an imported camera
  animation drives the view, you are left out of the shot: your body, what you hold and wear, your shadow and
  reflections, and your flashlight's light. You are back as soon as it ends or you untick this. On by default. On your
  screen only: in multiplayer, other players still see you." In the panel's nine languages (en, zh, zh-tw, ja, ko, fr,
  ru, ar, es; the translations are mine and await a person's review).
- **`cl_camera.lua`**: when its `CalcView` returns the camera's view (the camera motion, or the debug window's camera
  preview unless that orbits you), it notes the frame. Its `RenderScene` hook then sets no-draw on you, every entity
  parented to you (carried weapons, worn models, the fixes' weapon copy, to four levels), your active weapon, a death
  ragdoll and the fixes' body and weapon copies (looked up once a second), never the camera's dancer; its `PostRender`
  hook clears every flag it set. An entity already no-draw is left as it is. A frame whose `PostRender` does not come is
  undone by the next `Think`; `ShutDown` undoes too. The camera's view keeps `drawviewer`.
- **The RTX fixes' flashlight** (`cl_remix_flashlight.lua`): the hook `RTXFlashlightHidden(ply)`; a listener answering
  true keeps that light on but dark (radiance and haze 0, no measuring) and it comes back as it was. The motion
  importer answers for you while its camera hides you.

Why the frame-by-frame no-draw and not something simpler (ADR 0250's Rejected): `drawviewer = false` brings back the
fixes' copies and other add-ons' first-person legs; `PrePlayerDraw` leaves the weapon, attachments and the Hotloader's
visual proxy drawn; hiding in `CalcView` or `PreRender` lets the Hotloader see the hide and release your character;
keeping the flag set for the whole motion fights the server's networked value.

## Tests

- **Unit** ([test_motion_camera.py](../../tools/tests/test_motion_camera.py.md), new, 7 tests;
  [test_flashlight.py](../../tools/tests/test_flashlight.py.md), one new): pass on the branch, and the harness tests
  fail on `main`'s files (the option missing; the flashlight lit while hidden).
- **The gate**: `tools\test.ps1 -Config Release` in the worktree with `NL_FIXES_CLONE` set: exit 0, conventions OK, CTest
  35/35, Python 29, 26 and 2,178 tests (one skip each), "All checks passed". A first run failed one C++ check,
  `nl_client_catalog_tests` at `test_former_rtx.cpp(314)` (`another_game_running`: a game process seen mid-gate, the
  known flake); the rerun passed unchanged.
- **PoC** (`tools\qa\mmd_player_session.py --camera --no-steps`, RTX on, the package's add-ons, gm_construct, 1600x900,
  holding `out\r10\poc.lock`; the branch's package `0.0.0-dev.20261121092444+412a014d`, content digest
  `29ae2dce51bba018`; the PoC restored afterwards). Two NPCs of the PoC library's imported character, a four-second test
  dance with a still camera beside the first one that holds the dancer, you (with the tool gun) and the second NPC;
  your RTX flashlight on at brightness 20000 (put back to the PoC's 5 afterwards) aimed at the dancer; the time of day
  held at 15:00 (put back). The evidence is in the worktree's `out\mcam\poc-run<N>\` (`camera\results\camera.json`,
  `poc\camera\shot-*.png`, `poc\camera\console.log`):
  - run 1: the screenshots covered by the first-run RTX Remix guide, and the in-scene sampler counted nothing (it
    skipped skybox calls; `PostDrawOpaqueRenderables` comes with `bDrawingSkybox` true in these sessions); its
    flashlight and Hotloader numbers match run 2's;
  - **run 2, the result** (`--camera`): the guide closed, sampled from the add-on's own `RenderScene` and `PostRender`;
  - run 3 (`--camera --copies`): the RTX fixes' body and weapon copies on ("Local player shadow");
  - run 4 (`--camera --copies --hide-off`): a control, the option off for the whole run.

Run 2, per phase: frames sampled; in how many you and your active weapon were no-draw right after the hide
(`RenderScene`), still at `PostRender`, after the restore and between frames (`Think`); your flashlight's radiance.

| Phase | Frames | Hidden at `RenderScene` / `PostRender` | After restore / between frames | Flashlight radiance |
|---|---|---|---|---|
| First person | 93 | 0 / 0 | 0 / 0 | 5,058 |
| Camera motion, option on (default) | 212 | 212 / 212 | 0 / 0 | 0 |
| Unticked mid-motion | 215 | 0 / 0 | 0 / 0 | 6,333-6,653 |
| Ticked again | 161 | 161 / 161 | 0 / 0 | 0 |
| After the server's stop | 158 | 0 | 0 | 5,058 |
| Before / after the camera toggle (`mmdvmd_camera_toggle`) | 102 / 152 | 102 / 0 | 0 / 0 | 0 / 6,335-6,637 |
| Played once / after its end (5.5 s after the sample, with the 3 s end hold) | 109 / 158 | 109 / 0 | 0 / 0 | 0 / 5,058 |
| Imported character as your model: hidden, 6 s later, unticked | 217, 113, 125 | 217, 113, 0 | 0 | 0, 0, 6,520-6,653 |
| Before / after its dancer was removed (the camera fails) | 106 / 190 | 106 / 0 | 0 / 0 | 0 / 6,664 |

- Through every camera frame `ShouldDrawLocalPlayer()` stayed true (`drawviewer` kept) and the frame's scene hooks all
  saw you no-draw; outside camera frames nothing of yours was ever no-draw.
- Your imported character kept its Model Hotloader instance (3) from first person through the samples taken 2.5-4.5 s
  and about 12 s into the hiding, unticked and after the removal: the hide never reached the Hotloader's five-second
  release.
- Run 3: the fixes' body copy no-draw in every camera frame (its own rule, as in third person) and the weapon copy hidden
  by the change in every camera frame (283 of 283; unticked it draws, a second weapon model in your hand); both drawn
  again in first person after each stop, toggle, end and removal. Run 4 (the control): nothing hidden by the change, your
  flashlight lit throughout, you visible in every shot.

Screenshots, the same still camera beside the dancer, 1600x900 (`out\mcam\poc-run2\poc\camera\`):

| Shot | What it shows |
|---|---|
| `shot-01-camera_hidden.png` | The two dancers only: no body, tool gun, shadow or flashlight light of yours |
| `shot-02-camera_unticked.png` | Unticked mid-motion: you on the right with the tool gun, your flashlight's beam (brightness 20000) flooding the ground |
| `shot-03-after_stop_same_view.png` | After the stop, the camera's last view drawn in third person: you, the gun and the light are back (the HUD too) |
| `shot-04-mmd_camera_hidden.png` | An imported character as your player model, hidden: the dancers only |
| `shot-05-mmd_camera_unticked.png` | The same, unticked: you as the imported character with the tool gun |

Two things seen only with the fixes' copies on (runs 3 and 4, the control included, so not this change), for a
possible follow-up: every frame after `rtx_pseudoplayer`/`rtx_pseudoweapon` were switched on mid-session rendered
without path tracing (flat light, the flashlight invisible though lit), and the Model Hotloader's server scene capture
logged `secondary_collision.lua:111: attempt to compare nil with number` (43 times in run 3, 34 in run 4, from the phase
after the stop on): `ent:GetModelScale()` returned nil for some entity (ADR 0245's `undrawn`). Runs 1 and 2, copies off,
had neither.

## Notes and open questions

1. The translations of the two new texts (eight languages) are mine and await a person's review.
2. Not hidden: what another add-on draws for you by its own hooks without parenting it to you (a PAC3 outfit drawn
   apart, for example) and what is physics rather than drawing (RTX water's ripples around you, footsteps).
3. Not checked in the field install itself (rule 1), nor in a multiplayer game: other players keep seeing you by
   construction, since nothing is sent to the server.
4. In VR the camera motion does not drive the view (VR owns `CalcView`), so nothing is hidden there.
5. Possible follow-ups, not this change (seen with the fixes' copies on, the control run included, above): frames
   without path tracing after "Local player shadow" is switched on mid-session in the PoC, and the Model Hotloader's
   server scene capture erroring on an entity whose `GetModelScale()` is nil (`secondary_collision.lua:111`).
6. For the main thread: the merge's shared docs are additive (CHANGELOG top, ROADMAP paragraph after the map sky's,
   the end of RESEARCH and TESTING, the decisions index after 0249, the handover index after map-sky's line); the
   AGENTS.md status line and "latest is" chain are left to you. Both parts' `files.json` were re-indexed by
   `inputs.py import` (text only, no LFS object), their new origins naming `<repo>`.
