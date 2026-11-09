# Endfield NPC, weapon and item maps in imported game PBR

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[endfield-maps.patch](endfield-maps.patch) is the eighth native patch, after the public base and the seven
patches before it in [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`), which records the
patched native tree it gives (`fixes.patched_tree.source` `81da263b...`; `public` and `premake5.lua`
unchanged). The complete changed files are
[game_matching.inl](source/material_pipeline/to_pbr/game_matching.inl) and the matching regression
[game_matching_test.cpp](tests/game_matching_test.cpp), as the work tree has them (CRLF). The build applies
only the patch's `source/` part (`fixes.patch_paths`).

Arknights: Endfield rips ship, beside the characters' `T_actor_<name>_*` families, NPC, weapon and item
families: `T_npc_major_<x>_D` (NPCs, and the unmasked Endministrators' faces, bodies and hair),
`T_wpn_misc_<n>_D` (weapons, such as Laevatain's sword) and `T_item_widget_<x>_D`, with the same `_N`/`_HN`,
`_P` and `_E` maps. ToPBR's matcher took the Endfield layout only for `t_actor_` stems, so these sheets
abstained ("insufficient UV edge evidence" or "conflicting exported family") and got no game PBR unless the
player chose their maps in the Imported game PBR panel.

- **Outside `t_actor_`, a `t_` family is Endfield when a `_P` map lies under its `t_<word>_` prefix**: its
  own (cloth, hair, weapons, items) or a sibling's (faces and bodies ship only `_N`). Silver hair is known
  the same way, by an `_MRA` under its prefix, and that rule still comes first, as do `t_actor_` and WuWa: a
  family an earlier rule recognised keeps its layout, and a plain `T_*_D`/`T_*_N` pair with no `_P` under its
  prefix is still no game family. The family's normal map is `_N`, else `_HN`; its packed map `_P`; its
  emission `_E`.
- **Such a family pairs by its exact name or by hand, never by UV evidence alone**, like R23's WuWa families
  known by their character: R12 calibrated UV matching on `t_actor_` families, and a `_P` under a `t_` prefix
  is weaker evidence of the game. R12's UV candidates and thresholds, and the panel's list of families, are
  as before.
- **The conversion is unchanged** (no new recipe tag, so no cached map converts again): an automatic pairing
  gives the content keys and maps of the same maps chosen by hand with the Endfield layout.

Measured with the production matcher (`tests/game_match_probe.cpp`, autopbr) built before and after this
patch, every base with names shown and hidden:

| Corpus | Rows | Changed | Accepted before / after |
|---|---:|---:|---:|
| The AKEF pack's 41 Endfield PMX (240 bases) | 480 | 17, each by exact stem | 222 / 239 |
| R12's corpus (121 PMX of every game, 1,133 bases) | 2,266 | 7, each by exact stem (the same Endfield models) | 535 / 542 |
| R23's WuWa corpus (Shorekeeper, Chisa) | 98 | 0 | 5 / 5 |

Every changed row is an Endfield NPC, weapon or item sheet that now pairs by its exact stem with the Endfield
layout; no names-hidden row changed. The AKEF pack's 17 are the sheets that abstained with maps beside them:
14 convert, and the three `_N`-only faces and bodies find only protected skin and face texels and keep their
look. Converted automatically (the pack's SDK-free build of `GamePBR::Convert` on these headers), all 17
give the content keys and DDS bytes of the pack's manual pass.

Validated build (2026-11-09, this machine): **5,519,360 bytes**, SHA-256
`82ceef697486e28b9d44dfa9de5b03861e473aeb1dc7c8e0485f3745e9c5e4c5`, imported once with `tools/inputs.py`; the
module in the package now is the ninth patch's build ([game-emission](../game-emission/README.md)), which
includes this patch.
Built with [build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md) `-Only fixes` through a temporary
drive alias of this worktree's `out`, as R20-E and R23 did (premake writes wrong paths under a folder with
`!`). [test_endfield_maps.py](../../../../../tools/tests/test_endfield_maps.py.md) runs the matching
regression in the Release gate on the ToPBR headers the module is built from. See the loader's
[ADR 0137](../../../../../docs/decisions/0137-endfield-npc-weapon-and-item-maps.md).
