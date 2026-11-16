# The user's QoL requests of 2026-11-16: report

The brief (the user, 2026-11-16, three items):

1. "Adjust the topbr function, allow user to limit its application range, by default it should only work on map mesh
   and nothing else. Also marks it as an experimental feature in the menu."
2. "In the animation player, add a 3 seconds delay after the animation ends and return to the reference pose."
3. "The physical interaction of the NPC to the world is good, but currently, dancing character's physics interaction
   transfer way too much momentum to the object being interacted. Add an option to allow adjustment of the
   interaction."

Done by Claude on the branch `qol-topbr-scope-dance` (worktree `out\worktrees\qol16`), checked in the PoC. No loader
or runtime change; the RTX fixes' native module has a fourteenth patch.

## 1. ToPBR on the map's own surfaces ([ADR 0229](../decisions/0229-topbr-takes-the-maps-own-surfaces-unless-the-player-widens-it.md))

ToPBR's queue is filled in native code (the material pipeline's worker queues every newly drawn material), so the
range is held there: the fixes' fourteenth patch, [topbr-scope](../../packages/fixes/licenses/oversized-skinning/topbr-scope/README.md),
makes every queue of world conversion ask a range. The player's `rtx_topbr_scope` (read natively) restricts it or
not: 0, the default, the map's own surfaces; 1 the map's surfaces and props; 2 everything ToPBR can convert, as
before. The client driver names the BSP's materials at a map's start (and the props' model materials with 1), and a
narrower range clears the cache. The RTX Remix page is "Map and prop PBR (ToPBR, experimental)", opens with
"Experimental feature.", its switch is "Enable ToPBR (experimental)" and "Apply to" chooses the range; the guide's
line says the same; ten texts and the guide line in six languages.

Checked in the PoC (`out\qol16-poc\a`, gm_construct, three props spawned in view, 25 s per range, the console's
`Processed material` lines between phase markers):

| Range | Names held | What it converted |
|---|---|---|
| 0, the map's own surfaces | 203 | 24 materials, every one the map's (`maps/gm_construct/...` cubemap patches, `gm_construct/...`, `plaster/...`, `brick/...`, `metal/...`) |
| 1, with props | 236 | 11 more: the props' and static props' (`models/props_c17/oil_drum001a`, `models/props_interiors/furniture_chair01a`, `models/props_buildings/...`) |
| 2, everything | (unrestricted) | 12 more: the view models' and Kleiner's (`models/weapons/v_toolgun/toolgun`, `models/weapons/c_arms_citizen/...`, `models/kleiner/...`) |
| 0 again | 203 | the cache cleared, 193 drawn materials queued, the map's 24 converted again and nothing else |

## 2. The end hold ([ADR 0230](../decisions/0230-a-dance-holds-its-last-pose-and-its-bodies-weigh-its-ragdoll.md))

A non-looping dance that reaches its last frame keeps applying it for `MMDVMDNPC.EndHoldSeconds` (3), then stops as
before (start spot, reference pose). A pause during the hold lengthens it; a looping dance never ends. Checked in the
PoC with a test dance whose arms stay out to its last frame: the right hand stood at the same point half a second
before the end and one and two and a half seconds after it; the playback ended 3.03 s after the end and the hand
went 16.1 units back to the reference pose.

## 3. A dancing NPC's push ([ADR 0230](../decisions/0230-a-dance-holds-its-last-pose-and-its-bodies-weigh-its-ragdoll.md))

A dancing NPC's colliders were physics shadows its bones drive and the physics may not move: 50,000 kg to the solver
(`GetMass`), so whatever a limb met was shoved off at the limb's speed and more. Three designs were measured in the
PoC (the server half's test dance swings both arms out in four frames, a dance's speed; props without gravity):

1. **Lighter immovable bodies** (run `a`, a slower swing): no gain. A 10 kg watermelon in the swing and a 1 kg can
   inside the held hand reached 44.6 and 111.6 units/s with the 50,000 kg bodies, 60.6 and 151.9 with the ragdoll's
   masses, 46.2 and 42.0 at 0.1 kg: the shadow controller puts an immovable body on its bone whatever it meets.
2. **Scaling what a hit gave a prop** (runs `b` and `c`): props within reach got a collision callback, and on the
   next tick kept a share of the speed the hit gave them, with the hit's damage scaled the same. The callbacks fire
   (one hit per swing), but a slowed prop is overrun by the limb and launched harder: a 7 kg paint can reached 189.2
   units/s at 100 %, 564.8 at 25 % and 308.2 at 0 %, and a watermelon still broke at 0 % (the damage is done at the
   impact). Dropped.
3. **Bodies the physics may push back** (run `d`, shipped): each collider is a shadow its bone drives that the
   physics may move (`MakePhysicsObjectAShadow(true, true)`, no gravity), weighing the same body of the ragdoll times
   **Push strength of a dancing NPC's body (%)** (100 by default, 0 to 500; the tool's Build & Playback tab, nine
   languages); a `ShouldCollide` rule keeps the bodies off each other and off the map.

