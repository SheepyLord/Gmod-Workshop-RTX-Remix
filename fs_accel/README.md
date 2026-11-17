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
`garrysmod\data\nativeloader\load_accel_pending.txt` (the process's id and creation time) just before the hooks go in,
and a thread of its own deletes it once a map has loaded with them (`settle()`, which the menu script calls 10 s after
the first load ends and the add-on 5 s after `InitPostEntity`) and at least 20 s have passed. A start that finds the
marker of a process that is gone leaves the hooks out once and deletes it; an environment variable naming the process
makes the module's other copy refuse as well. Another running game of the same install (its process still alive) is
no reason to refuse. A game that quits before any map leaves the marker, and its next start goes without the hooks
once.

- **A: what is not in the loose add-on folders.** Every lookup of a game file tries each folder under
  `garrysmod/addons` on disk before the mounted `.gma` files, and a missed open is tried twice (Valve's native open,
  then the C runtime's). The module hooks `filesystem_stdio.dll`'s imports of `CreateFileA/W` and
  `GetFileAttributesExA/W` and answers "not there" (`ERROR_FILE_NOT_FOUND`, or `ERROR_PATH_NOT_FOUND` for a missing
  folder on the way) for a read-only lookup inside a cached folder whose directory listing (taken on first use) has no
  such name, as Windows would. Everything else goes on unchanged to the slot's previous function: the loader's own
  hook where it has one (in RTX starts it redirects a few reads), else Windows. Cached: each folder directly in
  `garrysmod/addons` with an ASCII name (not two folders whose names differ only in case) and `garrysmod/workshop`,
  which is normally missing. From [ADR 0239](../docs/decisions/0239-the-load-accelerator-caches-links-junctions-and-character-packs.md)
  that includes the Model Hotloader's `mmdhl_*` character packs (the loader deploys them before the game starts) and
  junctions and directory symbolic links (`FSCTL_GET_REPARSE_POINT`, a relative link resolved against its folder,
  at most 48): one whose target is a directory on a local fixed drive is listed through the link and its resolved
  target watched on its own (its subtree); one whose target is missing answers every path through it
  `ERROR_PATH_NOT_FOUND`, as Windows does (the link itself goes to Windows), and the nearest existing folder on the way
  to the target is watched. Any other reparse point (cloud files, deduplication, app aliases), a network or removable
  target, a link to a file or a missing target behind a file is not cached. A change, an overflow or an error seen by a
  link's own watch drops that link alone; a missing target that appeared before its watch was armed is checked after
  arming. Only plain ASCII `X:\...` paths are answered (no `\\?\`, UNC, `.`/`..`, streams, wildcards,
  trailing dots or spaces, 8.3 names or devices). A watcher thread (`ReadDirectoryChangesW`, armed before any listing)
  stops caching a folder that changes; while a change notification waits to be read nothing is answered; an open the
  game itself makes that can create or delete a file in a folder stops it at once. Positive lookups always reach the
  disk, so an edited Lua file or material shows as it does without the module. Once the process shuts down
  (`RtlDllShutdownInProgress`) nothing is answered and no lock is taken.
- **B: file.Find(pattern, title).** GMod's `Addon::FileSystem::FindFirst` walks every entry of every mounted add-on
  for each search with an add-on's title as the path (2.5-2.9 ms a call with 774 add-ons; Extended Spawnmenu makes
  2,263 of them right after a map loads). The module finds GMod's add-on table by the file system's export and RTTI
  (`Addon::FileSystem`), reads it once under SEH (every link and size checked, every tree walk with a step budget, so
  links that never end are refused and never followed; nothing written) into an index of each add-on's directories and
  files, and answers the same search from it. A change of the table (its sizes, or any list node: its address, owner,
  title or path) builds it again, at most every 2 s; meanwhile GMod answers. Two add-ons with one title give each name
  once, as GMod does; a wildcard in the folder part of a pattern is left to GMod. The add-on replaces `file.Find` for
  add-on titles only, after a self-test against GMod's own answers.

- **E: what a load reads, read ahead for the next load** ([ADR 0242](../docs/decisions/0242-what-a-load-reads-read-ahead-for-the-next.md)).
  While the companion's load overlay records a map load (`PrefetchRecord`), a hook on `filesystem_stdio.dll`'s
  `ReadFile` import notes which 64 KiB blocks of which file the load reads, in the order the files are first read: the
  offset from the `OVERLAPPED`, or for a synchronous read the handle's position asked before the read; the file from
  the `CreateFile` hooks or, for a handle opened before the record (the Workshop's archives), from Windows
  (`GetFinalPathNameByHandleW`). When the load has reached the game the overlay saves the record
  (`PrefetchSave`) as `garrysmod/data/nativeloader/prefetch/<map>.lst` (Lua cannot write that extension; files on
  local fixed drives only, not `garrysmod/cache` or `garrysmod/data`, 8 GiB at most) and, for a game's first load,
  `last.txt`. `Prefetch([map])` reads a list's blocks on a thread of its own: each file opened only when it is a plain
  file on a local fixed drive of the size the list names, its reads at low I/O priority (`IoPriorityHintLow`),
  1 MiB at a time into a buffer it discards, at most a quarter of the memory or 4 GiB; a later prefetch supersedes
  it. The companion reads the last first load's list ahead at menu start and a load's own map's once it is named.
  Only the copy that installed the hooks records (the menu realm's).

| File | Purpose |
|---|---|
| `CMakeLists.txt` | `nl_fs_accel` (static: the paths, the cache, the hooks, the index), the client and server modules, `nl_fs_accel_tests` |
| `fs_accel.h` | The shared declarations: paths, the cache and its counters (with the switches, shared by both copies), the watcher, the hooks, the start-up marker, the index |
| `path_rules.cpp` | Which paths the cache may answer for (`normalize`), GMod's add-on wildcards (`wildcard_match`) |
| `loose_cache.cpp` | A: the cached folders, their listings and verdicts (`LooseCache`), the watcher thread (`Watcher`) |
| `hooks.cpp` | A: the import hooks on `filesystem_stdio.dll` (chained, once per process, the other copy's hooks recognised by the `nl_fs_accel_v1` export), verify mode, the counters, the start-up marker and `settle()`, `install()` |
| `prefetch.cpp` | E: the record of a load's reads (`record_start`, `opened`, `read`, `record_list`), the list file (`save_list`, `load_list`), the read-ahead thread (`start`, `status`, `default_budget`, `wait`) |
| `addon_index.cpp` | B: finding `Addon::FileSystem`, reading GMod's table under SEH, the index and the search (`AddonIndex`) |
| `module.cpp` | `gmod13_open`: the `nlfsaccel` Lua table (`Install`, `Status` (with `links`, the links and junctions cached), `SetEnabled`, `SetVerify`, `FindInAddon`, `Invalidate`, `CountFind`, `Settled`; E: `PrefetchRecord`, `PrefetchSave`, `Prefetch`, `PrefetchStatus`, in the copy that installed the hooks) |
| `tests/test_loose.cpp` | The path rules and wildcards; the cache's verdicts against Windows' own answers on generated trees; junctions (live, to a missing folder whose parent exists, to one several missing folders deep) and, where the account may make one, a directory symbolic link, against Windows' answers; links that are not cached; a change behind a link that drops it; a folder with a name Windows could fold differently; the hook bodies (answered without the next function, the rest passed on, writes drop a folder, off); the watcher (a change seen, read, the folder dropped, the others answered again); the start-up marker (its own, a running process's, a gone one's, a reused id, text that is no marker) |
| `tests/test_prefetch.cpp` | E: list names; a record of synchronous and overlapped reads (blocks, first-read order, a handle opened before the record, the cache folder and unread files left out, the budget); the list's round trip and what it refuses (another file, relative and network paths); a read-ahead within its budget, clipped at the file's end, passing over a file of another size and a missing one |
| `tests/test_index.cpp` | The index against a table laid out as GMod's (built with the same C++ library): directories and files per add-on, a title shared by two add-ons (each name once), a mount that owns nothing, wildcards (one in the folder part left to GMod), case and slashes, a rebuild after a change but not twice within 2 s, a remount with every size the same, a table that does not hold together, a tree link pointing back at its node |
| `addon/lua/nlloadaccel/load_callbacks.lua` | D2 ([ADR 0241](../docs/decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md)): the hooks, timers and net receivers of a map load timed and the slowest named ([its documentation](addon/lua/nlloadaccel/load_callbacks.lua.md)) |
| `addon/lua/nlloadaccel/arc9_icons.lua` | F ([ADR 0240](../docs/decisions/0240-arc9s-attachment-icons-decoded-when-first-drawn.md)): ARC9's attachment icons decoded when first drawn ([its documentation](addon/lua/nlloadaccel/arc9_icons.lua.md)) |
| `addon/lua/autorun/!!!!!nlloadaccel.lua` | The add-on: loads the module in the server and client realms, adopts A (or installs it), replaces `file.Find` for add-on titles after a self-test, the checks, the off file for the menu realm, `Settled()` and the tally after a load ([its documentation](addon/lua/autorun/!!!!!nlloadaccel.lua.md)) |
