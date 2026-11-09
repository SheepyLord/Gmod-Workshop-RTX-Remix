# fs_accel

The load accelerator (R26, [ADR 0140](../docs/decisions/0140-the-load-accelerator.md)): two binary modules from one
source, `gmcl_nlfsaccel_win64.dll` and `gmsv_nlfsaccel_win64.dll`, shipped in the package's `load-accelerator` part
([packages/load-accelerator](../packages/load-accelerator/README.md)) with the Lua add-on in [`addon/`](addon), which
the package deploys as `garrysmod/addons/nlloadaccel`. It runs in RTX starts: the companion's menu script
[`load_accel.lua`](../companion/nativeloader/lua/nativeloader/menu/load_accel.lua.md) installs the hooks at menu start
and the add-on adopts them in each realm. The part is not marked `requires_remix` (nothing in it needs Remix), but the
combined RTX package is, and in a start without RTX the loader leaves every add-on folder of such a package out
([ADR 0013](../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)) while GMod never mounts the package's own
archive, so nothing loads the modules there; that would take a loader change (R26's report).

A crash or a hang while the hooks are new must not repeat at every start: `install()` writes
`garrysmod\data\nativeloader\load_accel_pending.txt` (the process's id and creation time) just before the hooks go in
and a thread of its own deletes it 20 s later. A start that finds the marker of a process that is gone leaves the
hooks out once and deletes it; an environment variable naming the process makes the module's other copy refuse as
well. Another running game of the same install (its process still alive) is no reason to refuse.

- **A: what is not in the loose add-on folders.** Every lookup of a game file tries each folder under
  `garrysmod/addons` on disk before the mounted `.gma` files, and a missed open is tried twice (Valve's native open,
  then the C runtime's). The module hooks `filesystem_stdio.dll`'s imports of `CreateFileA/W` and
  `GetFileAttributesExA/W` and answers "not there" (`ERROR_FILE_NOT_FOUND`, or `ERROR_PATH_NOT_FOUND` for a missing
  folder on the way) for a read-only lookup inside a cached folder whose directory listing (taken on first use) has no
  such name, as Windows would. Everything else goes on unchanged to the slot's previous function: the loader's own
  hook where it has one (in RTX starts it redirects a few reads), else Windows. Cached: each plain folder directly in
  `garrysmod/addons` with an ASCII name (not a junction or link, not the Model Hotloader's `mmdhl_*`, which its worker
  writes into while the game runs) and `garrysmod/workshop`, which is normally missing. Only plain ASCII
  `X:\...` paths are answered (no `\\?\`, UNC, `.`/`..`, streams, wildcards, trailing dots or spaces, 8.3 names or
  devices). A watcher thread (`ReadDirectoryChangesW`, armed before any listing) stops caching a folder that changes;
  while a change notification waits to be read nothing is answered; a create, write or delete open the game itself
  makes in a folder stops it at once. Positive lookups always reach the disk, so an edited Lua file or material shows
  as it does without the module.
- **B: file.Find(pattern, title).** GMod's `Addon::FileSystem::FindFirst` walks every entry of every mounted add-on
  for each search with an add-on's title as the path (2.5-2.9 ms a call with 774 add-ons; Extended Spawnmenu makes
  2,263 of them right after a map loads). The module finds GMod's add-on table by the file system's export and RTTI
  (`Addon::FileSystem`), reads it once under SEH (every link and size checked, nothing written) into an index of each
  add-on's directories and files, and answers the same search from it; a change of the table (its sizes or list) builds
  it again. Two add-ons with one title give each name once, as GMod does; a wildcard in the folder part of a pattern
  is left to GMod. The add-on replaces `file.Find` for add-on titles only, after a self-test against GMod's own
  answers.

| File | Purpose |
|---|---|
| `CMakeLists.txt` | `nl_fs_accel` (static: the paths, the cache, the hooks, the index), the client and server modules, `nl_fs_accel_tests` |
| `fs_accel.h` | The shared declarations: paths, the cache and its counters, the watcher, the hooks, the index |
| `path_rules.cpp` | Which paths the cache may answer for (`normalize`), GMod's add-on wildcards (`wildcard_match`) |
| `loose_cache.cpp` | A: the cached folders, their listings and verdicts (`LooseCache`), the watcher thread (`Watcher`) |
| `hooks.cpp` | A: the import hooks on `filesystem_stdio.dll` (chained, once per process, the other copy's hooks recognised by the `nl_fs_accel_v1` export), verify mode, the counters, the start-up marker, `install()` |
| `addon_index.cpp` | B: finding `Addon::FileSystem`, reading GMod's table under SEH, the index and the search (`AddonIndex`) |
| `module.cpp` | `gmod13_open`: the `nlfsaccel` Lua table (`Install`, `Status`, `SetEnabled`, `SetVerify`, `FindInAddon`, `Invalidate`, `CountFind`) |
| `tests/test_loose.cpp` | The path rules and wildcards; the cache's verdicts against Windows' own answers on generated trees; a folder with a name Windows could fold differently; the hook bodies (answered without the next function, the rest passed on, writes drop a folder, off); the watcher; the start-up marker (its own, a running process's, a gone one's, a reused id, text that is no marker) |
| `tests/test_index.cpp` | The index against a table laid out as GMod's (built with the same C++ library): directories and files per add-on, a title shared by two add-ons (each name once), a mount that owns nothing, wildcards (one in the folder part left to GMod), case and slashes, a rebuild after a change, a table that does not hold together |
| `addon/lua/autorun/!!!!!nlloadaccel.lua` | The add-on: loads the module in the server and client realms, adopts A (or installs it), replaces `file.Find` for add-on titles after a self-test, the checks, the tally after a load ([its documentation](addon/lua/autorun/!!!!!nlloadaccel.lua.md)) |
