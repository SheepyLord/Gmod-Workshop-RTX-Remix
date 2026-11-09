# 0137: Endfield's NPC, weapon and item families in imported game PBR

- Status: Accepted 2026-11-09 (found while packing 41 Arknights: Endfield characters offline for Model
  Hotloader with RTX PBR, `H:\BACKUP_20260815\Modding\ipg\AKEFRTX`); extends the Endfield layout of R11-A
  ([ADR 0091](0091-automatic-pbr-fallbacks.md)) within R12's matching
  ([ADR 0095](0095-texture-features-and-imported-pbr-overrides.md)), as
  [ADR 0131](0131-wuthering-waves-roughness-and-metalness.md) did for Wuthering Waves.
- Context: ToPBR's matcher (`Discovery::Named` in the fixes' `game_matching.inl`) took the Endfield layout only
  for `t_actor_` stems. Endfield rips also ship `T_npc_major_<x>_D` (NPCs, and the unmasked Endministrators'
  faces, bodies and hair), `T_wpn_misc_<n>_D` (weapons, such as Laevatain's sword) and `T_item_widget_<x>_D`,
  each with the same `_N`/`_HN`, `_P` and `_E` maps. In the pack's 41 models, 17 such sheets with maps beside
  them abstained ("insufficient UV edge evidence" or "conflicting exported family"): in game they got no game
  PBR unless the player chose the maps in the Imported game PBR panel. The pack baked them as manual choices.

## Decision

1. **Outside `t_actor_`, a `t_` family is Endfield when a `_P` map lies under its `t_<word>_` prefix**, its own
   (cloth, hair, weapons, items) or a sibling's (faces and bodies ship only `_N`), with no `_MRA` there. This is
   how Silver hair is already known (an `_MRA` under its prefix), and every earlier rule comes first: an own
   `_MRA` (Silver), `t_actor_` (Endfield), `_ID`/`_HM` or the character's (WuWa), an `_MRA` under the prefix
   (Silver). A family any of them recognised keeps its layout; a `T_*_D`/`T_*_N` pair with no `_P` under its
   prefix is still no game family. The family's normal map is `_N`, else `_HN`; packed `_P`; emission `_E`.
2. **Such a family pairs by its exact name or by hand, never by UV evidence alone**, like ADR 0131's WuWa
   families known by their character. R12 calibrated UV matching on `t_actor_` families, and a `_P` under a `t_`
   prefix is weaker evidence of the game than `t_actor_`. R12's UV candidates and thresholds and the panel's
   list of families stay exactly as they were.
3. **The conversion is unchanged**: no recipe tag changes, so no cached map converts again, and an automatic
   pairing gives the content keys and DDS of the same maps chosen by hand with the Endfield layout.
4. The change is the fixes' eighth native patch (`endfield-maps.patch`, after ADR 0131's `wuwa-maps.patch`),
   with its complete files, regression and README in `packages/fixes/licenses/oversized-skinning/endfield-maps`;
   `tools/ci/pins.json` records the patch and the patched tree, so GitHub's package workflow builds the same
   module, and [`test_endfield_maps.py`](../../tools/tests/test_endfield_maps.py.md) runs the regression in the
   Release gate on the shipped ToPBR headers.

## Evidence

The production matcher (`game_match_probe.cpp`) before and after, every base with names shown and hidden: in the
pack (240 bases, 480 rows) exactly the 17 changed, each to an exact-stem pairing with the Endfield layout; in R12's
corpus (121 PMX of every game, 1,133 bases) 7 rows changed, the same Endfield NPC and weapon sheets in copies of
four of those models, and nothing else; R23's WuWa corpus is unchanged. Of the pack's 17, 14 convert and the three
`_N`-only faces and bodies find only protected texels and keep their look; converted automatically, all 17 give the
content keys and DDS bytes of the pack's manual pass.

## Consequences

Imported Endfield NPCs, weapons and items get their game's normal, roughness and metalness automatically, as the
characters did. A renamed NPC, weapon or item sheet (an `_AOff` copy, a translated name) still abstains and is
assigned in the panel. The `_E` maps are converted, but ToPBR's materials author no `enable_emission`, and the
runtime gives a material without it no emission (`rtx_materials.h`), so they do not glow; that holds for every
imported game family and is left to the user (a change of look).

## Alternatives considered

- **Endfield for every `t_` family with `_N`/`_HN` and no `_MRA`**: a plain Unreal export (`T_X_D`, `T_X_N`) would
  have become Endfield, its green channel flipped. Rejected.
- **These families as UV candidates too**: renamed sheets would pair without the panel, but outside R12's
  calibration, with weaker game evidence, and more feature decodes from each folder's shared budget. Left for a
  names-hidden measurement like R12's, should renamed NPC sheets turn up.
