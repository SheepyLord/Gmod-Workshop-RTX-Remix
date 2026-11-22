# Local player shadow's weapon copy and the scene capture (report)

Claude, 2026-11-21, on the branch `local-shadow-fixes` (worktree `out\worktrees\mcam`, from `mmd-camera-hide-player` at
`4afbfd96`, which is not yet on `main`). Package only: one file of the RTX fixes part and one of the Model Hotloader
part; no loader (`winmm.dll`), runtime or native change. Decisions:
[ADR 0251](../decisions/0251-the-weapon-copy-draws-nothing-before-the-frame.md),
[ADR 0252](../decisions/0252-the-weapon-copy-draws-only-with-its-private-textures.md).

## The task

The camera runs of [ADR 0250](mmd-camera-hide-report.md) found two problems seen only with the RTX fixes' body and
weapon copies switched on (`rtx_pseudoplayer 1`, `rtx_pseudoweapon 1`): every later frame without path tracing, and
the Model Hotloader's server scene capture logging `secondary_collision.lua:111: attempt to compare nil with number`.
The user's "Do this task here" (2026-11-21) for the card that proposed finding both causes and fixing what is real,
then the same for the card about what those runs showed next: with the tool gun's weapon copy on, both copies in the
player's own first-person view.

## What was found

Facts with file and line references: [RESEARCH](../RESEARCH.md), "Local player shadow's weapon copy, path tracing and
the scene capture". A new PoC tool, [`shadow_copies_session.py`](../../tools/qa/shadow_copies_session.py.md), switches
the copies on and off mid-session in first and third person with a screenshot and the frame times per step, leaves out
parts of the weapon copy one by one (`--order diagnose`), and names the server's entities without a model scale.

- **Lost path tracing: the weapon copy, a scripted weapon and a third-person view.** The weapon copy's `Think` called
  the held weapon's `DrawWorldModel()` on every call, before the frame is rendered. For an engine weapon (the gravity
  gun) that method does not exist and nothing was drawn; for a scripted weapon (the tool gun) the model was drawn, and
  in every third-person view the frame fell back to the game's raster picture: the median frame went from 13.0 ms
  (third person, copies off) to 4.17 ms (the weapon copy on), the map's own sky and baked light in the screenshot,
  path tracing back in first person (11.8 ms). The camera runs 3 and 4 had both copies, the tool gun and the dance's
  camera, a third-person view: raster in every shot.
- **Both copies in first person: the weapon copy's real textures.** Under the classic `rtx_pseudoweapon_unique_hashes 0`
  the copy's client-side model drew the real weapon's textures, which no category can hide; with it at the body's hands
  the body copy showed too (its glasses, teeth and arms). Leaving out that model's draw, or giving the copy its private
  textures (`rtx_pseudoweapon_unique_hashes 1`), gave a clean view; the copy entity's own draw and the tool gun screen
  add-on played no part. The gravity gun's copy was out of sight in the shots.
- **The Model Hotloader's error: entities without a model scale.** `GetModelScale()` answers nothing for an entity
  that is not an animated model. gm_construct's five spotlight beams (`beam`, `sprites/glow_test02.vmt`) are such
  entities; once an imported character (here your own model) stood near the spawn, the scene capture asked a beam for
  its scale, compared nothing with 0.01 and stopped before the capture, every tick. The copies matter only through the
  Model Hotloader: with the body copy on it draws your imported character every frame in first person (it adopts the
  copy as a player copy), and a character drawn in the last three frames is not hidden in first person
  (`first_person.lua`, `HiddenFirstPerson`), so the client asks for the scene. Without the copy your character rests in
  first person and its capture with it: the camera runs 1 and 2 logged no error, runs 3 and 4 logged 43 and 34. Any
  imported character near such an entity (an NPC, a ragdoll) gets the same.

## What changed

- **`rtx_pseudoweapon.lua`** (the fixes part, [packages/fixes/README.md](../../packages/fixes/README.md)):
  - `Think` sets up the player's and the held weapon's bones (`SetupBones`) where it drew the weapon (ADR 0251), and
    makes no render call: a weapon change only asks for new textures.
  - The copy's own draw (`PseudoweaponRender`) makes its private textures at its first draw after a weapon change
    (`MaterialSet`, inside the frame), whatever `rtx_pseudoweapon_unique_hashes` says; it draws only with them and
    nothing before they exist, puts the material overrides back after the draw, and registers its materials as the
    player model's once their hashes are known (ADR 0252). A copy model made again in `Think` gets the same draw.
- **`secondary_collision.lua`** (the Model Hotloader part): `undrawn()` treats a missing model scale as drawn at its
  size; a model drawing no mesh is still left out.
- Both parts' `files.json` re-indexed with `inputs.py import --file` (text only).

## Tests

- **LuaJIT**: [`test_pseudoweapon.py`](../../tools/tests/test_pseudoweapon.py.md) (new, 4 tests) and
  [`test_hotloader_scene_visibility.py`](../../tools/tests/test_hotloader_scene_visibility.py.md) (`no_scale`, new; 10
  tests). The new cases fail on the files before the fixes: `DrawWorldModel` called on every `Think`, no private texture
  with the legacy setting (the file with ADR 0251 alone), and the field's `attempt to compare nil with number`.
