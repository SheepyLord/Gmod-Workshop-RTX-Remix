# Imported characters keep their built motions (2026-11-22)

The user's request of 2026-11-22:

> Update the animation player to improve the experience on imported models. Currently, the imported models'
> animation needs constantly rebuilt between game sessions.

Done by Claude on the branch `mmd-built-keys` (worktree `out\worktrees\mmdkeys`, from `origin/main` at `c58a5da2`).
Package only: the character motion importer part (`packages/character-motion-importer`, the Advanced MMD Animation
Player): the new `sv_skeletons.lua`, `sh_core.lua` (`BuiltTail`), `sv_cache.lua` (the expression mappings' key),
`sv_commands.lua` (a build's file and checks, invalidation, Clear) and the autorun file; no loader (`winmm.dll`),
runtime, native or Model Hotloader change. Decision:
[ADR 0259](../decisions/0259-imported-characters-share-their-builds-across-carriers.md); facts with file and line
references: [RESEARCH.md](../RESEARCH.md) "Imported characters' carriers and the animation player's built files".

## Why the motions had to be built again

A built motion is the motion solved against one actor's skeleton, and the add-on named its file after the actor's
model path. An imported character's model is a Model Hotloader carrier, `models/mmd/<16 hex>/<name>.mdl`, whose 16 hex
are the start of a hash of the carrier's whole fit: its size, its asset (new at every import), materials, attachments,
physics edits, NPC profile and the fit's generator. Any change gave the character a new path, and its motions were
missing again.

In the user's game (read only): 668 rig manifests for 183 imported assets; grouped by character, the carrier changed
102 times since 2026-11-01, about sixty times for a new size alone (on 17 of those 21 days), about twenty-five for
another role or NPC profile, about fifteen for a new import, the rest for Hotloader updates. One motion was built three
times for one character in four days, another twice in seven minutes after a resize.

## What changed

- **A build model per skeleton.** A carrier's builds are named after the first carrier of its skeleton that got a
  build or an expression mapping (`MMDVMDNPC.BuildModelKey`, used by `BuiltTail`, so the built flags, a dance, a build
  and Clear all follow it).
- **When two carriers share one:** the same role, NPC profile, includes, IK chains and locks, pose parameters, morphs
  (the flex ids a build drives), bone names and parents, exactly; each bone's rotation, its offset from its parent
  divided by the carrier's size, and the Reference pose, within 1e-4. Scale variants of one fit differ by 3.6e-6 at most
  in the user's rigs; 79 of 85 re-imports of one character are identical; a half-degree change of a bone is not shared.
- **The skeletons are kept** in `data/mmd_vmd_npc/built/_skeletons.dat` (each build model's numbers, the carriers
  joined to one), so they match after the Hotloader deleted a build model's own rig.
- **A build's file names the build model** (`model`) and the carrier it was solved on (`built_on`).
- **Expression mappings follow** the build model too.
- **Builds and mappings from before are adopted once**, from three seconds after the first map starts, in 3 ms steps
  (or at once when a lookup needs it): carriers of one skeleton are joined under the one with the most builds, the
  others' current-format files renamed to its name (a name it already has is left), their mappings merged (its own
  win). Files of the earlier format (`mmd_vmd_npc_built_v1`, no `_fm2`), which the player does not read, stay as they
  are.

| Change of the character | Its builds |
|---|---|
| A new size | Shared (the pelvis/spine correction stays the built size's: 0.16 units at most for a 20 % change) |
| A new import of the same model, new materials or attachments, a Hotloader update that keeps the fit | Shared |
| Another skeleton fit (a generator that moved a bone, another model, an outfit with other bones) | Its own |
| Another role or NPC profile (citizen, Combine, player model) | Its own (another Reference pose) |
| Other morphs (names or indices) | Its own (other flex ids) |

## Checked

- **LuaJIT** ([test_motion_skeletons.py](../../tools/tests/test_motion_skeletons.py.md), 7 tests, new;
  [test_motion_server.py](../../tools/tests/test_motion_server.py.md)'s `build_model`): resize, re-import, the next
  session without the old rig, the migration (stepped and on demand), the mappings, and `sv_commands.lua`'s file,
  checks, invalidation and Clear. The new scenarios fail on the code before; three broken copies (no build model, a
  tolerance a hundred times looser, morphs left out) each fail one.
- **Offline, a copy of the user's data** (the field only read): the migration over its 668 rigs, its mappings and
  stand-ins of its 286 built files: 30 rig reads, 24 skeletons kept, 5 carriers joined, 3 builds renamed and 3 left;
  every character with builds then has a build model its next sizes and imports find. Of the 286 built files only 73
  are of the current format; the other 213 (1.90 GiB, last written 2026-11-02) are `mmd_vmd_npc_built_v1`, which the
  player refuses.
- **PoC, two games** ([mmd_player_session.py](../../tools/qa/mmd_player_session.py.md) `--carriers build`, then
  `--carriers find`; evidence in `out\mmdkeys-poc`):

| Session | Carrier | Size | Build model | Dance |
|---|---|---|---|---|
| 1 | `53f26d7c...` (built the test dance in 2.3 s) | 1.0 | itself | built |
| 1 | `eec7a2ea...` (new) | 1.25 | `53f26d7c...` | played, no build; hands up 11 units |
| 2 (new game) | `53f26d7c...` (fitted again) | 1.0 | itself | built |
| 2 (new game) | `cf161f4e...` (never made before) | 1.5 | `53f26d7c...` | played, no build; hands up 12.6 units |

  The PoC's character library is restored between runs, so only the skeleton file linked the second game's carriers
  to the first. One start of the second game crashed before the main menu (0xC0000005 at address 0: Chromium's
  `chrome_elf.dll` called through a null pointer inside the signature check NVIDIA NGX ran; no add-on had loaded) and
  was run again. Neither game logged an add-on error.

## Files

- `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_skeletons.lua` (new), `sh_core.lua`,
  `sv_cache.lua`, `sv_commands.lua`, `lua/autorun/mmd_vmd_npc.lua`; the part's `files.json`.
- `companion/nativeloader/lua/autorun/_nativeloader_guard.lua`: the render guard's list of the package's own Lua
  paths names `lua/mmd_vmd_npc/sv_skeletons.lua` (`test_render_guard_addons.py` requires every indexed one).
- Tests: [motion_skeleton_harness.lua](../../tools/tests/motion_skeleton_harness.lua.md) and
  [test_motion_skeletons.py](../../tools/tests/test_motion_skeletons.py.md) (new),
  [motion_server_harness.lua](../../tools/tests/motion_server_harness.lua.md) and
  [test_motion_server.py](../../tools/tests/test_motion_server.py.md) (`build_model`).
- QA: [mmd_player_session.py](../../tools/qa/mmd_player_session.py.md) (`--carriers`),
  [mmd_player_probe.lua](../../tools/qa/mmd_player_probe.lua.md), [mmd_player_server.lua](../../tools/qa/mmd_player_server.lua.md).
- Docs: ADR 0259 and its row, CHANGELOG, ROADMAP, RESEARCH, TESTING, AGENTS.md, this report and its line in the
  handover index.

## Published

`tools\test.ps1 -Config Release` passed on the branch (35 native tests; 2,201, 29 and 26 Python tests; "All checks
passed"), after one fix the first run asked for: the render guard's list of bundled paths now names the new server
file. `origin/main` had not moved from `c58a5da2`, so `main` was fast-forwarded to `217abd73` and pushed. The merge's
hook uploaded item 3829070317 as **0.0.0-dev.20261122231627+872153d3** (2,325,070,203 bytes, SHA-256
`49b726e345e50bd5908a45e2a5bc0040b30264f26c4f807cd3363e6c2b71094c`, content digest `cfc4ffdb...`) at 2026-11-22
23:17 UTC, with one change note of about 5,200 characters: this round's entry and the skills entry before it, the
changelog since the last upload (ADR 0222). The push's hook found the same inputs and uploaded nothing.

## Notes and open questions

1. The field install was not run in a game (rule 1). Its migration runs at the first map start after the update;
   on a copy of its data it took 30 rig reads.
2. Clear for one carrier, and a changed expression mapping, act on every carrier sharing the build model.
3. The 213 built files of the earlier format (1.90 GiB) in the user's game are dead weight: the player refuses their
   format. Deleting them is the user's call.
4. A build reused at another size keeps its pelvis/spine correction at the size it was built (0.16 units at most for
   a 20 % change, with the pelvis turned 45 degrees); Clear and Build make it exactly for the new size.
