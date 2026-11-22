# hotloader_library_rows_harness.lua

The LuaJIT side of [test_hotloader_library_rows.py](test_hotloader_library_rows.py.md)
([ADR 0258](../../docs/decisions/0258-the-library-window-adds-rows-for-new-characters.md)). Loads the shipped
`mmdhl/library.lua` and `mmdhl/ui.lua` whole in the client realm (GMod's one `continue` in `ui.lua`, in the scene tab's
loop, is read as LuaJIT's `goto`), with the disk (characters' manifests and settings as tables), the native module, the
Workshop's origins, translated names and Derma instrumented. The stand-in `DListView` keeps GMod's lines: `Lines` in
creation order, `Sorted` in display order, `AddLine` appending to both; `SortByColumn` sorts by a column's text as a
header click does. A badge's `PaintOver` is run to read its pill's text and colour. `relist` gives a character the
library has a package's settings and Workshop origin, as a package's model over the player's own copy does.

```powershell
luajit tools\tests\hotloader_library_rows_harness.lua packages\model-hotloader\mmd_hotloader\lua\mmdhl <scenario>
```

A check compares the window that took the changes with one built afresh in the same view (folder, search and the entry
the window chose): every row in display order (asset, both columns, tooltip, badge text and colour, fonts, GUI Scaler's
`gScF` mark, the entry it holds), the selected rows, the chosen entry, the buttons' states, the count line, the details,
the name, the folder tree and its selected node. An update the window takes as rows must not clear the list and must
make one line per new row; a rebuild must clear it once.

Scenarios:

- `record`: `library.Add` records the ids it listed (new ones and ones listed again), once each, by revision;
  `library.Refresh` clears the record; only the last sixteen revisions are kept.
- `rows_like_a_rebuild`: two additions before the window's next frame (seven rows), then five more, beside a selected
  row (still the one selected); a model of a package the tree shows (its node relabelled, the tree not built again)
  and of a new package (the tree built again); a window with nothing selected.
- `views`: the unfiled models, a folder and its subfolder, the Workshop's models and two packages', searches by name,
  original name, id, source and nothing, a folder with a search, a Workshop view with a selection.
- `empty_view`: an empty folder ("no models") gains a row ("choose a row"); an empty Workshop view gains a first
  package's model (its folder tree grows).
- `multi_selection`: three selected rows stay selected and the chosen one stays chosen.
- `listed_again`: an own model taken over by a package (renamed, its favourite gone, a Workshop badge: its row moves);
  the chosen entry listed again (renamed, needing bones: its details follow); new and listed-again characters in two
  batches before one frame; in a folder with a search, an entry without a row leaving the folder (the total), one
  joining it, one now found by the search and a row that moves; two selected rows listed again.
- `rebuilds`: a rename, a full rebuild, a favourite, a move to a folder, a row whose entry left the folder or the
  search when listed again, an addition then a rebuild, names translated, seventeen additions without a frame, a column
  sort, a folder changed without a rebuild, the deleted Workshop models' view, an addition that lists nothing (no
  update at all), the props tab and the scene tab.
- `gui_scaler`: with GUI Scaler's convar present, new rows carry its mark as a rebuild's rows do.
- `random`: 150 seeded libraries (0-40 characters of repeated and differently cased names, favourites, folders,
  packages, bone badges, translated names, sources), views, selections and one to four batches of new characters and
  of characters listed again with other settings (a duplicate id sometimes), with or without a frame between them; a
  rebuild is expected exactly when a row has to go. It prints how many updates it checked of each kind and needs more
  than 100 as rows and more than 10 rebuilds.

Prints `PASS <scenario>` and exits 0; otherwise a Lua error names the failed check (exit 1). Writes nothing.
