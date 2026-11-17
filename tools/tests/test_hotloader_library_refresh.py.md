# test_hotloader_library_refresh.py

Load-speedup round 2 ([ADR 0238](../../docs/decisions/0238-the-hotloaders-map-start-work-once-and-after-the-map-runs.md)):
the Model Hotloader's character library is built again once for a server's whole catalog, never for a single-player
catalog, and each character's `manifest.json` is decoded once. In the user's field game the library was built 94 times
at every map start (one per approved character's catalog message, each decoding 206 manifests): 51 s of
`util.JSONToTable`.

`LibraryRefreshTests` runs [hotloader_library_refresh_harness.lua](hotloader_library_refresh_harness.lua.md) with
LuaJIT once per scenario: `single_player_catalog` (93 catalog messages, no rebuild), `multiplayer_catalog` (93
messages and a withdrawal: one rebuild each, after the tick, no manifest decoded again; asks before a tick are one
rebuild) and `manifest_cache` (a second build decodes nothing; a manifest written again, of another size, new, gone and
back; settings and a deletion still read at every build).

`LibraryRefreshSourceTests` reads the shipped `sharing.lua`: the two catalog receivers call `catalogChanged()`, never
`library.Refresh()` directly; the map-start restoration decodes rigs through `readRig` with one table for
`PruneRigs` and itself; the server's catalog request starts the warm characters (`mmdhl.readiness.HostReady`) only for
the host.

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_library_refresh.py    # from the repository root
```

No game or installed data is touched; nothing is written. Requires LuaJIT for the harness (otherwise one explicit
skip). Exit 0 on pass, nonzero on an assertion, a Lua error or a timeout.
