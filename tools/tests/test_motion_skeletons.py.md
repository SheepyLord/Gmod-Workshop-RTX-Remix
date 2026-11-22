# test_motion_skeletons.py

Runs [motion_skeleton_harness.lua](motion_skeleton_harness.lua.md) under LuaJIT, once per scenario, without starting
Garry's Mod. The harness loads the shipped Character Motion Importer's `sh_core.lua` (built-file names),
`sv_cache.lua` (expression mappings) and `sv_skeletons.lua` (build models,
[ADR 0259](../../docs/decisions/0259-imported-characters-share-their-builds-across-carriers.md)) from
`packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc`, with the game's API stubbed and rig manifests made
the way the Model Hotloader writes them.

```powershell
python -I -m unittest discover -s tools/tests -p test_motion_skeletons.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_a_resized_character_finds_its_builds` | The user's report of 2026-11-22: a carrier without builds is its own build model; after a build, a resized carrier of the same skeleton finds it (the same file name, listed, accepted); a head turned half a degree does not; float noise of a millionth matches and a thousandth does not; the build model's members; a Source model keeps its old file name |
| `test_a_reimport_finds_its_builds_and_another_skeleton_does_not` | A new asset, materials, attachments, display name, donor hash and fit generator share the builds; other morph indices, another NPC profile, another role, an extra bone, or another Reference offset do not |
| `test_the_next_session_finds_the_builds_without_the_old_rig` | The skeletons are saved; the next session finds the builds for a new size after the build model's own rig is gone; the rig the Hotloader holds for the session is used without reading its file; a broken skeleton file is an empty one |
| `test_earlier_builds_and_mappings_are_adopted_once` | Builds made before the change: two carriers of one skeleton join under the one with more builds (alias), the other's build is renamed to its name unless that name is taken, both are found together and by a new size; another skeleton, a carrier whose rig is gone and a Source model are left alone; the joined carrier's expression mappings join the kept one's (the kept one's win); a summary line; through the stepped timer after `InitPostEntity`; nothing again in the next session |
| `test_a_lookup_completes_the_adoption_first` | A lookup before the stepped migration finishes completes it at once |
| `test_expression_mappings_follow_the_character` | A mapping saved for one carrier is found by a resized one, saved under the build model, and cleared through either |
| `test_the_skeleton_file_loads` | `sv_skeletons.lua` compiles |

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
