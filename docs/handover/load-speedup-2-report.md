# The second load speed-up round (report)

Claude, 2026-11-16, on the branch `load-speedup-2` (worktree `out\worktrees\ls2`), package only: the Model
Hotloader's Lua and the load accelerator's module, add-on and menu line. The loader and the runtime are not changed.
Decisions: [ADR 0238](../decisions/0238-the-hotloaders-map-start-work-once-and-after-the-map-runs.md) (supersedes in part
[ADR 0099](../decisions/0099-saved-characters-load-on-first-use.md)) and
[ADR 0239](../decisions/0239-the-load-accelerator-caches-links-junctions-and-character-packs.md) (supersedes in part
[ADR 0140](../decisions/0140-the-load-accelerator.md)).

## The request and the plan

The user, 2026-11-16: "In field game, the game usually takes 2-3 minutes to load, if this can be further decreased, we
can save a lot of time for the user. We did a round of Plan a map-load speed-up (investigation only) before, please
perform another round to show me what can be further accelerated." The investigation came first: the plan, every
run's evidence and the tools are in the main checkout's `out/load-speedup-2/` (`PLAN.md`, `runs/`, `tools/`), facts in
[RESEARCH.md](../RESEARCH.md) ("The second load speed-up round"). Every warm map load of the field game took 88-95 s,
whatever the map; over half of it was one frame of 54 s in which the Model Hotloader built its character library 94
times (once per catalog message of the server, each decoding all 206 manifests). The user chose four of the plan's
items: "H1, A2, H2, H3".

## What changed

