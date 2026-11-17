# 0236: Linlong's PBR: an evened hair texture and stronger maps

- Status: Accepted 2026-11-16 (the user's two choices from an A/B in the game)
- Decided by: the user ("Here address the demo pbr for Ling long we shipped yesterday: 1, In the active gmod session,
  the hair's rendering looks off as the color is not uniform. 2, the PBR effect is too weak and not obvious."). Shown
  the measured sheets, they chose "Even cream hair" and "SP: strongest".
- Builds on: [0231](0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md) (Linlong's RTX PBR ships with the Model
  Hotloader as the Remix mod `mmdhl_pbr_linlong`).
- Report: [linlong-pbr-tune-report.md](../handover/linlong-pbr-tune-report.md).

## Context

The shipped layer gave ten of Linlong's sheets normal and roughness maps at 2048: her outfit and hair took the game's
own normal maps at strength 1.0, the rest rpai's AI relief; her eyes kept their emission. In the field game all nine
of her drawn sheets had live texture hashes equal to the pack's offline predictions, so the layer reached her.

- **The hair.** Her two hair sheets paint hard-edged blocks of cream, pink and orange-brown on separate UV islands;
  on the mesh they meet wherever the hair twists or lies in clumps. They look the same with the layer, without it,
  and with flat normal maps; a plain red test albedo removed every block. They are the texture's.
- **The strength.** Against no layer at all the shipped maps changed her by 2.6-4.7/255 over three views at 4K, with
  fine relief (band-passed lightness) up 2-5%: little more than the 1.6-3.6/255 between two shots of the same state.

## Decision

1. **Her hair sheets get evened copies as their albedo** (rpai's `albedo_source`, made by the skill's new
   `scripts/even_albedo.py`): one cream main tone measured from the sheets (L* 84.7, a* 2.2, b* 13.9), the strand
   detail kept, 35% of the colour detail and 15% of the broad shading; the broad lightness spread falls from 3.6 and
   4.6 to 1.0. The pink and orange-brown ends go with the blocks.
2. **The stronger maps (variant SP):** the outfit's game normal maps at 3.0 on its three sheets; cloth roughness 0.6
   with more of its AI variation (0.65), the lace 0.45, the waxed canvas 0.48, the gloves' leather 0.42, the leaves
   0.28 (relief 2.2), the petals 0.38, the badge 0.12, the apron's print 0.24; the hair 0.26 with its game normal maps
   at 2.4 and anisotropy -0.7 along the strands, on the hair sheets only (rpai's hair class is also the canvas).
   Measured against no layer: 3.7-6.0/255, fine relief +6-10%.
3. **Unchanged:** 2048 (the 8 GB tier), the same ten materials, the painted shadows (目影, 髮影) left out, the eyes'
   emission; the folder `mmdhl_pbr_linlong` and its `mod.usda`.
4. **The settings live in her per-model preset** (`skills/mmd-remix-pbr/tool/presets/models/linlong_801f3bcf.json`,
   also in the installed copy), so the layer can be made again with rpai.

## Consequences

- Linlong looks different in RTX sessions: one cream hair colour, visible weave and canvas texture, glossier hair,
  leaves and badge. The game-map look of her outfit stays (rpai's AI relief at 2048 measured weaker, +1-2%).
- The mod grows from 92 to 117 MB (28 DDS: two hair albedos and four anisotropy maps added); 20 new Git LFS objects,
  37.6 MB stored. Her maps load at her first draw (runtime patch 0030), as before.
- The way to test a character a pack already covers in a running game is in the skill's testing protocol: a variant
  in `ai_pbr` does not take over hashes another mod already supplies, so variants go into the owning mod's own layer,
  backed up and put back byte for byte.
