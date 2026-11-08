# Wuthering Waves maps in imported game PBR (R23)

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[wuwa-maps.patch](wuwa-maps.patch) is the seventh native patch, after the public base and the six
patches before it in [pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`), which records the
patched native tree it gives (`fixes.patched_tree.source` `c7e8e29d...`; `public` and `premake5.lua`
unchanged). The complete changed files are
[game_matching.inl](source/material_pipeline/to_pbr/game_matching.inl) and
[game_pbr.h](source/material_pipeline/to_pbr/game_pbr.h), as the work tree has them (CRLF).

The user's report (R23 item 1): imported Wuthering Waves characters showed little or no PBR. Measured
on Shorekeeper and Chisa with the production matcher (`tests/game_match_probe.cpp`) and converter:

- **The `_N` map is the game's `Normal_Roughness_Metallic` map.** Every material instance exported
  beside the characters names it so: RG the normal, **alpha the roughness**, **blue the metalness**.
  R11 used it as a normal map only, so roughness and metalness came from the material-name classes.
  Now, for a WuWa family, roughness is alpha and metalness is blue from 0.55, all metal by 0.8
  (smoothstep): blue also holds a dielectric baseline (cloth up to about 0.2) and leather around
  0.4-0.55, while buckles, rings and plates sit at 0.7-0.9. Hair and the protected skin, face and eye
  texels keep their rules. The recipe tag changes, so cached maps convert again once.
- **A family without its own `_ID`/`_HM` mask was not recognised.** Chisa's coat (`Alpha`: `_D`
  and `_N` only) and Shorekeeper's `Ahpla_N` (the game's own misspelling) were dropped. A WuWa family
  is now also known by its character: another family under the same `t_<...>md<5 digits>` prefix has an
  `_ID` or `_HM` map. Such a family pairs by its exact name or by hand in the Imported game PBR panel,
  never by UV evidence alone: with UV matching it took a belly decal of Chisa's (0.386, above R12's
  thresholds), so R12's calibrated UV candidates stay exactly as before.

Result on the two characters: Chisa's `Alpha`, `Down` and `Up` pair by name and Shorekeeper's
renamed `服.png` by its UV layout (as before); their roughness means are 0.53-0.84 and metal only on
metal parts. Shorekeeper's other renamed textures still abstain (UV evidence below R12's thresholds);
the panel assigns them by hand. WuWa hair has only a 256 x 256 tiling `_HN` detail normal, not a
UV-mapped one, and keeps its class rules.

Validated build (2026-11-08, this machine): **5,518,336 bytes**, SHA-256
`45fc78ef3dc792beb85b714a584bcb2c2c2c71182f2a8597d61d6cc686aba77c`, imported once with `tools/inputs.py`.

Build with [build_modules.ps1](../../../../../tools/ci/build_modules.ps1.md) `-Only fixes` (here
through a temporary drive alias of this worktree's `out`, as R20-E did, because premake writes wrong
paths under a folder with `!`). See the loader's [ADR 0131](../../../../../docs/decisions/0131-wuthering-waves-roughness-and-metalness.md)
and [R23 report](../../../../../docs/handover/R23-report.md).
