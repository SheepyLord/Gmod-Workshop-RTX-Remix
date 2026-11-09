# Imported game materials glow where their game's emission map does

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[game-emission.patch](game-emission.patch) is the ninth native patch, after the public base and the eight
patches before it in [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`), which records the
patched native tree it gives (`fixes.patched_tree.source` `474d7922...`; `public` and `premake5.lua`
unchanged). The complete changed files are [usda.cpp](source/material_pipeline/to_pbr/usda.cpp) and the
native ToPBR regression [to_pbr_test.cpp](tests/to_pbr_test.cpp), as the work tree has them (CRLF). The
build applies only the patch's `source/` part (`fixes.patch_paths`).

ToPBR's imported game materials (R11-R13; Arknights: Endfield and Silver Palace families with an `_E` map)
wrote `emissive_mask_texture` and `emissive_intensity` but never `enable_emission`. The runtime's default for
it is off (`rtx_material_data.h:65` at the packaged fork commit `c6b48ed1`), and a material with emission off
gets none (`rtx_materials.h:970` caches its intensity as 0), so no game emission map ever glowed. The user
chose to have them glow (2026-11-09, after [ADR 0137](../../../../../docs/decisions/0137-endfield-npc-weapon-and-item-maps.md)).

- **`WriteOpaqueMaterial` writes `bool inputs:enable_emission = 1` for an imported game material with an
  emission map**, beside its existing texture and intensity. World conversion (vanilla ToPBR, off by
  default) keeps its emission off, and a game material without an emission map gets no flag.
- **The intensity stays the game record's 1**: an `_E` map is non-zero only on the parts the game lights
  (the AKEF pack's 40 converted maps: median 0.6 % of texels, at most 16 % on Laevatain's sword, lit texels'
  values 0.3-0.9), and at intensity 1 those parts read clearly bright in daylight (the PoC's daytime
  `adapted_yf` about 0.115 at exposure 1.5) and glow at night (exposure at its cap of 16). No scene-adaptive
  input ([ADR 0067](../../../../../docs/decisions/0067-scene-adaptive-emission.md)): a fixed emitter is what
  a lit part is.
- **No map converts again**: the flag is in the published USD layer, which ToPBR writes again whenever its
  content changes (polled every 3 s), so an install picks it up in its next session; the converted maps, their
  recipe and the game registry are unchanged.

[to_pbr_test.cpp](tests/to_pbr_test.cpp), built as [the R11 notes](../autopbr/docs/TOPBR_R11.md) describe
(the production format handlers, VTF code and USD writer; `tests/vtf_parser/stubs` first on the include path,
then `source`, `public/include` and garrysmod_common's `include`; MSVC C++17 `/EHsc /UNDEBUG`), passes with this
patch and fails without it at the game emission check. It needs the fixes' own headers, so the loader's Release
gate checks this folder's files against the patch instead
([test_game_emission.py](../../../../../tools/tests/test_game_emission.py.md)).

Validated build (2026-11-09, this machine): **5,519,360 bytes**, SHA-256
`477c2266ac49c8cd397b01bf5e1b7ae4db0f4a318bb233881b7c7b82fd859545` (the eight patches before it included),
imported once with `tools/inputs.py`. Built with [build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md)
`-Only fixes` through a temporary drive alias of this worktree's `out` (premake writes wrong paths under a folder
with `!`). See the loader's [ADR 0138](../../../../../docs/decisions/0138-imported-game-emission-glows.md).
