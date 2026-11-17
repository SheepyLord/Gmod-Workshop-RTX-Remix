# hotloader_library_refresh_harness.lua

The LuaJIT side of [test_hotloader_library_refresh.py](test_hotloader_library_refresh.py.md) (load-speedup round 2,
[ADR 0238](../../docs/decisions/0238-the-hotloaders-map-start-work-once-and-after-the-map-runs.md)). Loads the shipped
`mmdhl/library.lua` and `mmdhl/sharing.lua` whole in the client realm, with the disk (50 characters' manifests and
settings, their sizes and times), the native module, timers, hooks and network messages instrumented, and counts each
`util.JSONToTable` of a manifest.

```powershell
luajit tools\tests\hotloader_library_refresh_harness.lua packages\model-hotloader\mmd_hotloader\lua\mmdhl <scenario>
```

Scenarios:

- `single_player_catalog`: 93 `mmdhl_catalog` messages and a tick leave the library's revision, its manifests and
  `MMDHL.LibraryChanged` alone; the catalog is still kept in `mmdhl.sharedAssets`.
- `multiplayer_catalog`: the same messages from another server build the library once, on the tick, without decoding
  a manifest again, and list the 93 server-approved characters; a withdrawal is one more build; twenty
  `RequestRefresh` calls before a tick are one build.
- `manifest_cache`: a second build decodes nothing; a manifest written again (another time) or of another size, a new
  character, one whose folder went (listed no more) and came back are each decoded once; settings (a chosen name, a
  deletion) are read at every build.

The include-time build must decode each manifest once in every scenario. Prints `PASS <scenario>` and exits 0;
otherwise a Lua error names the failed check (exit 1). Writes nothing.
