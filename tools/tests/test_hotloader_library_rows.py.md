# test_hotloader_library_rows.py

[ADR 0258](../../docs/decisions/0258-the-library-window-adds-rows-for-new-characters.md): the Model Hotloader's library
window brings the rows of the characters `library.Add` listed up to date (new rows, and the rows of characters listed
again) instead of building its whole list again, and shows exactly what a rebuild shows. With the user's library of 220
characters and the spawn menu open on the Model Hotloader's tab, each library update of a content pack's install
rebuilt the list: a frame of 52-59 ms (three panels a row, 660 in all, made again), five times for a pack of twelve.

`LibraryRowsTests` runs [hotloader_library_rows_harness.lua](hotloader_library_rows_harness.lua.md) with LuaJIT once
per scenario: `record` (what `library.Add` records by revision), `rows_like_a_rebuild` (two additions before a frame,
then a third, beside a selected row and with none; a package's count relabelled in the folder tree, a new package
building it again), `views` (folders, Workshop packages and searches: only the rows a
view lists are made), `empty_view` (an empty folder and an empty Workshop view gain their first rows), `multi_selection`
(rows the player selected stay selected), `listed_again` (a package's model over a character the library has: its row
renamed, badged and moved, the chosen entry's details, rows joining a folder or a search, the total when an entry leaves
the folder, a selection of two), `rebuilds` (a row that has to go, renames, favourites, moves, a rebuild before the
frame, names translated, more updates than the record keeps, a column sort, a changed folder, the deleted view, the
props and scene tabs: the list built again), `gui_scaler` (new rows carry GUI Scaler's mark) and `random` (150 random
libraries, views, selections and batches of new characters and characters listed again, each checked as rows or as a
rebuild where a row had to go). Each compares the window with a window built afresh on the same library and view, row
by row.

`LibraryRowsSourceTests` reads the shipped sources: the window's `Think` brings rows up to date when `AddedSince` names
them and otherwise calls `Refresh`; only `Refresh` clears the list and records what it was built from (`self.built`);
`library.Add` records each id it listed once and `library.Refresh` clears the record; the PoC probe
([pack_install_probe.lua](../qa/pack_install_probe.lua.md)) times `AddRows` beside `Refresh` and reports the window's
updates, and [pack_install_session.py](../qa/pack_install_session.py.md) runs a branch's `ui.lua` too.

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_library_rows.py    # from the repository root
```

No game or installed data is touched; nothing is written. Requires LuaJIT for the harness (otherwise one explicit
skip). Exit 0 on pass, nonzero on an assertion, a Lua error or a timeout.
