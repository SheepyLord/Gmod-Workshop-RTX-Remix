# The package says when the disk is too full for updates (2026-11-22)

The user's request of 2026-11-22:

> Please delete them. Also, during installation, when the payload is being unpacked, there might be risk that the
> user's disk is nearly full and a full disk will cause a failure. Without modifying the loader, try to handle this
> situation

("Them": the 213 built files of the earlier format that the [previous round's report](mmd-shared-builds-report.md)
named.)

Done by Claude on the branch `disk-space-notice` (worktree `out\worktrees\diskfull`, from `main` at `b14a21cc`).
Package only: the companion's new menu script `nativeloader/menu/disk_space.lua` and its translations, the RTX client
module's menu API (`loader/client`: `disk_space.cpp`, `module.cpp`; `gmsv_nlrtxclient_win64.dll` ships in the fixes
part, as for [ADR 0246](../decisions/0246-the-directx-level-servers-see.md)), the render guard's list of the package's
Lua, the translation tool's units, and `poc_session.py --menu-console` for the tests. No loader (`winmm.dll`) change.
Decision: [ADR 0260](../decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md); facts with file and
line references: [RESEARCH.md](../RESEARCH.md) "The loader on a full disk".

## The built files of the earlier format

In the field install's `garrysmod/data/mmd_vmd_npc/built`, the 213 files not ending in `_fm2.json` were each read
first (all `"format":"mmd_vmd_npc_built_v1"`, which the animation player refuses) and then moved to the Recycle Bin:
1.90 GiB, back on the drive once the Recycle Bin is emptied. The 73 files of the current format stay.

## What a full disk did before

