# The library window adds rows for new characters (report)

Claude, 2026-11-21, on the branch `claude/gallant-lumiere-af7670` (the session's worktree under `<repo>\.claude\worktrees`;
the loader build, the gate and the PoC runs in the worktree `<repo>\out\worktrees\hlrows`, branch
`hotloader-library-rows`, with the same files). Package only: the Model Hotloader part's `ui.lua` and `library.lua`; no
loader (`winmm.dll`), runtime or native change. Decision:
[ADR 0258](../decisions/0258-the-library-window-adds-rows-for-new-characters.md).

**Base: ADR 0255 is not on `main` yet.** The branch starts from `main` at `9085be02` with the uncommitted state of
`<repo>\out\worktrees\packi` (branch `pack-install-speed`, [ADR 0255](../decisions/0255-workshop-models-install-several-at-once.md))
brought onto it as one commit, `3a04cfd2` ("Base: pack-install-speed's uncommitted state (ADR 0255) on main
9085be02"): packi's files copied, the shared docs and `tools/ci/pins.json` merged three ways with both sides kept. This
work is the commit after it. Land ADR 0255 first; see "For the main thread".

## The task

The follow-up ADR 0255 left (the pack-install session's request of 2026-11-21): with the spawn menu open on the Model
Hotloader's tab, every library update of a content pack's install made the library window rebuild its whole list, a
frame of 52-59 ms with the user's library of 220 characters, five times for a pack of twelve. Make the window add the
rows of newly added characters instead, when the only change since its last rebuild is entries added through
`library.Add`, and keep the order, the folder filter, the search, badges, tooltips, the selection and the counts exactly
as a rebuild shows them; anything else still rebuilds.

## What was found

Facts with file and line references: [RESEARCH](../RESEARCH.md), "The library window's list: what an update costs".

- **What a rebuild makes again.** `PANEL:Refresh` clears the `DListView` and makes every row again: a
  `DListView_Line` with two `DListViewLabel` columns (eight `vgui.Create` calls a row, each merging its control table
  into the panel), a tooltip, a badge and fonts, about 1,760 `vgui.Create` calls for 220 rows, then the layout of the new
  rows and the removal of the old ones.
- **The pack's characters are already in the user's library.** All twelve models of the pack (eleven characters and a
  static prop) have asset folders in the field install's library, so the PoC runs with `--seed-library` install them
  over entries the library has (a takeover: the package's settings and a Workshop origin), as the user's own game does.
  The first form of this change rebuilt the list for an update that listed an entry the library already had; the first
  after-run (`after1`) therefore still rebuilt at every update. The final form dresses those rows again.
- **A hidden window does not update, and the spawn menu can close itself.** Sandbox's spawn menu closes on a click on
  its background. In `after1` the window stopped updating 14 s into the install while another session's A/B capture
  drove the field game's window. The probe now keeps the spawn menu open and logs when the window is shown or hidden;
  no close happened in the later runs.
- **The folder tree was rebuilt at every update.** A package's node shows its count of models, so every update of an
  install changed the tree's signature and made its twenty-odd nodes again (about 330 `vgui.Create` calls): most of
  `AddRows`'s cost in `after3` (up to 16 ms). The tree now relabels those nodes when only the counts changed.

## What changed

- **`library.lua`**: `library.Add` records the ids it listed, each once, under the revision it made
  (`library.added`, the last sixteen revisions); `library.Refresh` clears the record.
- **`ui.lua`**: the row code is shared by `Refresh` and the new path (`FolderShows`, `RowItem`, `AddRow`, `DressRow`,
  `rowColumns`, `rowBefore`, `rowMatches`, `ShowCount`, `NothingChosenText`). `Refresh` notes what the list was built
  from (`self.built`, with the entries the folder's total counts). On a revision change `Think` asks `AddedSince`; when
  every revision since was one of `library.Add`'s and the tab, folder, search, translated names, rows and the list's own
  order are as `Refresh` left them, `AddRows` makes new rows, dresses again the rows of entries listed again, moves each
  to where a rebuild's sort puts it in `DListView.Sorted` (`placeRow`, binary search), keeps the total, the count line,
  GUI Scaler's mark and the details (the chosen entry's again through `Choose` when it was listed again) and leaves the
  selection alone. A row that would have to go builds the list again, as does anything else; a click on a column
  header (`SortByColumn`) drops `self.built`. `RefreshFolders` relabels the Workshop packages' nodes when only their
  counts changed.
- **Tools**: [`pack_install_session.py`](../../tools/qa/pack_install_session.py.md) runs a branch's `ui.lua` too with
  `--hotloader-lua`, leaves a field game another task's test uses running with `--keep-field-game`, and prints the
  library's revisions and the window's updates; [`pack_install_probe.lua`](../../tools/qa/pack_install_probe.lua.md)
  times `AddRows` beside `Refresh`, lists each update of the window with its frame and the next (`library_updates`),
  logs each library revision and the window shown or hidden, and keeps the spawn menu open while it runs.

## Measured

PoC, gm_construct at 1600x900, `pack_install_session.py` with the pack of ADR 0255's report
(`<modding>\ipg\genshin_pbr\genshin-impact-rtx.gma`, the same file as ADR 0255's last runs) and ADR 0255's RTX package
(`out\packi\pkg\gmod-rtx-remix-0.0.0-dev.20261122035639_7415012b.gma` in packi's worktree), `--seed-library` with the
field install's `data\mmd_hotloader` (222 characters' manifests, 220 settings files, 22 props, read only),
`--spawnmenu`, and each branch's `library.lua`, `workshop.lua` and `ui.lua` run over the package's with
`--hotloader-lua`: before = packi's files, after = this branch's. The window's updates during the install only (the
spawn menu's opening, a rebuild in both, left out):

| Runs | Window's updates | Time in the window's call | Update frames | Next frames | Median install frame |
|---|---|---|---|---|---|
| `before3`, `before4` (no other game) | 6, each a full rebuild | 18.0-30.5 ms | 41.5-62.8 ms | 18.2-39.2 ms | 10.4-11.6 ms |
| `after3` (no other game; tree rebuilt for each count) | 4, rows | 3.6-16.3 ms | 23.3-47.3 ms | 11.7-21.8 ms | 11.8 ms |
| `after4` (no other game; final code) | 3, rows | **1.4-6.9 ms** | **18.8-22.6 ms** | **10.3-14.8 ms** | 10.9 ms |
| `before2` (a field game beside it) | 4, each a full rebuild | 22.7-66.5 ms | 43.1-89.9 ms | 20.0-25.3 ms | 13.1 ms |
| `after2` (the field game gone; tree rebuilt for each count) | 3, rows | 4.8-12.0 ms | 20.4-33.6 ms | 11.5-23.5 ms | 10.3 ms |

`vgui.Create` ran about 13,400 times in `before3` and `before4` and 8,000-8,700 times in `after3` and `after4`. Every
`after` update listed one to four characters, each one the library already had; the static prop went through the
props library's own rebuild. The installs took 11.5-12.9 s in pairs 2-4. ADR 0255's own measurement (`fix4`, the
same setup) had five rebuilds of 52-59 ms.

The first pair (`before1`, `after1`) ran beside a field game that another session's A/B capture drove; `after1` used
the first form of this change (an entry listed again rebuilt the list), and its window stopped updating after 14 s.
Evidence: `<repo>\out\worktrees\hlrows\out\hlrows\` (`before1`-`before4`, `after1`-`after4`; each
`<run>\bigmenu\results\result.json` with `library_updates` and its events, and `frames.csv`). No run ended a game:
every run used `--keep-field-game`; a field game that another session's test used ran beside pair 1 and `before2`
and had ended by `after2`. The first pair's installs took 19-21 s beside it.

## Tests

- [`test_hotloader_library_rows.py`](../../tools/tests/test_hotloader_library_rows.py.md) (new) with its LuaJIT harness:
  the shipped `library.lua` and `ui.lua` with Derma instrumented; nine scenarios compare the window that took the
  updates with a window built afresh, row by row (`record`, `rows_like_a_rebuild`, `views`, `empty_view`,
  `multi_selection`, `listed_again`, `rebuilds`, `gui_scaler`, `random`: 150 random libraries, 234 updates as rows and
  33 that had to rebuild). The incremental scenarios fail on ADR 0255's window, and 22 deliberately broken copies of
  the two files (no placement, no total, no folder tree, no search, rows of entries listed again not dressed or not
  moved, the chosen entry's details not refreshed, a row kept that must go, the tree always rebuilt or relabelled for
  any change, and so on) each failed a scenario.
- The existing Model Hotloader tests (`test_hotloader_*.py`, among them ADR 0255's `test_hotloader_workshop_install.py`
  and its `library_add` scenario) pass unchanged.
- The gate, `tools\test.ps1 -Config Release` in `out\worktrees\hlrows` on the final state: repo conventions OK, CTest
  35 of 35, Python 2,190 of 2,191 (two skipped). The one failure is ADR 0255's `test_hotloader_workshop_install`
  scenario `failures` ("the failed model counted"), which fails about one run in seven whichever `library.lua` it loads
  (40 runs each with packi's and with this branch's: 6 failures each): its harness assumed an order that LuaJIT seeds per
  run, and the main thread has fixed it on its integration branch. The first gate run also found this work's decision
  index row without its status column (`test_vr_review_docs`), fixed since.

## Open items

- **Translated names still rebuild.** With translation allowed, a new model with a non-ASCII name is sent for
  translation when its row is first shown; the answer changes `mmdhl.names.revision`, and the window builds its list
  again (as it did). The pack's characters have English names.
- **The props tab** still rebuilds for every update: its library has no `library.Add`, and installed props go through
  its rebuild (ADR 0255 left it so).
- A takeover that moves a model out of the folder the window shows builds the list again (rows are never removed
  alone: `RemoveLine` leaves a hole in the list's lines).
- Not tried: the field install, a multiplayer game (server-approved models reach the library by full rebuilds, as
  before), GUI Scaler in a game (its mark is checked under LuaJIT only).

## For the main thread

- This work lands after ADR 0255 (`pack-install-speed`), whose uncommitted state the branch's base commit `3a04cfd2`
  holds; relative to that state the whole change is `git diff 3a04cfd2` in this branch's worktree. The main thread
  commits, merges and publishes it (the user approved landing it right after `pack-install-speed`, with the DLib and
  ULib pair).
- `packages/model-hotloader/files.json` was re-indexed for `ui.lua`, `library.lua` and `ui.lua.md`
  (`tools\inputs.py import model-hotloader --file ...`; `verify`: 0 problems). A commit on `main` publishes the Workshop
  item.
- The decision record is 0258, as the main thread numbered it: 0256 and 0257 go to the DLib and ULib work.
- At the merge (the main thread, 2026-11-21): it landed right after ADR 0255, with the DLib and ULib work (ADR 0256,
  ADR 0257); AGENTS.md's status line and its "latest is" chain name it.
