# category_manager_harness.lua

Loads the packaged RTX fixes' automatic categorization (`remixlua/cl/remixapi/cl_remix_category_0_manager.lua`)
under stand-ins for GMod, NikNaks and the native `RemixMaterial` API, and checks
[ADR 0213](../../docs/decisions/0213-automatic-categorization-hardened.md):

- a map load's delayed start runs the map scan as a job spread over frames (each frame's step stays small, with a
  clock that costs half a millisecond a look), every write says it is automatic, and brushes, glass, the blended
  displacement (under the tracker's name, not `maps/<map>/..._wvt_patch`), the static prop and the `$decal` overlay
  become decals; the C++ world list has each material once; an unreadable material is counted and skipped; each VMT
  is read once a scan;
- Scan Now again gives the same categories and no second queue entry;
- World Geometry off empties the C++ world list and marks no map geometry while Overlay Decals still marks the
  overlay; with both off nothing is marked; World Geometry on scans again;
- the queue merges a material's requests into one entry, and a frame checks at most 64 entries;
- a manual `rtx_set_material_category` write is not automatic;
- switching automatic categorization off stops the scan and drops its queued work, keeping manual entries;
- a map change stops the old map's scan and queue, and the old map's delayed start does nothing.

Usage: `luajit tools/tests/category_manager_harness.lua <cl_remix_category_0_manager.lua>`. Reads only its argument;
no game, network or file writes. Prints `PASS category manager: ...` and exits 0, nonzero on a failed assertion.
Run by [test_player_categories.py](test_player_categories.py.md).