The loader was already safe on a full disk. At each start it checks the space before it unpacks: the new files (a new
version's payload folder whole and the other files that changed) must fit with 64 MiB to spare, or it stops before
anything in place changes. A write that fails while it unpacks or moves (Windows error 112 or 39) stops it too, and
what it did is undone; the next start removes the staged files first. The game then runs the versions installed
before. Nothing is ever left half installed.

What it did not do is tell the player: the refusal was in `garrysmod/data/native-loader/status.json` and the loader's
log only, the loader shows no window for it, and the update was tried again, and refused again, at every start, while
the Workshop item showed the new version and the game ran the old one.

In the user's game (its journal, read only): 25 deployed packages, 57.7 GiB. The RTX package unpacks its payload
folder whole for each new version (1.36 GiB, and the previous one is kept for a rollback) and its other files when they
changed (0.80 GiB); each map content pack holds 3.5-3.65 GiB.

## What changed

- **The RTX client module measures**: `disk_space()` in its menu API (menu realm only) answers the free and total
  bytes of the drive that holds the game folder, read when asked with `GetDiskFreeSpaceExW` as the loader reads them,
  the drive's letter, and each package of the committed generation with the bytes of its payload folder and of its
  other files (from the journal the module already reads at its verification).
- **After a start whose updates did not fit**, a card at the main menu says what the new files needed, what the loader
  keeps free and what was free (or that the drive filled while it unpacked), that nothing changed, and how much to free
  on which drive. It shows at every such start.
- **Before it happens**, a card when the drive has less free space than the largest deployed package would need to
  unpack again, plus the loader's 64 MiB and 512 MiB for the game's own caches and logs. It has **Don't show this
  again**; a failed update is always shown.
- **The text** is in the companion's six languages; sizes as Windows shows them (tenths of a GB, whole MB), the units
  translatable.

| Card | When | What it says | Amount to free |
|---|---|---|---|
| Not enough disk space to install updates (refused) | `deployment.outcome` `failed` with the loader's "not enough free disk space: ..." | needed, kept free, free; nothing changed | needed + 64 MiB - free + 512 MiB |
| Not enough disk space to install updates (full) | `failed` with Windows error 112 or 39 | the drive ran out while unpacking; nothing changed | what the warning wants - free (or "some space" without the module's measure) |
| Little free disk space for updates | free < largest package + 64 MiB + 512 MiB | free, the largest package's size, why | the difference |

Console commands at the main menu: `nativeloader_disk_space` (the card that applies, or "no card: there is space for
updates"), `nativeloader_disk_space_status` (the numbers), `nativeloader_disk_space_reset` (the warning back after Don't
show this again), `nativeloader_disk_space_preview need|full|low` (each card with sample numbers, the real state left
as it was).

## What it does not cover

- **A first installation that does not fit** shows nothing in the game: nothing of the package is deployed, and GMod
  cannot mount the item itself ([ADR 0015](../decisions/0015-workshop-route-for-native-packages.md)). Only the loader's
  report and log say it. Only a loader change could show it, and the loader stays as it is (the user's rule).
- **The warning's estimate** is conservative and approximate: an update unpacks a payload folder whole, but other files
  only when they changed, and a new subscription is not counted. The loader's own check decides; the warning says only
  that it may refuse.
- **An older RTX client module** (without `disk_space`) gets the failure card only, its drive taken from the runtime
  folder in `status.json`.

## Checked

- **C++** ([loader/client/tests](../../loader/client/tests/README.md) `test_disk_space.cpp`, 4 tests, new): a package's
  payload folder and its other files summed apart (a payload path in other letter case counted in, a sibling folder
  with the same prefix not, a package the generation does not list left out, a duplicate id once); sizes saturate
  instead of wrapping around; the drive's free space for the current folder, and nothing for a volume that does not
  exist; `module.cpp` registers `disk_space` in the menu API only and fills the footprints at its verification.
- **LuaJIT** ([test_disk_space_notice.py](../../tools/tests/test_disk_space_notice.py.md), 10 tests, new): the shipped
  `disk_space.lua` in a mocked menu realm ([disk_space_harness.lua](../../tools/tests/disk_space_harness.lua.md), 8
  scenarios): the refusal's card with its numbers and amount to free, the full disk's card, the warning and its Don't
  show this again (the cookie, the reset command, a failure card shown anyway), nothing when there is space, an older
  module's failure card, nothing for other failures or outside the menu realm, the previews leaving the real state, the
  cards in another language; the script compiles; and the loader's wording, which the script reads, is pinned to
  `deploy.cpp` and `fs.cpp`.
- **Translations**: `tools\companion_i18n.py check` passes (799 strings in each of the six languages); the twelve new
  strings keep their `%s` order. The update also refreshed stale source line references in the catalogs.
- **PoC, a real RTX start** ([disk_space_session.py](../../tools/qa/disk_space_session.py.md), evidence in
  `out\diskfull-poc\run1`): the module's measure at the main menu, "drive H: has 137614 MiB free of 1907729 MiB;
  largest package gmod-rtx-remix: 2216 MiB; wanted free 2792 MiB; last deployment deployed" (Python had read 139846 MiB
  free before the run, which then deployed the 2.2 GB package), no card (enough space), the RTX menu module with seven
  menu scripts; the three previews' screenshots at 1920x1080: each card's text wrapped inside it, its amounts rounded up,
  the warning's two buttons side by side.
- **PoC in Japanese** (`out\diskfull-poc\run2`, then `run3` after the fix below; `--language ja`, 1600x900): the
  refusal's card and the warning in Japanese, their lines broken between characters inside the card, the buttons 了解
  and 今後表示しない side by side. In `run2` one line ended between "2.3" and "GB"; a size's number and unit are now
  joined by a no-break space, and in `run3` "2.3 GB" moves to the next line whole, the no-break space drawn as a space.
- Not covered: a real refusal in a game (the loader's own check is the loader's tests'; the card reads its report,
  tested under LuaJIT with the loader's own words), the field install (rule 1), and a 4K screen (the card scales by the
  screen height, as the companion's other notices).

## Files

- `companion/nativeloader/lua/nativeloader/menu/disk_space.lua` (new) and its `.md`;
  `companion/nativeloader/lua/autorun/_nativeloader_guard.lua` (the new path among the package's own Lua).
- `companion/i18n/*.po`, `nativeloader.pot` (the twelve strings), `companion/i18n/addons/*` (line references only);
  `tools/companion_i18n.py` (`%s GB` and `%s MB` may stay as they are).
- `loader/client/disk_space.h`, `disk_space.cpp` (new), `module.cpp`, `CMakeLists.txt`, `README.md`;
  `loader/client/tests/test_disk_space.cpp` (new), `CMakeLists.txt`, `README.md`.
- `packages/fixes/modules/gmsv_nlrtxclient_win64.dll` (rebuilt, `repo_builds.py refresh`), `packages/fixes/files.json`,
  `tools/ci/pins.json`.
- Tests: [disk_space_harness.lua](../../tools/tests/disk_space_harness.lua.md),
  [test_disk_space_notice.py](../../tools/tests/test_disk_space_notice.py.md) (new).
- QA: [disk_space_session.py](../../tools/qa/disk_space_session.py.md) (new),
  [poc_session.py](../../tools/poc_session.py.md) (`--menu-console`).
- Docs: ADR 0260 and its row, CHANGELOG, ROADMAP, RESEARCH, TESTING, AGENTS.md, this report and its line in the
  handover index.

## Published

`tools\test.ps1 -Config Release` passed on the branch (35 native tests; 2,212, 29 and 26 Python tests; "All checks
passed"), after one fix the first run asked for: three `test_poc_session.py` tests build `step_run`'s arguments
themselves, without the new `menu_console`, which `poc_session.py` now reads with a default (and a new test sends two
menu commands with their screenshots). `origin/main` had not moved from `b14a21cc`, so `main` was fast-forwarded to
`e4f0beca` and pushed. The merge's hook uploaded item 3829070317 as **0.0.0-dev.20261123002706+24c6839a**
(2,325,115,036 bytes, SHA-256 `7be418f8c601201ec946ee8fbe6659e836243027ca4f841a346d2785a830a356`, content digest
`34a86584...`) at 2026-11-23 00:27 UTC, with one change note of 2,139 characters: the version line and this round's
changelog entry (ADR 0222). The push's hook found the same inputs and uploaded nothing.

## Notes and open questions

1. The 512 MiB margin beyond the loader's own 64 MiB is a choice (the game's caches, logs and shader caches grow at
   run time); the warning's threshold for the user's game is about 4.2 GB, set by the largest map pack.
2. The field install was not run in a game (rule 1); its drive has far more free space than any card asks for, so it
   shows nothing there unless a command previews one.
3. A first installation that does not fit stays silent in the game; a loader change offered for approval could show a
   window for it.
4. In Japanese, Windows' font linking behind Tahoma (`extended`, the companion's other menu notices use the same fonts)
   leaves uneven gaps between some characters ("インスト ール" in `run3`'s screenshots; the translation has no space
   there). The text is legible; a font chosen per language would draw it evenly, for every notice at once.