- **H1, the library built once for a catalog burst** (`packages/model-hotloader/mmd_hotloader/lua/mmdhl/library.lua`,
  `sharing.lua`): `library.RequestRefresh()` builds on the next tick, once however often it was asked; the receivers of
  `mmdhl_catalog` and `mmdhl_catalog_forget` ask through it (`catalogChanged`), and a single-player client not at all
  (its build does not read the server's catalog). The network messages are unchanged.
- **H3, the other map-start JSON once**: `library.Refresh()` keeps each decoded manifest with its file's size and time
  and decodes only a new or changed one (forgetting those no longer listed); the server's `PruneRigs` and its
  restoration of saved characters share one table of decoded rigs (`readRig`), so each `rig.json` is decoded once a
  map start instead of twice.
- **H2, the warm characters after the map runs** (`actors.lua`): in single-player and on a listen server every saved
  entry is published at the map's start and the characters the memory profile keeps ready are queued, newest use
  first; `mmdhl.readiness.HostReady()` (called when the host's client asks for the catalog from its `InitPostEntity`)
  starts the queue 5 s later, then one character (all its entries) every 3 s, `WarmNext`; 90 s after the map's start
  at the latest. A dedicated server makes them ready at once, as before. The console says "N entries ready once the
  map runs" at the start and "Saved characters ready while the map runs: N entries (M characters) in T s" at the end;
  `Describe()` adds `deferredEntries` and `waitingCharacters`.
- **A2, links, junctions and `mmdhl_*` cached** (`fs_accel/loose_cache.cpp`, `fs_accel.h`, `module.cpp`): a junction
  or directory symbolic link directly in `garrysmod/addons` is classified from its reparse data
  (`FSCTL_GET_REPARSE_POINT`): to a directory on a local fixed drive, it is listed through the link and its resolved
  target gets a `ReadDirectoryChangesW` of its own; to a missing target, every path through it is answered "path not
  found", as Windows answers, and the nearest existing folder on the way is watched; anything else is not cached, at
  most 48 links. A link's watch drops its own link on a change, an overflow or an error. The `mmdhl_*` folders are
  cached as plain folders. `Status().links`, the menu's line and the client's tally name the links.
- **Tests**: `tools/tests/test_hotloader_library_refresh.py` with its LuaJIT harness (new: the single-player and
  multiplayer catalog, the manifest cache, the sources' receivers, `readRig` and the host's `HostReady`);
  `test_mmd_lazy_load.py` (the deferral in the existing scenarios, `server_dedicated` and `server_host_ready` new);
  `fs_accel/tests/test_loose.cpp` (links and junctions against Windows' own answers, links that are not cached, a
  change behind a link).
- **Records**: the load accelerator's modules rebuilt and recorded (`tools/ci/repo_builds.py refresh`,
  `packages/load-accelerator`, `tools/ci/pins.json`); the edited Hotloader Lua indexed (`tools/inputs.py import
  model-hotloader`).

## Results in the user's field game

The branch's package as a local package (`allow.local` in the field's `native-loader/config.json`, which outranks the
Workshop copy; backed up first and put back byte for byte, SHA-256 `6C1F5D5F...`), measured with the plan's driver
(`field_run.py`: the user's launch options plus `-condebug`, the Workshop's mount awaited, `map` through the console, the
load overlay's end line). The first run ended the user's running game (PID 77192, started through Steam at 22:25) with
a console quit, as their standing permission for test sessions allows. Times from the map command to that line:

| Run | Package | modern_house (1st) | gm_construct (2nd) |
|---|---|---|---|
| `ab0-control-mh-gc` (the same hour) | Workshop `…20261117045710+91b90b73` | 96.3 s | 88.8 s |
| plan `r3` / `r5` (control) | Workshop `…034806+58651f23` | 92.4 s / 91.6 s | 88.2 s / 92.1 s |
| `ab1-mh-gc` (its first start deployed the package: 13.3 s, 232 changes) | branch `…054848+ca29d671` | **29.8 s** | **28.7 s** |
| `ab2-mh-gc` (40 s between the maps) | branch | **25.5 s** | **30.8 s** |

Phases of modern_house (seconds; `phase_table.py`): server 16.8 -> 11.3 / 9.4, client 16.3 -> 11.1 / 10.5, after the
client's `InitPostEntity` 59.3 -> 2.5 / 2.3, settling 3.9 -> 4.9 / 3.2 (control -> ab1 / ab2).

- **The accelerator** (its status after the first load): 54 roots, 8 of them links or junctions (the menu's line "54
  loose add-on folders cached, 8 of them links or junctions"); 3.84 million calls, 3.76 million answered, **75,588**
  went on to Windows (the plan's runs: 4.49-4.53 million, 3.63 million, 0.86-0.90 million); nothing dropped.
- **The warm characters**: "34 entries ready once the map runs (10 characters, 3.9 GiB ...)", and in ab2 "Saved
  characters ready while the map runs: 34 entries (10 characters) in 3.7 s" 30 s after the load's end. In the 38 s after
  the load the main thread had one busy stretch of 1.4 s at a character's materials and otherwise none of 0.25 s or
  more at 85 % of a core that came from the queue (`busy_stretches.py`; a 2.8 s stretch on `cache/map_pack.bsp` right
  after a load is there without this change too, plan run r4).
- **The load overlay** still names `mmdhl/library.lua` among the slowest Lua files (2.0-2.5 s: one build decoding the
  206 manifests in each map's new client Lua state).
- No Lua error in any run's console text; every run quit normally (exit 0) and wrote the field's settings back.
- **Every answer checked against Windows** (`ab3-verify-mh-gc`: `--probe --extra-lua verify_on.lua`, which sets
  `nativeloader_load_accel_verify 1` in the server realm once the first map's client Lua starts; the switch is the
  module's and stays on for the session). Verify mode hands each lookup the cache would answer to Windows and counts a
  disagreement when Windows finds the file: **0 disagreements**, 7.63 million answers in all, 3.71 million of them in
  gm_construct's load, which ran checked from its start (its server and client phases took 22.5 s and 20.7 s instead
  of 11-12 s, every answer going to Windows as well). The cached roots include the field's 8 links (7 junctions, 4 of
  them to folders that no longer exist, and one absolute directory symbolic link, which the tests cannot create) and
  the 4 `mmdhl_*` folders; nothing was dropped.
- The field's `config.json` was put back after the runs (SHA-256 `6C1F5D5F...`, `nlctl plan` shows the Workshop copy
  ACTIVE again); the game was left closed. Its next start deploys the Workshop's version again (2.8 s in the control
  run).

## Not checked

- A listen server with a second player, and a dedicated server: covered by the harnesses (`multiplayer_catalog`,
  `server_dedicated`, the host-only `HostReady`), not by a game.
- A relative directory symbolic link: this account may not create symbolic links, so the tests use junctions; the
  field's one symbolic link is absolute.
- A cold first load (after a restart): the plan measured +19 s cold for the old package; not repeated.

## Leftovers

- In the main checkout's `out/load-speedup-2/`: the plan, the runs `ab0`-`ab3` beside the plan's, the new tools
  `busy_stretches.py` and `verify_on.lua`, the field config's backup `field-config.json.bak`; in this worktree
  `out/ls2-package` (the package used in the field).
- The plan's other items are open: ARC9's attachment icons (F), a prefetch for cold loads (E), the loader's start check
  and deployment (L1, L2; need the user's approval), the overlay naming slow hooks (D2), Remix's spinning geometry
  workers (S1).

## The gate

`tools\test.ps1 -Config Release` with `NL_FIXES_CLONE` in this worktree, on `a51d6bf0`: CTest 35 of 35, 2,111 Python
tests OK (one skipped, as before), all checks passed. Its first run, on `457e4994`, failed one test
(`test_vr_review_docs`: the shared decision index may only gain table rows, and notes had been appended to the entries
of 0099 and 0140); the notes were taken out, since the new rows and the ADRs say what they supersede.