- **PoC** (`shadow_copies_session.py`, holding `out\r10\poc.lock`; gm_construct, 1600x900, RTX on, the package's
  add-ons; the field game ran beside the earlier runs and was not ended, and was closed by the user before `diag-2`).
  Packages: before the fixes, the camera branch's (`0.0.0-dev.20261121092444+412a014d`); with ADR 0251
  (`0.0.0-dev.20261121210222+a4815247`); with ADR 0252 too (`0.0.0-dev.20261122000444+75ff93b4`). Evidence in the
  worktree's `out\lshadow\<run>\poc\run\` (`shot-*.png`, `console.log`, `remix-dxvk.log`) and
  `out\lshadow\<run>\run\summary.json`. A first `diag-1` was stopped by the user's interrupt before its first shot; the
  PoC was rolled back (verified clean) and the run repeated as `diag-2`.

| Run | Package | In hand | Steps and median frame (ms) | Seen |
|---|---|---|---|---|
| `repro-1` | before | gravity gun | before 15.9, body 17.0, both 16.9, your imported model 16.0, off 13.9 (first person) | Path traced; the capture's error right after your imported model (the beam, 84.3 s) |
| `repro-2` | before | tool gun | before 13.3, weapon 14.3, both 15.3, off 13.5 (first person) | Path traced; with the weapon copy a second tool gun in view, with both your body from inside the head |
| `repro-3` | before | tool gun | first person 12.9; third person: off 13.0, weapon **4.17**, both **4.14**; first person both 11.8 | Third person with the weapon copy: no path tracing (raster) |
| `fixed-1` | ADR 0251 | tool gun | first person 14.6; third person: off 14.2, weapon 15.2, both 12.9; first person both 12.6; your imported model 15.8 | Path traced in every shot; no capture error (the beam still has no scale, 118.1 s); both copies in first-person view |
| `fixed-body` | ADR 0251 | gravity gun | before 14.7, body 14.4, both 9.4 (first person) | Nothing of the copies in your view |
| `fixed-body-tool` | ADR 0251 | tool gun | before 12.0, body 11.4, both 11.2 (first person) | The body copy alone out of view; with the weapon copy both copies in view |
| `diag-2` | ADR 0251 | tool gun | body 7.2, weapon 6.0, entity draw left out 5.7, model draw too 6.7, drawn with the screen add-on off 6.3, camera SWEP 6.3, private textures 6.7 (first person) | Both copies in view until the model's draw is left out or the copy has its private textures |
| `verify-1` | ADR 0252 | tool gun | body 6.7, both 6.7, both in third person 6.0, gravity gun 6.4, tool gun again 8.2 (first person but the third) | Nothing of you in first person in every step; path traced in third person |

Screenshots that show it, all 1600x900:

| Shot | What it shows |
|---|---|
| `repro-3\poc\run\shot-02-02_third_off.png` | Third person, copies off: path traced, the RTX sky with clouds |
| `repro-3\poc\run\shot-03-03_third_weapon.png` | The same view with the weapon copy on: the raster picture, the map's sky, flat green grass |
| `fixed-1\poc\run\shot-03-03_third_weapon.png` | The same step with ADR 0251: path traced |
| `fixed-body-tool\poc\run\shot-03-03_both_on.png` | Both copies with the tool gun before ADR 0252: the body copy's glasses, teeth and arms in your view |
| `verify-1\poc\run\shot-03-03_both_on.png` | The same step with ADR 0252: nothing of you in view |
| `verify-1\poc\run\shot-04-04_third_both.png` | Both copies in third person with ADR 0252: path traced |

## Notes and open questions

1. Why the runtime stopped hiding the body copy while an uncategorized model was drawn at its hands was not traced
   (it releases player-model instances it finds far from the body, `filterPlayerModelInstances`); with nothing
   uncategorized drawn there it no longer arises.
2. A weapon that places a world model of its own in its `DrawWorldModel` (Customisable Weaponry 2.0's `WMEnt`) no
   longer has it updated by the copy in first person; its weapon copy may lag. Not tried.
3. The first draw after a weapon change makes one texture per weapon material through a render target capture written
   to `data` (as the copy did before with the setting on), and the copy may show for the frames before its hashes are
   registered.
4. Not checked in the field install, in a multiplayer game, or with scripted weapons other than the tool gun and the
   camera.
5. The PoC tool reports the server's entities without a model scale: on gm_construct also `worldspawn` and the brush
   entities, which the capture never asked (it skips the world and brush models first).

## Published

- `tools\test.ps1 -Config Release` on `938b7adc` (all three changes): "All checks passed." (conventions; C++ 35 of
  35; Python 29, 26 and 2184 tests). The run before it, on `2fe3f30e`, failed one C++ check, `nl_client_catalog_tests`
  at `test_leftovers.cpp(284)`: the user's field game started during the run and the leftover check counted it as
  another game; no C++ had changed since the passing run on `dbb1c5f5`, and the next run passed.
- Merged into `main` by fast-forward from `14b0accd` on the user's "Merge and publish all": the camera option (`4afbfd96`) with its follow-ups `dbb1c5f5` (ADR 0251), `2fe3f30e` (ADR 0252) and `938b7adc` (ADR 0253).
- The merge's hook uploaded item 3829070317 as `0.0.0-dev.20261122004027+d17b0fb8` (content digest `136716c4...`), with one change note carrying the three new changelog entries (the sky's chat line, the weapon copy and the scene capture, the camera option). A player's game deploys it at its next start (Steam may first only download it).
