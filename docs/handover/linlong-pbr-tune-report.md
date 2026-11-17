# Linlong's PBR: an evened hair texture and stronger maps (2026-11-16)

The user's report: "Here address the demo pbr for Ling long we shipped yesterday: 1, In the active gmod session, the
hair's rendering looks off as the color is not uniform. 2, the PBR effect is too weak and not obvious." Done by Claude
on the branch `linlong-pbr-tune`, package only (the Model Hotloader part's `mods/mmdhl_pbr_linlong`) and the
`mmd-remix-pbr` skill ([ADR 0236](../decisions/0236-linlongs-pbr-an-evened-hair-texture-and-stronger-maps.md)).

## What the running game showed

The field game (modern_house, single-player, 3840 x 2160, an RTX session) had Linlong spawned as a ragdoll. Everything
went through rpai's console bridge (client Lua, Source's `jpeg`), with a camera framed on her bones (a temporary
`CalcView` hook); each change was put back: the hook removed, part visibility restored, `ai_pbr`'s `mod.usda` and the
shipped mod's two text files byte for byte (SHA-256 checked), the scratch mods and test textures deleted, and the 62
screenshots of the captures moved out of `garrysmod/screenshots` into `out/linlong/field-screenshots`.

- **The layer reaches her.** `rpai hashes` with her asset: the offline predictions equal the live hashes on all nine
  drawn sheets (body1-4, hair1-2, face, eye, skin); the hair overlays (前髪+, 髪+) and the painted shadows are not
  drawn.
- **The hair's blocks are the texture's.** Her hair sheets paint cream, pink and orange-brown blocks on separate
  islands. They showed the same with the layer, without it (the mod's sublayer removed) and with flat normal maps;
  with a plain red albedo on both hair sheets the hair was evenly red, with no block.
- **The shipped strength is near the noise.** Three views (wide, hair, skirt), each state shot once after a reload,
  the shipped state again at the end: the shipped layer changed her by 2.6-4.7/255 against no layer, with fine relief
  +2-5%, while two shots of the shipped state differed by 1.6-3.6/255.
- **How to test a covered character.** A test layer in `ai_pbr` (first in path order) changed nothing: once the game
  runs, a reloaded mod does not take over hashes another mod already supplies. Variants were therefore swapped into
  `mmdhl_pbr_linlong`'s own layer, backed up and put back. Remix debug views could not be used: `RemixConfig`
  refuses `rtx.debugView.debugViewIdx` since ADR 0234, and the debug module's `SetDebugView` goes through it.

## The variants (one capture run, the user's game)

| Variant | What | Change against no layer | Fine relief against no layer |
|---|---|---|---|
| shipped | the game's normal maps at 1.0 | 2.6-4.7/255 | +2-5% |
| S | evened hair; normal maps 2.0, hair 1.8 with anisotropy -0.5, glossier materials | 3.3-5.1/255 | +4-7% |
| **SP (chosen)** | evened hair; normal maps 3.0, hair 2.4 with anisotropy -0.7, glossier materials | 3.7-6.0/255 | +6-10% |
| AI | S with rpai's AI relief instead of the game's maps on the outfit | 2.3-3.7/255 | +1-2% |

The sheet sent to the user (`out/linlong/shots/linlong-pbr-options.jpg`): the blocks and the red test, the evened
hair, and shipped, S and SP on the skirt. The user chose the even cream hair and SP.

## What changed

- `packages/model-hotloader/mods/mmdhl_pbr_linlong/`: the new layer and its 28 DDS (10 normal, 10 roughness, 2 hair
  albedo, 4 anisotropy, 2 emissive; at most 2048 px; 117 MB), imported with `tools\inputs.py import model-hotloader
  --root <stage>=mods/mmdhl_pbr_linlong --prune` (21 stored, 14 removed; 20 new LFS objects, 37.6 MB). `mod.usda` is
  unchanged. The staged layer and DDS are byte for byte those of variant SP as captured.
- `skills/mmd-remix-pbr/tool/presets/models/linlong_801f3bcf.json` (new in the repository; also in the installed
  copy): the SP settings and the decision in its `doc`.
- `skills/mmd-remix-pbr/scripts/even_albedo.py` (new, with its `.md`): the evened copies (it reproduces the tested
  ones byte for byte); the tool README, `SKILL.md` and `references/testing-protocol.md` (a character a pack already
  covers; 20 s per swap; no debug views from Lua) in both copies of the skill.
- `packages/README.md` and `packages/model-hotloader/README.md` name the change.

## Not checked

- The new package in a game start: the field picks it up from the Workshop at its next start (the user's game was in
  use); the layer itself was checked in that game as variant SP.
- 1080p, other maps and lighting, and the PoC.
- Linlong standing or dancing: she lay on the floor in the user's scene throughout (face down, then face up).

## Published

Merged into `main` as `4a093eb5` and pushed (`bcd791f1..4a093eb5`, 17 LFS objects, 38 MB: the four anisotropy maps
are one file). The merge's hook built the package here and uploaded item 3829070317 as
**`0.0.0-dev.20261117034806+58651f23`** (content digest `d306ef16...`, the same as the branch's local build), its change
note the changelog's new section; the push's hook found the inputs unchanged. The field game deploys it at its next
start.