Run `d`, the same swing:

| Bodies | Weight | Paint can top speed (units/s) | Distance in 1.6 s | Watermelon | Can inside the hand |
|---|---|---|---|---|---|
| Before (immovable) | 50,000 kg | 1,177.2 | 1,282 | broke | 153.1 |
| 100 % (default) | 0.95-8.51 kg | 207.0 | 287 | whole | 136.1 |
| 25 % | 0.24-2.13 kg | 88.4 | 119 | whole | 120.8 |
| 0 % | 0.1 kg | 35.7 | 48 | whole | 42.1 |

The bodies stayed on their bones (largest gap 0) and still stopped traces through the hands and a player-sized hull
into the head; a hull into the box's empty corner passed, as before.

## Files

- `packages/fixes/licenses/oversized-skinning/topbr-scope/` (the patch, its complete files, the regression, README);
  `tools/ci/pins.json` (the fourteenth patch, the patched tree `b07547bc...`); the module
  `packages/fixes/modules/gmcl_RTXFixesBinary_win64.dll` (5,607,424 bytes, SHA-256 `e885543d...`, built with
  `build_modules.ps1 -Only fixes` under a `subst` alias; the PoC runs used the same code built before the decision
  records were renumbered, `93823af4...`, which differs only in the comments' ADR number);
  `cl_rtx_topbr_conversion.lua`, `cl_rtx_settings.lua`,
  `cl_material_pipeline.lua`; the part's README and `files.json`.
- `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua` (the hold, the push),
  `sh_core.lua` (the slider's two texts in nine languages), `lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua` (the
  setting and slider); the part's `files.json`.
- `companion/nativeloader/lua/nativeloader/guide_pages.lua` and the catalogs in `companion/i18n` and
  `companion/i18n/addons`.
- Tests: [test_topbr_scope.py](../../tools/tests/test_topbr_scope.py.md) (new), the ToPBR driver and settings
  harnesses ([topbr_harness.lua](../../tools/tests/topbr_harness.lua.md),
  [rtx_settings_harness.lua](../../tools/tests/rtx_settings_harness.lua.md)), the motion server harness's
  `ragdoll_collision` and new `end_hold` scenarios ([test_motion_server.py](../../tools/tests/test_motion_server.py.md)),
  [test_eye_texgen.py](../../tools/tests/test_eye_texgen.py.md) (the patch order).
- QA: [mmd_player_session.py](../../tools/qa/mmd_player_session.py.md) `--qol` with its client and server halves.
- Docs: ADR 0229 and 0230 and their rows, CHANGELOG, ROADMAP, RESEARCH, TESTING, this report and its line in the
  handover index, AGENTS.md.

## Not done, and limits

- Not checked in the field install itself (rule 1).
- The old immovable bodies are not a setting any more (500 % is five times the ragdoll's weight). A body pressed by a
  prop much heavier than itself gives way and passes into it while the controller brings it back to its bone.
- The PoC runs used an empty motion library (the server half writes its own test dance) and the imported character
  the PoC's library holds; the ToPBR check ran on gm_construct only.
- Imported game PBR for imported characters (`rtx_topbr_game_maps`) is a separate feature and unchanged.

## The gate

`tools\test.ps1 -Config Release` on the branch (rebased on `main` `0231259e`): "All checks passed" (repo conventions
OK; C++ 35 of 35; Python 2,024 tests in `tools`, 1 skipped, 29 in `gmapack`, 26 in `steam`). Two earlier runs failed only
in `nl_client_catalog_tests`, at a different check each time (`test_leftovers.cpp:170`, `test_former_rtx.cpp:314`):
both count a `gmod.exe` that cannot be opened as another game, so a process ending during the snapshot (another
session's game or test host) fails them; the test passed alone and in the third run. Loader code is unchanged here.

## Published

`main` was fast-forwarded to `0cc79d27` (the branch's one commit) and pushed (`0231259e..0cc79d27`, one LFS object,
the fixes module, 1.1 MB). The merge's hook built the package from `packages/` and uploaded item 3829070317 as
**0.0.0-dev.20261116091301+f38cbcc6** (2,205,859,273 bytes, SHA-256
`4cc280f958db7911649eef11ec0089acdb0f814ddaabcae141a9cccfe2c11eea`, content digest `8d230b6f...`; Steam sent 19.7 MB
of changed content) at 2026-11-16 02:13 UTC, its change note the changelog's entry; the push's hook found the inputs
unchanged. Not yet seen in the field: a running game keeps the previous fixes module until it restarts.
