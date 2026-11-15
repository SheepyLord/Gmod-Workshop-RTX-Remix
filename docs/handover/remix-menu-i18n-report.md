# The Remix menu's newest texts translated: report (2026-11-15)

The user's go-ahead of 2026-11-15, "Yes, please translate them", for the finding of the night sky editor's build (runtime
patch 0099): the fork's translation catalogs for the Remix menus (Alt+X) were behind its sources, so 98 menu texts
showed in English in Simplified and Traditional Chinese, Japanese, Korean, French and Russian. Done by Claude on the
branch `remix-menu-i18n` (worktree `out\worktrees\mi18n`, from `main` at `89ff6c74`): runtime patch 0100 (fork branch
`claude/remix-menu-i18n`), catalogs only; no loader (`winmm.dll`) or package code change. Facts in
[RESEARCH.md](../RESEARCH.md) ("The Remix menu's catalogs after the upstream merge").

## What was missing, and why the build did not say so

The upstream merge of 2026-11-14 (runtime patch 0093, fork commit `20e3553eb`) brought 98 menu texts: the water
simulation and its sludge (56), RTXDI's best-light jitter and sparse neighbour candidates (14), the post effects'
colour inversion (10), the eye's iris depth scale, limbal ring and roughness (5), the dissolve of alpha-blended draws
(5), the particles' spawn distribution (4), the world-space skinned bones checkbox (2) and the displacement's
silhouettes behind translucency (2). The build's `i18n/tools/embed.py` checks the catalogs against `remix.pot`, and
nothing regenerates `remix.pot` but `i18n/tools/update_strings.py`, so the build passed with the texts in English.

## What changed

**Runtime patch 0100** (`Translate the Remix menus' 98 new texts (zh-CN, zh-TW, ja, ko, fr, ru)`, fork branch
`claude/remix-menu-i18n` at `25c85588` on 0099's `1dd38dbf`):

- `update_strings.py` regenerated `remix.pot` (3,452 messages) and merged it into the six catalogs. The 98 new texts
  are translated in every language, keeping to each `i18n/glossary/<language>.md`; the terms this batch settled (the
  water's sludge, ripples, wind waves, swell, gusts and droplet rings, the dissolve and its ramp, the limbal ring, the
  colour inversion's negative) are added to each glossary. The 16 entries (18 in zh-CN) whose English left the
  sources moved to the end as obsolete `#~` entries, as the tool keeps them; the other entries' references moved to
  their current source lines, which is most of the patch.
- The translations are agent-written (Claude), not reviewed by a native speaker.
- No code: the menus' translator (`rtx_fork_i18n.cpp`) and the fonts are unchanged; the fonts already had every
  character the translations use.
- Built by `build_runtime.ps1` (0001-0100) in `out\worktrees\r17\out\runtime-src`: `d3d9.dll` 479,855,616 bytes,
  SHA-256 `2c157ebe717182bb4bd2b8305fe0fbed29a09c0d36b84f78be6d7415e54290ab` (70,817,488 bytes with xz).

## Checks

- `python i18n/tools/update_strings.py --check`: exit 0, `remix.pot` matches the sources.
- `i18n/tools/embed.py` (the fork README's arguments): `3452 messages; translated: zh-CN 3452/3452, zh-TW 3452/3452,
  ja 3452/3452, ko 3452/3452, fr 3452/3452, ru 3452/3452`, exit 0; it checks each translation's characters against the
  fonts and its printf conversions against the English.
- `python -m unittest discover -s i18n/tools -p test_embed.py`: 5 tests, OK.
- A scratch check before writing (`out\tmp\i18n`): the 98 rows are exactly the catalogs' untranslated texts, no
  translation is blank, line breaks and printf conversions match, and each language's punctuation and spacing rules
  hold (no issues).
- The built `d3d9.dll` holds all 98 new texts in English and in each of the six languages, each translation under its
  message's index in the form `embed.py` stores it (588 of 588 found; `out\tmp\i18n\check_dll.py`).

## In the PoC

RTX 5090, 1280x720, gm_construct, frame generation 3x; `out\tmp\i18n\menu_lang_probe.lua` set
`rtx.gui.logUntranslatedText`, then for each language `rtx.gui.language` with the developer menu (`rtx.showUI` 2) and
the graphics settings window (1) open, a screenshot of each, and English and the menu closed at the end (nothing
saved, so `user.conf` untouched). Evidence in `out\qa-poc\remix-menu-i18n`; both runs exited 0 and quit normally.

- **The branch's package** (`0.0.0-dev.20261115222500+8c409360`, `01-menu`): the Remix log reads `menu language:
  <code>, 3452 translated texts` for each of the six and rebuilds the font atlas (zh-CN 4,032 glyphs, zh-TW 4,038, ja
  3,342, ko 2,679, fr 450, ru 546); **no `[i18n] untranslated` line** in any language. The screenshots show both
  windows translated, without missing glyphs.
- **The published package** as a control (`0.0.0-dev.20261115182304+8aafd13e`, `02-control-published`, the same
  probe): `3360 translated texts`, and in every language `[i18n] untranslated (<code>): "Water Simulation
  [Experimental]"`, the developer menu's header below the visible part of the Rendering tab (measured each frame even
  off-screen). So the logging works when set from Lua, and that header showed in English before this patch.
- Not opened: the sections inside the closed headers (the water simulation, RTXDI, the post effects, the eye, the
  particles, the alpha blending), which automation cannot open (clicks do not reach the menu); their texts are
  checked in the catalogs and in the DLL.

## What is left

- The build still does not notice new menu text after a merge: `update_strings.py --check` has to be run by hand.

## Gate

`tools\test.ps1 -Config Release` on the branch: "All checks passed" (C++ 35 of 35; Python 2,019 tests in `tools`, 1
skipped, 29 in `gmapack`, 26 in `steam`); `check_repo.py` again after the PoC paragraphs: repo conventions OK.
