# mmdhl_pack.py

Builds a **Model Hotloader Workshop package** as an add-on folder (`mmdhl_<name>`), offline, from a
Model Hotloader cache. It is the fallback for `hotloader_export.py` (mmd-remix-pbr skill), which runs
Model Hotloader's own exporter in the running game. Use this one when the game is not running, or
when the package needs a display name or preset name the library does not have.

The folder is the `--addon` input of the repository's `tools\package_content.py`. Its format is in
[../references/model-hotloader-package.md](../references/model-hotloader-package.md).

```powershell
$B = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\packages\robin'
python -I scripts\mmdhl_pack.py H:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\mmd_hotloader f9c3e4b4 `
  "$B\mmdhl_robin" "Robin (Model Hotloader + RTX PBR)" "Robin" "SheepyLord" "$B\description.txt" `
  --default-preset-name Default

# two characters in one package:
python -I scripts\mmdhl_pack.py <cache> cf3eec2f "$B\mmdhl_evernight_march7th" "<title>" "Evernight" "SheepyLord" `
  "$B\description.txt" --item "e2c25f9e=March 7th"
```

## Arguments

| Argument | Meaning |
|---|---|
| `cache` | `<game root>\garrysmod\data\mmd_hotloader` of the install that holds the import. Read only |
| `asset` | the model's asset id: 64 hex digits or a unique prefix of 8 or more (`rpai` keys end in the first 8) |
| `out` | the add-on folder to write. Name it `mmdhl_<name>`, lowercase ASCII, the character's name only. Must not exist |
| `title` | the package title Model Hotloader shows; at most 128 bytes: `<Name> (Model Hotloader + RTX PBR)` |
| `name` | the model's display name in the library; at most 100 bytes. The character's own name in plain ASCII (`Robin`, `Chisa`): Model Hotloader shows English readers the PMX's English name instead of a non-ASCII one |
| `author` | at most 128 bytes |
| `description_file` | UTF-8 text (a BOM is fine), at most 8000 bytes |
| `release_json` (optional) | JSON with `release` and `build` for the manifest's `generator`. Default: `<game root>\garrysmod\lua\bin\mmdhl-native-release.json` beside the cache, which the loader deploys from the RTX package (its record in this repository, `packages\model-hotloader\bin\mmdhl-native-release.json`, says 2.3.1, build `1e4cb10d1a76-20261105T224511Z`, on 2026-11-08; the 2026-10-31 installs had `ecd7c426c0b5-20261026T225907Z`). Installers do not check it |
| `--item ASSET=NAME` | another character in the same package (repeatable) |
| `--tag TAG` | `addon.json` tag, at most two of GMod's (default `cartoon`) |
| `--default-preset-name NAME` | rename the library's default bodygroup preset (only that one). The environment variable `MMDHL_DEFAULT_PRESET_NAME` does the same (the Robin session's form) |
| `--replace` | replace an earlier package folder at `out` (refused for any other folder) |
| `--allow-game-install` | allow `out` inside a game install. Only when the user asked for that |

## Names (refused before anything is read or written)

The user's rule (2026-11-08): a model's recorded name is the character's own name only. Before it
touches the cache, the script passes the title, the item name, every `--item` name, the default
preset name (`--default-preset-name` or `MMDHL_DEFAULT_PRESET_NAME`) and the `out` folder's name
through [model_names.py](model_names.py.md). A game or franchise tag (`鸣潮-千咲`, `HSR Robin`,
`[Arknights] Texas`), a version or edition tag (`阿芙2.0`, `Alf 合体7`, `Furina v2`), an author tag
(`by_mobius`, `Tda式`), a rating or format tag (`Robin R18`, `New MMD Model`), a pack word in an item
name (`Chisa RTX`) or such a tag in the folder name (`mmdhl_robin_r18`) ends the run with exit 1 and
one `error:` line per name on stderr. Give the character's name as the user uses it (`Chisa`,
`Guinaifen`, `Alf`).

## What it reads

Per character, from the cache: `assets\<id>\manifest.json` and `model.bin`, every
`textures\<sha256>.png` the manifest's materials name (`base`, `sphere`, `toon`), the library entry
`library\<id>.json` (spawn settings and bodygroup presets; required), and when present
`terms\<id>.json`, `fit_overrides\<id>.json` and `arms\<id>.json`. That is the file set Model
Hotloader's exporter takes (`sharedManifest(..., sourceOnly=true)`): generated archives such as
`materials-v5.gma` are never shipped, every player's game rebuilds them.

## What it writes

Only `out` (built as `<out>.partial-<pid>` beside it, then renamed into place):

- `addon.json`: `{"title", "type": "model", "tags", "ignore": []}`;
- `data_static\mmdhl\packages\<32 random hex>.json`: the package manifest;
- `data_static\mmdhl\files\<sha256>.dat`: one MMDPACK2 packet per distinct file (textures that
  several models share are stored once).

Every packet is unpacked again with Windows' `Decompress` and compared with the file's SHA-256 before
it is written. Settings are reduced as Model Hotloader reduces them: presets written as a JSON array
(`util.TableToJSON` does that for presets named `"1"`, `"2"`) become named presets, the default becomes
a string, the terms record keeps the keys and limits of `terms.lua` (`ForPackage`), a fit loses who
saved it, arm parts are cleaned as `CleanArmsParts` does. Inputs are checked against the exporter's
and installers' limits (texts, tags, 4 MiB manifest, per-file and 16 GiB total limits).

Output: one line per character, a `bodygroups:` line, one line per packed file
(`<sha256 prefix> <raw bytes> -> <packed bytes>`), notes, and a JSON summary last (`package`, `files`,
`blobs`, `raw`, `packed`, `folder`, `generator`, `items`).

## Side effects and safety

- Writes nothing but `out`. Refuses an `out` inside the cache, or inside a game install (a folder with
  `garrysmod\` and `gmod.exe`) unless `--allow-game-install`.
- Each run makes a new random package id, as Model Hotloader's exporter does. Harmless for players.
- Windows only (`cabinet.dll`). Runs with `python -I` (standard library only); it puts its own folder
  on `sys.path` for `model_names.py`.

## Exit codes

0 built; 1 refused or failed (a tagged name, or another reason, on stderr; nothing left behind);
2 bad command line.

Tests: [test_names.py](test_names.py.md) (the name refusal; packing itself was verified by hand, below).

## Verified (2026-10-31)

- Rebuilt Robin's published package from the classic install's cache (asset `f9c3e4b4`,
  `--default-preset-name Default`): all 46 `.dat` files byte-identical to `out\packages\robin\mmdhl_robin`,
  the manifest identical apart from `id` and `created`.
- Built Evernight and March 7th from the field cache (`cf3eec2f` and `--item e2c25f9e=三月七`): all 47
  packets byte-identical to the ones Model Hotloader's own exporter wrote for item 3830769477, and the
  manifest's `items`, `files`, `title`, `description` and `generator` identical. Only the key order
  differs (the exporter sorts keys), which no reader cares about.

## Provenance

Written for this user by Claude in the Guinaifen session (2026-10-29), extended in the Robin session
(2026-10-30: preset arrays, `MMDHL_DEFAULT_PRESET_NAME`, the release file), tidied for this skill
(2026-10-31: option parsing, asset prefixes, `--item`, arm parts, terms limits, input limits, atomic
output, `--replace`, the game-install guard); the name refusal added 2026-11-08. Not third-party code.
