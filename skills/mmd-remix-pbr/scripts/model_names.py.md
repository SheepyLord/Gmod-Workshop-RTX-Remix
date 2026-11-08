# model_names.py

The **naming rule** as code (the user, 2026-11-08): a model's recorded name is the character's own
name only, as the user uses it (`Chisa`, `Guinaifen`, `Alf`, `March 7th`), with no game or franchise
tag (鸣潮, 星穹铁道, 原神, HSR, WuWa, Genshin, `[Arknights]`), no version, build or edition tag (`2.0`,
`v1.2`, `Ver.3`, `合体7`), no author or uploader tag (`by_mobius`, `Tda式`) and no rating or format tag
(`R18`, `NSFW`, `MMD`, `PMX`).

This file is a byte-identical copy of `workshop-content-pack/scripts/model_names.py`, kept here so this
skill runs alone; that skill's `test_names.py` fails when the two differ, so change both together. The
full table of what it refuses is in
[the workshop-content-pack copy's notes](../../workshop-content-pack/scripts/model_names.py.md).

Used by [hotloader_export.py](hotloader_export.py.md) (title, export file name, `--out` folder, every
model's library name), [stage_pbr_mod.py](stage_pbr_mod.py.md) (`--dest` folder, `--doc`) and
[package_characters.py](package_characters.py.md) (each `--character` NAME): a tagged name ends the
run with exit 1 and the reason on stderr, before anything is written.

```python
import model_names
model_names.find("阿芙2.0", "name")      # ["version or edition tag '2.0'"]
model_names.find("pbr_robin_r18", "slug")  # ["rating tag 'r18'"]
model_names.refusal("--character name", "Robin")   # None: clean
```

Kinds: `name` (display names; also refuses pack words such as RTX or PBR), `title` (titles, labels,
doc strings), `slug` (folder names and package ids; `mmdhl_`/`pbr_` and `-rtx` are dropped, `_` and `-`
read as spaces), `prose` (descriptions: game tags only).

Pure functions over strings: no files, no side effects, no exit codes of its own. Standard library only.
