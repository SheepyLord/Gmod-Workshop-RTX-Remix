# 0258: The library window adds rows for new characters instead of building its list again

- Status: Accepted 2026-11-21 (the follow-up [ADR 0255](0255-workshop-models-install-several-at-once.md) left open:
  with the spawn menu open, each library update of a content pack's install still rebuilt the library window's whole
  list)
- Package only: the Model Hotloader's `ui.lua` and `library.lua`. No loader change. Builds on ADR 0255's `library.Add`.

## Context

Since ADR 0255, the models a Workshop package installs reach the library through `library.Add`, a few at a time and at
most every four seconds; each call makes one library revision. The library window (`MMDHLLibrary` in `ui.lua`: the
spawn menu's External Models tab and the `mmdhl_open` window) compared its revision with the library's every frame
(`PANEL:Think`) and called `PANEL:Refresh` on any change. `Refresh` clears the list (`DListView:Clear`) and makes every
row again: a `DListView_Line` with two `DListViewLabel` columns each (every `vgui.Create` of a scripted panel merges
its whole control table into the new panel), a tooltip, the badge of where the model comes from and its fonts, then
lays them all out and removes the old ones.

Measured in the PoC with `tools/qa/pack_install_session.py` (the user's library of 220 characters copied in, the spawn
menu open on the Model Hotloader's tab; ADR 0255's report, run `fix4`): five library updates for a pack of twelve
characters, each a frame of 52-59 ms, of which `vgui.Create` took 17-23 ms and `Refresh` itself 6-12 ms; the rest was
the new rows' layout and the old rows' removal. The rows of the other 210 characters were made again each time.

`library.Add` also lists characters the library already has: a package's model with the same content as one the player
imported (the same asset id) takes it over, with the package's settings and a Workshop origin. That is the user's own
case as the author of the pack in the report, and the PoC measurement's: the library copied from the user's game
already held all of the pack's models (its eleven characters and its one static prop).

## Decision

1. **`library.Add` records what it listed** (`library.added[revision]={ids}`), each id once: new entries and entries
   listed again. The last sixteen revisions are kept; `library.Refresh` clears the record.
2. **`PANEL:Refresh` notes what the list was built from** (`self.built`: the library, the tab, the folder, the search,
   the entries the folder's total counts, the number of rows), and a row keeps its sort key (`row.item`).
3. **The listed entries' rows are brought up to date alone.** On a revision change the window asks `AddedSince`: when
   every revision since the list was built is one of `library.Add`'s, and the tab, folder, search, translated names,
   rows and the list's own order (no column header clicked: `SortByColumn` drops `self.built`) are as `Refresh` left
   them, it calls `AddRows(ids)`. That brings the folder tree up to date (`RefreshFolders`) and the folder's total (an
   entry listed again may join the folder or leave it). A new entry the search matches gets a row made by the same code
   a rebuild uses (`AddRow`: the same columns, tooltip, badge and fonts). An entry listed again that has a row gets its
   columns, tooltip and badge again
   (`DressRow`); one without a row that the search now matches gets a new row. Each new or changed row moves from where
   it is in the list's display order (`DListView.Sorted`; `AddLine` puts a row last) to where a rebuild's sort puts it,
   by binary search (`rowBefore`: favourites first, then the name, then the id, a strict order). New rows get GUI
   Scaler's mark (`ownScale`) as a rebuild's do; the count line follows, and the details too: those of the chosen entry
   when it was listed again (`Choose`, as a rebuild calls it), otherwise, with no row chosen, why the list is empty or
   to choose a row.
4. **The folder tree is relabelled when only a package's count changed.** `RefreshFolders` built the tree again whenever
   its signature changed, and a package's node shows how many models it provides ("Package (7)"), so every update of an
   install made the tree's twenty-odd nodes again (each a handful of panels: `DTree_Node` with its label, expander and
   icon). Its signature now has two parts: the tree's layout (the tab, the folders, each package's id, title and kind,
   the deleted models' count, the language) and the packages' counts. When only the counts changed, each package's node
   gets its label again (`DTree_Node:SetText`, kept in `self.packageNodes`); otherwise the tree is built again as before.
   A full rebuild of the list uses the same function.
5. **Anything else builds the list again, as before**: a row that would have to go (its entry, listed again, left the
   folder or the search), a rename, a favourite, a move, a deletion, another folder or search, a full library rebuild,
   names translated, the deleted Workshop models' view, the props tab (its library records nothing), the scene tab, a
   window more than sixteen revisions behind, a window that was hidden (shown again, it rebuilds), and a list whose
   display order is not the length the window left it.

## Consequences

- An update of a pack's install costs the rows it adds or changes, not the whole list: measured in the handover report
  ([library-rows-report.md](../handover/library-rows-report.md)).
- The selection stays as the player left it. A rebuild selected again only the row chosen last (`self.selected`);
  rows brought up to date alone leave a selection of several rows alone, so Move or Delete still applies to all of
  them. Likewise a folder the player collapsed stays collapsed when only a package's count changes (a rebuilt tree
  expanded it again).
- The window relies on `DListView`'s `Sorted` table, GMod's display order (`dlistview.lua`: `AddLine` appends to
  `Lines` and `Sorted`, `DataLayout` lays out `Sorted`). If it is missing, or its length is not the window's count of
  rows, the window builds its list again. Rows are never removed alone: `RemoveLine` would leave a hole in `Lines`, which
  the count line reads, so a row that has to go builds the list again.
- `tools/qa/pack_install_probe.lua` times `AddRows` beside `Refresh` and lists each update of the window with its
  frame (`library_updates`), each library revision and when the window was shown or hidden, and keeps the spawn menu
  open while it runs; `pack_install_session.py --hotloader-lua` also runs a branch's `ui.lua`, and `--keep-field-game`
  leaves a field game that another task's test uses running.

## Rejected

- **Building the list again over several frames, a few rows at a time:** the list would show part of the library for
  a moment, and the work would be the same.
- **Holding the window's update until the install ends:** the library window would show no new model for the whole
  install, which ADR 0255 lists every four seconds.
- **Reusing the old rows (a pool of panels):** saves making panels, but every row is still set and laid out again; more
  code than bringing the listed rows up to date, for less.
- **Rows for renames, favourites and moves too:** those changes come from the player's own click in the window, where
  a rebuild was always expected, and go through `library.Refresh`, which says nothing about what changed.
- **Treating an entry listed again as a reason to rebuild** (this decision's first form): in the user's game and in the
  PoC with the user's library, every update of the pack's install listed characters the library already had, so the
  window still rebuilt its list for each.
- **Sorting the whole display order again after adding rows** (`table.sort`): the same result with about 1,700
  comparisons of lowered names for 220 rows, where the binary search makes eight per row.
