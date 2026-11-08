# model_names.py

The **naming rule** for characters, their packs and their records, as code (the user, 2026-11-08):
a model's recorded name is the character's own name only, as the user uses it (`Chisa`, `Guinaifen`,
`Alf`, `March 7th`). No game or franchise tag, no version, build or edition tag, no author or
uploader tag, no rating or format tag.

It is a module, not a command. The scripts that take or derive a name import it and refuse a name it
flags before they write anything (exit 1, the reason on stderr): `mmdhl_pack.py`, `pbr_mod.py` and
`check_pack.py` here; `hotloader_export.py`, `stage_pbr_mod.py` and `package_characters.py` in the
mmd-remix-pbr skill, which keeps an identical copy of this file (`test_names.py` fails when the two
differ). Change both copies together.

```python
import model_names
model_names.find("鸣潮-千咲")          # ["game tag '鸣潮'", "<prefix>-<name> folder form '潮-千'"]
model_names.find("Chisa")              # []
model_names.refusal("item name", "阿芙2.0")   # one line for stderr, or None when the name is clean
```

## What it refuses

| Kind of tag | Matched (after Unicode NFKC folding and lower-casing) | Examples |
|---|---|---|
| game or franchise | a known game's Chinese, Japanese or English name anywhere (`GAMES_CJK`), or its English name or abbreviation as whole words (`GAMES_LATIN`) | 鸣潮, 星穹铁道, 原神, 崩坏, 明日方舟, 终末地, 白银之城, 异环; Wuthering Waves, WuWa, Honkai, Star Rail, HSR, Genshin, Arknights, Endfield, ZZZ, Silver Palace |
| `<prefix>-<name>` folder form | two non-ASCII runs joined by `-`, `_` or a dash (`‐ ‑ ‒ – — ― −`); the middle dot (阮·梅) and the long-vowel mark (ー) are not separators | 鸣潮-千咲, 星穹铁道-桂乃芬, 库拉蒂—骑士 |
| version or edition | dotted numbers; `v`, `ver`, `version` before a digit (not after a Latin letter); 合体/合體 and a number; `<n>版`, 版本, 第…版/代, 周年; a number right after a non-ASCII name; a lone number after a Latin word | 2.0, 1.0.3, v2, Ver.3, V4X, 合体7, 千咲2, Robin 2 |
| author or uploader | the word `by` (also `1.0by_x`), `@`, 作者, 配布, 改模, 模型, 制作, 製作, 改変, a Latin or digit before 式 | by_mobius, By Alicia, Tda式 |
| rating or format | `R18`, `R-18`, `18+`; the words MMD, PMX, PMD, NSFW | Robin R18, New MMD Model |
| bracketed | any `[ ]`, `【 】`, `〔 〕`, `《 》`, `「 」`, `『 』`, `〖 〗`, `〘 〙` | [Arknights] Texas, 【原神】 |
| pack words (kind `name` only) | RTX, PBR, Remix, Hotloader, Workshop, pack, package, model, addon | Chisa RTX |

Round brackets are not a tag by themselves: `Guinaifen (桂乃芬)` passes (her name in Chinese), while
`Chisa (WuWa)` fails on the game tag inside.

## Kinds

| `kind` | For | Checks |
|---|---|---|
| `name` (default) | a Model Hotloader display name (`<item name>`, `--item ASSET=NAME`), a package's character name | everything above |
| `title` | a title, a label, a bodygroup preset name, a `mod.usda` doc string | everything but pack words, so `Chisa (Model Hotloader + RTX PBR)` passes |
| `slug` | a folder name or package id: `mmdhl_<n>`, `pbr_<n>`, `<n>-rtx`, an export file name | the `mmdhl_`/`pbr_` prefix and the `-rtx` suffix are dropped and `_`/`-` read as spaces; `2_0` counts as a version |
| `prose` | a description | game and franchise tags only (a description may name loader versions or say "made by") |

It does not judge ASCII: a non-ASCII display name is refused by `check_pack.py` (the earlier rule,
2026-10-31), only advised against by the packers.

## Limits

A game the lists do not name passes, unless its name sits before a dash as a CJK folder prefix. Add
it to `GAMES_CJK` or `GAMES_LATIN` in both copies, with a case in `test_names.py`. A real name that
looks like a tag (a character called `V2`) is refused; that has not happened yet.

## Inputs, outputs, side effects, exit codes

Pure functions over strings: no files, no network, no side effects, no exit codes of its own.
Standard library only; imported by scripts that run with `python -I` and by the rpai venv's Python.
Tests: [test_names.py](test_names.py.md).
