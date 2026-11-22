# 0259: Imported characters share their built animations across their carriers

- Status: Accepted 2026-11-22 (the user's request of 2026-11-22: "Update the animation player to improve the
  experience on imported models. Currently, the imported models' animation needs constantly rebuilt between game
  sessions.")
- Package only: the character motion importer's `sv_skeletons.lua` (new), `sh_core.lua` (`BuiltTail`), `sv_cache.lua`
  (the expression mappings' key), `sv_commands.lua` (a build's file, its checks, invalidation, Clear) and its autorun
  file. No loader change, no Model Hotloader change.

## Context

The Advanced MMD Animation Player builds a motion for one actor: the client poses the actor in its own Reference
pose and solves, for every frame, each tracked bone's manipulation from that pose (`cl_menu.lua`,
`fast_compile_solver`); the server writes the frames, by bone and flex index, to a built file named after the actor's
model path (`sh_core.lua`, `BuiltTail`: `<motion>_<safe model name>_<CRC of the path>_<options>_fm2.json`) and plays
only a file whose header names that model.

A Model Hotloader character is a carrier, `models/mmd/<16 hex>/<name>.mdl`, whose 16 hex are the start of a hash of
the carrier's whole fit manifest (the Hotloader's `rig.cpp`, `identify`): its size, its asset (a new one at every
import of the character), its materials, attachments, physics edits, the NPC profile it animates with and the fit's
generator. Any of them gives the character a new model path, and every motion built for it was missing again.

Measured in the user's game (read only, 2026-11-22): 668 rig manifests for 183 imported assets. Grouped by
character, the carrier changed 102 times since 2026-11-01: about sixty for a new size alone, about twenty-five for
another role or NPC profile, about fifteen for a new import, the rest for Hotloader updates (attachments, materials,
generator). One motion was built three times for one character in four days; another twice in seven minutes.
The built folder held 286 files, 73 of them in the current format (`_fm2`; the other 213 are of an earlier format
this add-on no longer reads).

What a build depends on: the solver reads each bone's orientation in the Reference pose and the bones' and flexes'
indices; positions only once, for the pelvis/spine correction (the spine's offset from the pelvis). Motion offsets are
in the motion's units for every model. A carrier's Reference pose comes from its own bones (the fitted rest
transforms), its Reference table (`animation.reference`) and its role, profile, IK chains and locks; its flexes from
its morph list. Between scale variants of one fit in the user's 668 rigs the rotations differ by at most 1.8e-6 per
quaternion component and the bones' offsets from their parents, divided by the size, by 3.6e-6; 79 of 85 pairs of
re-imports of one character are identical within 1e-4, and 12 pairs of different characters (outfit variants of one
base model) have identical skeletons.

## Decision

1. **A build model per skeleton.** `MMDVMDNPC.BuildModelKey(model)` names the model whose file names a model's builds
   take. For a Model Hotloader carrier it is the build model of the carrier's skeleton when one exists, else the
   carrier itself; for any other model the model itself. `BuiltTail` names files after it, so every lookup (the built
   flags, a dance, a build, Clear) follows it without changes of their own.
2. **Two carriers share a build model when a build solved on either would be the same** (`sv_skeletons.lua`,
   `Signature` and `Matches`): exactly the same version, role, NPC profile, includes, IK chains (with their knees) and
   locks, pose parameters, mesh and reference yaw, joint frame convention, native flex count, morphs (name, PMX name,
   PMX and native index), bone names and parents and Reference length; and within 1e-4 each bone's rotation, its offset
   from its parent divided by the carrier's size (the root's above the actor's fixed height, `actorOrigin`), each
   Reference rotation, and each Reference offset as written or divided by the size (a bone of the profile's skeleton
   keeps that skeleton's offset at every size; a fitted one scales). The numbers come from the Hotloader's rig manifest:
   the one it holds for the session (`mmdhl.rigsByModel`), else the carrier's `rig.json`.
3. **The skeletons are kept** in `data/mmd_vmd_npc/built/_skeletons.dat`: each build model's numbers (six decimals)
   and the carriers joined to one (aliases). Carriers match a build model after the Hotloader deleted the build
   model's own rig.
4. **The first carrier of a skeleton that gets a build or an expression mapping becomes its build model**
   (`NoteBuildModel`, after `finalize_build` and `SetFlexOverrideForModel`); carriers that found none before look again.
   A build's file names the build model (`model`) and, when it differs, the carrier it was solved on (`built_on`).
5. **Expression mappings follow the character** like its builds: their key is the build model.
6. **Builds and mappings from before are adopted once** (the migration): the carriers named by current-format build
   files and by mappings whose rigs remain are grouped by skeleton; each group keeps the carrier with the most builds,
   the others' files take its name (a name it already has is left as it was) and their mappings join its (its own
   win). It runs in steps of 3 ms a tick from three seconds after the map starts, or at once when a lookup needs it,
   and never again (`migrated` in the skeleton file). Files of the earlier format are left alone.
7. **Not shared:** another role or NPC profile, other morphs, another fitted skeleton (a fit generator that moved a
   bone, another character) or another donor's IK locks. Those build again, as before.

## Consequences

- A resized character, a new import of it, a Hotloader update and a new map session find the motions built before.
  On a copy of the user's data the migration keeps 24 skeletons, joins 5 carriers to them, renames 3 builds and leaves
  3 duplicates, in one pass of 30 rig reads; every character with builds then has a build model its later carriers
  find.
- A build reused at another size is the build of the size it was made at: its rotations and motion offsets are a
  fresh build's; its pelvis/spine correction (on by default) is that size's. The correction works from the spine's
  offset from the pelvis, 0.06 units in the median of the user's 298 citizen carriers at size 1 and 2.1 at most, so at
  a 20 % change of size it differs by 0.16 units at most with the pelvis turned 45 degrees. Clear and Build make it at
  the new size.
- Clear, and a changed expression mapping, act on the build model: for every carrier sharing it. Each such change
  sends one replica message per carrier this session found under it.
- No client or network change: the client's own replica of a build made this session names the carrier it was made
  on, and plays locally on that carrier (on another carrier the server's pose plays, as with any build of an earlier
  session).
- A deleted or broken `_skeletons.dat` makes each carrier its own build model again until it is rebuilt from the rigs
  that remain (the migration runs again); build models whose rig is gone are lost to new carriers then.

## Alternatives

- **Key builds by asset id and size:** a new import changes the asset; a Hotloader update changes the carrier without
  it; and it would share builds across fits that differ.
- **An exact hash of quantized numbers:** float noise of a fit at another size straddles some rounding step in most
  rigs (some 600 numbers each), so the hash would differ anyway.
- **Rescale a build's offsets to the new size:** a fresh build at that size does not scale the motion's offsets;
  the two would differ.
- **Keep one carrier path across sizes in the Hotloader:** a carrier's model file holds its size; sizes are different
  files.
