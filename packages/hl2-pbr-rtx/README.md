# hl2-pbr-rtx

Half-Life 2 PBR RTX at 2K, shipped with the RTX package at the user's request of 2026-11-26
([ADR 0269](../../docs/decisions/0269-half-life-2-pbr-rtx-at-2k-ships-with-the-rtx-package.md)). It holds PBR materials
under RTX Remix for the weapons and spawnable items of Half-Life 2 and Garry's Mod, in every map.

| Covers | Items |
|---|---|
| Weapons, first-person and world models | crowbar, gravity gun, physics gun, pistol, .357, SMG, AR2, shotgun, crossbow, RPG, grenades, SLAM, stunstick, bugbait, tool gun, camera |
| Items | health kits and vials, suit batteries, ammunition, the health and suit chargers, mines, the thumper, the HEV suit, the helicopter bomb, the editors' cube |

It is one Remix mod folder, `!hl2_pbr_rtx_shipped_2k`, which the part's packager deploys to
`rtx-remix/mods/!hl2_pbr_rtx_shipped_2k`:

| What | Count or size |
|---|---|
| Replacements (`materials.usda`) | 69 for 67 textures |
| DDS maps (`textures/`) | 281, every one at most 2048 on its longer edge |
| Folder size | 1,034,382,258 bytes |
| Git LFS storage | 644 MB |

The player models' hands, the NPCs and the map textures are not included; the Half-Life 2 view models' own gloves are.

## Where it comes from

The `remix-map-pbr` skill's pipeline for the game's own assets made the mod
([game-assets.md](../../skills/remix-map-pbr/references/game-assets.md)). The pipeline lives on the local branch
`claude/hl2-pbr-rtx` of the user's fork `SheepyLord/garrys-mod-rtx-remixed`:
- tools in `source/hl2_pbr_rtx/tools`;
- the doc in `docs/HL2_PBR_RTX.md`;
- the commit recorded in `files.json`.

The full mod draws the view models at 4096. Its `pack_mod.py --max-side 2048` cut leaves out each DDS file's top mip
levels: no second encode, the same maps one size down. On the PoC at 3840x2160 the 2K mod looked the same as the full
one, 0.7-1.6 of 255 apart under the same sky.

The folder name is this part's own. The loader skips a package whose files overlap an active package's (ADR 0006), so
the bundled copy shares no folder with the standalone packages. Those are `hl2-pbr-rtx` (the full version, folder
`!hl2_pbr_rtx_pack`) and `hl2-pbr-rtx-2k` (`!hl2_pbr_rtx_pack_2k`); the development build is `!hl2_pbr_rtx`. The name
sorts after all of them. The runtime takes a replaced texture from the folder that sorts first, so a game that also has
one of those shows it. Every one of these names sorts before the map packs and the RTX fixes' `base_mod`.

## Updating

In the fork, from `source/hl2_pbr_rtx/tools`:

```powershell
python pack_mod.py --max-side 2048 --folder "!hl2_pbr_rtx_shipped_2k" --mod-label "(RTX package, 2K)"
```

Then here:

```powershell
python tools\inputs.py import hl2-pbr-rtx --root "<fork>\source\hl2_pbr_rtx\work\package_2k\!hl2_pbr_rtx_shipped_2k=!hl2_pbr_rtx_shipped_2k" --prune
```

Afterwards, put `<repo>` back into the `source` and `git.repository` of `files.json` (AGENTS.md rule 10), and run
`python tools\inputs.py verify --part hl2-pbr-rtx`.

## Licence and credits

- **The textures.** They are derived from textures that ship with Half-Life 2 and its episodes (Valve Corporation)
  and Garry's Mod (Facepunch Studios). The rights in them stay with those companies, and this repository's MIT licence
  does not cover them. They are bundled at the user's decision (ADR 0269) for use with Garry's Mod, which ships the
  originals.
- **The maps.** The normal and roughness maps were made with PBRify's models (CC0).
- **The colours.** OpenAI's image model, run with the user's API key, re-rendered the colour of 50 of the 67 sheets,
  where its answer kept every part in place. The rest are the local upscale of the game's own colour.
