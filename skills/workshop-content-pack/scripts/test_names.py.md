# test_names.py

Unit tests (standard-library `unittest`) of the naming rule, [model_names.py](model_names.py.md), and
of every script that refuses a tagged name: [mmdhl_pack.py](mmdhl_pack.py.md),
[pbr_mod.py](pbr_mod.py.md) and [check_pack.py](check_pack.py.md) here, and, when the mmd-remix-pbr
skill sits beside this one, its `hotloader_export.py`, `stage_pbr_mod.py` and `package_characters.py`.

```powershell
Set-Location <skills>\workshop-content-pack\scripts
$env:TEMP = $env:TMP = '<repo>\out\tmp'      # in the repository: scratch stays under out\
python -I -m unittest -v
```

`python -I -m unittest` discovers `test_*.py` in the current folder and puts that folder on `sys.path`
itself, so the isolated interpreter finds the scripts.

## What it checks

| Class | Cases |
|---|---|
| `RuleTests` | 29 tagged names refused (`鸣潮-千咲`, `星穹铁道-桂乃芬`, `阿芙2.0`, `Alf 合体7`, `Robin R18`, `HSR Robin`, `[Arknights] Texas`, `Tda式初音ミクV4X`, `千咲2`, `Chisa RTX`, ...) and 30 plain names passed (`Chisa`, `March 7th`, `Guinaifen (桂乃芬)`, `阮·梅`, `A2`, `Jean-Luc`, ...); the reasons name the tag; titles keep the `(Model Hotloader + RTX PBR)` suffix but not tags; slugs (`mmdhl_robin_r18`, `alf_2_0`, `pbr_chisa_wuwa` refused; `evernight-march7th-rtx` passed); descriptions flag only games; an unknown kind raises; the two copies of `model_names.py` are byte-identical (skipped when mmd-remix-pbr is not beside this skill) |
| `PackerTests` | `mmdhl_pack.py` refuses a tagged item name, `--item` name, `--default-preset-name`, title and out folder with exit 1 and writes nothing; clean names reach its next check; `pbr_mod.py` refuses a tagged label or out folder, also with `--dry-run` |
| `CheckPackTests` | a tagged display name is an error, a warning with `--keep-name`; a plain one passes; tagged folder names and package id give three errors; a description naming a game is an error |
| `SiblingScriptTests` | `stage_pbr_mod.py` (tagged `--dest`, tagged `--doc`), `package_characters.py` (tagged NAME) and `hotloader_export.py` (tagged `--title`; a tagged library name read from a fixture install) exit 1 before writing, and the game bridge is never started |

## Side effects and exit codes

Writes only into temporary folders (`tempfile`, which honours `TEMP`), removed afterwards; no game,
network or real install is touched. Exit 0 when every test passes, 1 otherwise (unittest's own codes).
