# hotloader_export.py

Exports Model Hotloader characters as a Workshop package add-on folder, through the running game.

It does what the library's Export dialog (`lua/mmdhl/workshop_export.lua`) does, with the same item
settings (spawn preset, body groups, arms, fits, terms-of-use records) and the same native call
(`StartPackageExport`), then unpacks the archive Model Hotloader writes into an add-on folder
(`addon.json` + `data_static/mmdhl/...`) that `package_content.py` takes as `--addon`.

```powershell
& $py hotloader_export.py --game-root <GarrysMod> --asset cf3eec2f --asset e2c25f9e `
    --title "Evernight and March 7th (Model Hotloader + RTX PBR)" --description-file desc.txt `
    --file-name evernight-march7th --tag cartoon --out out\packages\x\mmdhl_x
```

`--asset` takes the full 64-digit id or any unique prefix. The game must be in a map (client Lua runs
there) with Model Hotloader loaded; the models must be in its library (not shared ones). `--gmapack`
defaults to `tools\gmapack\gmapack.py` of the repository this skill sits in, else the main checkout's.

## Names (checked before the game is contacted)

The user's rule (2026-11-08): a model's recorded name is the character's own name only. Through
[model_names.py](model_names.py.md) the script refuses, with exit 1 and one `error:` line per name:

- a tagged `--title` (`Robin R18 RTX (...)`), `--file-name` or `--out` folder name (`mmdhl_robin_r18`);
- a tagged library name of any `--asset`, read from `garrysmod\data\mmd_hotloader\library\<id>.json`
  (else the import's `assets\<id>\manifest.json`, else the id's first 12 digits, as `library.lua`
  names entries): `鸣潮-千咲`, `阿芙2.0`, `Robin R18`. The export carries the library's names as they
  are, so either the user renames the model in Model Hotloader (ask first: it is their library) or the
  pack is built offline with workshop-content-pack's `mmdhl_pack.py`, which takes the names on its
  command line;
- after the export, a tagged name among the names the game exported (a rename in between): the
  archive then stays in the game's `exports` folder and `--out` is not written.

## Terms of use

The export dialog asks the player to acknowledge the models' terms of use first
(`mmdhl_terms_warning_export`). This script does not show that dialog and does not change the setting:
use it for private (hidden) items, and make an item public only after exporting through the dialog.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in
[tool/README.md](../tool/README.md). Run with the rpai venv's Python
(`%USERPROFILE%\.rpai\venv\Scripts\python.exe`).

## Side effects

Reads the install's Model Hotloader data (assets, library entries). Then, through the rpai bridge
(which writes its request and answer files under `garrysmod\data\rpai`), runs Model Hotloader's own
`StartPackageExport` in the running game, which writes `garrysmod\data\mmd_hotloader\exports\<file
name>.gma`; waits for it and unpacks it into `--out` with `gmapack extract`. Writes nothing else. It
skips the export dialog's terms-of-use acknowledgement, so it is for private (hidden) items only.

## Exit codes

0 on success; 1 when a step fails or a name is refused (the reason is printed on stderr); 2 for a bad
command line (argparse). Tests: workshop-content-pack's `test_names.py` (the name refusals, without a
game).
