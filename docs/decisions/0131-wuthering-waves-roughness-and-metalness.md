# 0131: Wuthering Waves maps give roughness and metalness; families known by their character

- Status: Accepted 2026-11-08 (R23, the user's item 1); changes R11-A's "Wuthering Waves normals only"
  rule (the [R11 report](../handover/R11-report.md), the fixes' autopbr `Source.md`) within the imported game
  maps of [ADR 0091](0091-automatic-pbr-fallbacks.md), [ADR 0095](0095-texture-features-and-imported-pbr-overrides.md)
  and [ADR 0098](0098-compact-imported-game-maps-and-recipe-keys.md)
- Context: the user: "PBR resources for Wuthering Wave characters doesn't seem to work properly (or strong
  enough for user to notice). Test imports does not show PBR up in game." Measured on Shorekeeper and Chisa
  with the production matcher and converter: only Chisa's `Up` and `Down` paired, as normal maps; roughness
  and metalness came from material-name classes.

## Decision

1. **A WuWa `_N` map is the game's `Normal_Roughness_Metallic` map**, as every exported material instance
   names it: RG the normal (Z rebuilt, as before), **alpha the roughness**, **blue the metalness**. Blue also
   holds a dielectric baseline (cloth up to about 0.2) and leather around 0.4-0.55, while buckles, rings and
   plates sit at 0.7-0.9, so metalness is blue through a smoothstep from 0.55 to 0.8. Hair and the protected
   skin, face and eye texels keep their rules. The conversion recipe's tag changes, so cached WuWa maps (and,
   since the tag is shared, every game family) convert again once.
2. **A WuWa family is known by its character**, not only by its own `_ID`/`_HM` masks: Chisa's coat (`Alpha`,
   `_D` and `_N` only) and Shorekeeper's `Ahpla_N` (the game's spelling) qualify when another family under the
   same `t_<...>md<5 digits>` prefix has an `_ID` or `_HM` map.
3. **Such a family pairs by its exact name or by hand** (the Imported game PBR panel), never by UV evidence
   alone: offered to UV matching, it took a belly decal of Chisa's at 0.386, above R12's thresholds. R12's
   calibrated UV candidates stay exactly as they were.
4. The change is the fixes' seventh native patch (`wuwa-maps.patch`), with its complete files and README in
   `packages/fixes/licenses/oversized-skinning/wuwa-maps`; `tools/ci/pins.json` records the patch and the
   patched tree, so GitHub's package workflow builds the same module.

## Consequences

Imported WuWa characters show the game's own roughness and metalness: matte cloth, glossy leather and metal
only where the game has metal. Characters with renamed textures (Shorekeeper's `服.png` and the like) still
depend on UV evidence or the panel. WuWa hair (a 256 x 256 tiling `_HN` detail normal only) is unchanged.
