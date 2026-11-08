# package_characters.py

Packages published rpai characters into a folder for reuse (a drop-in Remix mod plus each character's
maps, AI cache and settings). Not a Workshop pack: that is the workshop-content-pack skill.

```powershell
& $py package_characters.py --dest "H:\path\to\package" `
    --character Guinevere=new_mmd_model_9cdc990f="E:\...\桂乃芬.pmx" `
    --character Hyacine=hyacine_r18_6ca2dcc3
```

Layout:

```
remix_mod/<mod>/       drop-in Remix mod: mod.usda (only the packaged layers), models/*.usda and
                       exactly the DDS files those layers reference
characters/<name>/     maps/ (final PNGs), raw/ (AI cache), masks/, classes/hashes/generated.json,
                       preview.jpg, compare_*.jpg, preset.json (per-model settings, when present)
tool/                  a copy of rpai (skip with --no-tool)
package.json, README.md
```

| Option | Meaning |
|---|---|
| `--dest` | the package folder; must be empty or new, unless `--update` |
| `--character NAME=MODEL_KEY[=PMX]` | repeatable. NAME is the character's own name (the folder `characters/<NAME>`, the README row, the `package.json` key); MODEL_KEY the rpai key (`rpai status`), which may carry tags because rpai derives it from the PMX's English name; PMX optional, recorded |
| `--mod` | the live rpai mod to package from (default `ai_pbr`; `ai_pbr_2048` for the 8 GB variant) |
| `--game-root` | default: the game root in `%USERPROFILE%\.rpai\config.json` |
| `--no-raw`, `--no-tool` | leave out the AI cache (about 300 MB per character) or the tool copy |
| `--update` | allow writing into a non-empty destination (a hand-written README stays) |

**Names.** The user's rule (2026-11-08) through [model_names.py](model_names.py.md): a NAME carrying a
game, version, author, rating or pack tag (`鸣潮-千咲`, `阿芙2.0`, `Robin R18`, `Chisa RTX`) is refused
with exit 1 before anything is read or written. Give the character's name as the user uses it.

Published USD layers are copied and checked **byte for byte**, preserving all shader inputs, including
`emissive_adaptive_intensity` and the older-runtime `emissive_intensity` fallback. The generated README
explains both modes. Packaging does not add or tune emission: publish the desired ratio first, or use
[set_adaptive_emission.py](set_adaptive_emission.py.md) on a staged mod. The Python entry point also
accepts an argument list for offline tests (the repository's `tools/tests/test_adaptive_emission.py`).

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in
[tool/README.md](../tool/README.md). Run with the rpai venv's Python
(`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads the live mod, rpai's work folders and presets; writes only `--dest` (empty or new, unless
`--update`), then checks every copied DDS against the live mod.

## Exit codes

0 on success; 1 when a step fails or a NAME is refused (the reason is printed); 2 for a bad command
line (argparse). Tests: `tools/tests/test_adaptive_emission.py` (packaging) and workshop-content-pack's
`test_names.py` (the name refusal).
