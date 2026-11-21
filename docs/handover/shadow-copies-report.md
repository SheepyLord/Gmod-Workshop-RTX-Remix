# Local player shadow's weapon copy and the scene capture (report)

Claude, 2026-11-21, on the branch `local-shadow-fixes` (worktree `out\worktrees\mcam`, from `mmd-camera-hide-player` at
`4afbfd96`, which is not yet on `main`). Package only: one file of the RTX fixes part and one of the Model Hotloader
part; no loader (`winmm.dll`), runtime or native change. Decision:
[ADR 0251](../decisions/0251-the-weapon-copy-draws-nothing-before-the-frame.md).

## The task

The camera runs of [ADR 0250](mmd-camera-hide-report.md) found two problems seen only with the RTX fixes' body and
weapon copies switched on (`rtx_pseudoplayer 1`, `rtx_pseudoweapon 1`): every later frame without path tracing, and
the Model Hotloader's server scene capture logging `secondary_collision.lua:111: attempt to compare nil with number`.
The user's "Do this task here" (2026-11-21) for the card that proposed finding both causes and fixing what is real.

## What was found

Facts with file and line references: [RESEARCH](../RESEARCH.md), "Local player shadow's weapon copy, path tracing and
the scene capture". A new PoC tool, [`shadow_copies_session.py`](../../tools/qa/shadow_copies_session.py.md), switches
the copies on and off mid-session in first and third person with a screenshot and the frame times per step, and names
the server's entities without a model scale.

- **Lost path tracing: the weapon copy, a scripted weapon and a third-person view.** The weapon copy's `Think` called
  the held weapon's `DrawWorldModel()` on every call, before the frame is rendered. For an engine weapon (the gravity
  gun) that method does not exist and nothing was drawn; for a scripted weapon (the tool gun) the model was drawn, and
  in every third-person view the frame fell back to the game's raster picture: the median frame went from 13.0 ms
  (third person, copies off) to 4.17 ms (the weapon copy on), the map's own sky and baked light in the screenshot,
  path tracing back in first person (11.8 ms). The camera runs 3 and 4 had both copies, the tool gun and the dance's
  camera, a third-person view: raster in every shot.
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

- **`rtx_pseudoweapon.lua`** (the fixes part, [packages/fixes/README.md](../../packages/fixes/README.md)): `Think` sets
  up the player's and the held weapon's bones (`SetupBones`) where it drew the weapon. The copy follows the hand as
  before; its own model still draws in the frame and hides in third person.
- **`secondary_collision.lua`** (the Model Hotloader part): `undrawn()` treats a missing model scale as drawn at its
  size; a model drawing no mesh is still left out.
- Both parts' `files.json` re-indexed with `inputs.py import --file` (text only).

## Tests

- **LuaJIT**: [`test_pseudoweapon.py`](../../tools/tests/test_pseudoweapon.py.md) (new, 3 tests) and
  [`test_hotloader_scene_visibility.py`](../../tools/tests/test_hotloader_scene_visibility.py.md) (`no_scale`, new; 10
  tests). The new cases fail on the files before the fix: `DrawWorldModel` called on every `Think`, and the field's
  `attempt to compare nil with number`.
- **PoC** (`shadow_copies_session.py`, holding `out\r10\poc.lock`; gm_construct, 1600x900, RTX on, the package's
  add-ons; the field game ran beside it and was not ended). Before the fix, the package of the camera branch
  (`0.0.0-dev.20261121092444+412a014d`); after it, this branch's (`0.0.0-dev.20261121210222+a4815247`). Evidence in the
  worktree's `out\lshadow\<run>\poc\run\` (`shot-*.png`, `console.log`, `remix-dxvk.log`) and
  `out\lshadow\<run>\run\summary.json`.

| Run | Package | In hand | Steps and median frame (ms) | Seen |
|---|---|---|---|---|
| `repro-1` | before | gravity gun | before 15.9, body 17.0, both 16.9, your imported model 16.0, off 13.9 (first person) | Path traced; the capture's error right after your imported model (the beam, 84.3 s) |
| `repro-2` | before | tool gun | before 13.3, weapon 14.3, both 15.3, off 13.5 (first person) | Path traced; with the weapon copy a second tool gun in view, with both your body from inside the head |
| `repro-3` | before | tool gun | first person 12.9; third person: off 13.0, weapon **4.17**, both **4.14**; first person both 11.8 | Third person with the weapon copy: no path tracing (raster) |
| `fixed-1` | after | tool gun | first person 14.6; third person: off 14.2, weapon 15.2, both 12.9; first person both 12.6; your imported model 15.8 | Path traced in every shot; no capture error (the beam still has no scale, 118.1 s) |
| `fixed-body` | after | gravity gun | before 14.7, body 14.4, both 9.4 (first person) | Nothing of the copies in your view |
| `fixed-body-tool` | after | tool gun | before 12.0, body 11.4, both 11.2 (first person) | The body copy alone out of view; with the weapon copy both copies in view |

Screenshots that show it, all 1600x900:

| Shot | What it shows |
|---|---|
| `repro-3\poc\run\shot-02-02_third_off.png` | Third person, copies off: path traced, the RTX sky with clouds |
| `repro-3\poc\run\shot-03-03_third_weapon.png` | The same view with the weapon copy on: the raster picture, the map's sky, flat green grass |
| `fixed-1\poc\run\shot-03-03_third_weapon.png` | The same step with the fix: path traced |
| `fixed-body-tool\poc\run\shot-02-02_body_on.png` | The body copy alone with the tool gun: nothing of it in your view |
| `fixed-body-tool\poc\run\shot-03-03_both_on.png` | With the weapon copy too: the body copy's glasses, teeth and arms in your view, the weapon copy in its hands |

## Notes and open questions

1. **Open, not changed: the weapon copy of a scripted weapon shows both copies in first person.** With the tool gun's
   weapon copy on, the body copy's glasses, teeth and arms and the weapon copy itself are drawn in your own view, before
   and after this fix; the body copy alone stays out of view, and the gravity gun's weapon copy does not do it. The
   body's player-model categories were set before every such shot. The runtime treats every player-model instance more
   than 34 units (horizontally) or 64 (vertically) from the last instance with the player-body category as an ordinary
   one (`filterPlayerModelInstances`); what the tool gun's weapon copy changes there was not found. The weapon copy is
   off in the classic settings the companion applies ("Local player shadow" switches only the body copy), and with
   `rtx_pseudoweapon_unique_hashes 0` (also classic) it has the real weapon's textures, so it cannot be hidden from your
   view anyway. A possible follow-up.
2. A weapon that places a world model of its own in its `DrawWorldModel` (Customisable Weaponry 2.0's `WMEnt`) no
   longer has it updated by the copy in first person; its weapon copy may lag. Not tried.
3. Not checked in the field install, in a multiplayer game, or with scripted weapons other than the tool gun.
4. The PoC tool reports the server's entities without a model scale: on gm_construct also `worldspawn` and the brush
   entities, which the capture never asked (it skips the world and brush models first).
