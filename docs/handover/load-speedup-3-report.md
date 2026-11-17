# The third load speed-up round (report)

Claude, 2026-11-17, on the branch `load-speedup-3` (worktree `out\worktrees\ls3`), package only: the load accelerator's
module and add-on (`fs_accel/`), the companion's load overlay and menu script. Decisions:
[ADR 0240](../decisions/0240-arc9s-attachment-icons-decoded-when-first-drawn.md) (F),
[ADR 0241](../decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md) (D2) and
[ADR 0242](../decisions/0242-what-a-load-reads-read-ahead-for-the-next.md) (E). The plan's S1 is its own branch
(`remix-workers`, ADR 0243, `docs/handover/remix-workers-report.md` on that branch); L1 and L2 (the loader, branch
`loader-speedup`, ADR 0244 proposed) were rejected by the user and are not part of this round's result.

## The request

The user, 2026-11-17, after the second round: "Very nice, now the field game load into modern_house within 30 seconds.
Let's also do the remaining 6 points in the plan. Every second matters" (the plan: `out/load-speedup-2/PLAN.md` in the
main checkout, items F, E, L1, L2, D2, S1). Later: "All loader change is rejected, please present your work to the main
thread, don't push or commit, let the main thread coordinate." S1 and L1/L2 were built by subagents in their own
worktrees; F, D2 and E here.

## What changed

- **F, ARC9's attachment icons decoded when first drawn** (`fs_accel/addon/lua/nlloadaccel/arc9_icons.lua`, ADR 0240).
  ARC9's attachment files ask `Material(<icon>.png, "mips smooth")` while they load: the user's subscriptions hold 1,722
  such calls in 154 files of 7 add-ons, 1,481 of them PNGs, 853 distinct. A PoC probe showed GMod caches a PNG material by
  flags and path for the whole process (a second call 0.002 ms; 30 PNGs the server realm decoded cost the client
  0.10 ms against 2.4 ms for 10 small fresh ones), so the server decoded every icon and the client found them: both
  realms had to stop. While a map loads (until the realm's `InitPostEntity`), a PNG an ARC9 attachment file asks for
  (its source up to nine frames up the stack) gets a stand-in: the server one shared material, the client one
  `UnlitGeneric` per icon made without decoding, filled with the decoded icon at its first draw or read
  (`surface.SetMaterial`, `render.SetMaterial` and the overrides, the IMaterial getters). Not with ARC9's
  `arc9_atts_generate_entities` on, nor for flags other than `mips`, `smooth`, `noclamp`. Switch:
  `nativeloader_load_accel_arc9`.
- **D2, the load's slowest Lua callbacks named** (`fs_accel/addon/lua/nlloadaccel/load_callbacks.lua`,
  `companion/.../menu/loading_status.lua`, ADR 0241). From the load accelerator add-on's autorun (the first of each
  realm) until 10 s after `InitPostEntity`, what `hook.Add`, `timer.Simple`, `timer.Create` and `net.Receive` register is
  timed (the render guard's record of timed functions gets each wrapper); then the originals go back (the lag report's
  `swap`). A console line per realm, `data/nativeloader/load_callbacks_<realm>.txt`, and the overlay's end-of-load line
  ("Lua callbacks that ran longest: ..."). Switch: `nativeloader_load_accel_callbacks`.
- **E, what a load reads, read ahead for the next** (`fs_accel/prefetch.cpp`, `hooks.cpp`, `module.cpp`,
  `menu/load_accel.lua`, `menu/loading_status.lua`, ADR 0242). A hook on `filesystem_stdio.dll`'s `ReadFile` notes, while
  the overlay records a load, which 64 KiB blocks of which file it reads (one lock and no allocation a read: each handle
  is mapped to its file once); a load that reached the game is saved as `data/nativeloader/prefetch/<map>.lst` (an
  extension Lua cannot write; a game's first load also as `last.txt`). The module reads a list ahead on its own thread
  at low I/O priority (local fixed drives, files of the listed size, at most a quarter of the memory or 4 GiB): the last
  first load's at menu start, a load's own map's once it is named. Lua: `PrefetchRecord`, `PrefetchSave`, `Prefetch`,
  `PrefetchStatus`. Switch: `nativeloader_load_accel_prefetch` (kept for the menu as a file).
- **Tests**: `nl_fs_accel_tests` (`tests/test_prefetch.cpp`: list names, the record of synchronous and overlapped reads,
  the list's round trip and what it refuses, a read-ahead within its budget); `test_arc9_icons.py`,
  `test_load_callbacks.py` with their LuaJIT harnesses; new scenarios in `test_loading_status.py` (`callbacks`,
  `prefetch`, `prefetch-off`) and `test_load_accel.py` (`menu-prefetch`, `menu-prefetch-off`).
- **Records**: the load accelerator's modules refreshed twice (`repo_builds.py refresh`; the second after the record's
  per-read cost was cut).

## Results in the user's field game

The branch's package through `allow.local` (as in the second round; config backed up and put back, SHA-256
`6C1F5D5F...`), the second round's driver. Warm: `r3-w2-mh-gc` (package `…080405+c7191064`, after a warm-up start
`r3-w1`) against the second round's `ab2-mh-gc`; seconds from the map command to the overlay's end line:

| | Second round (ab2) | Round 3 (r3-w2) |
|---|---|---|
| modern_house in all | 25.5 | 25.9 |
| — server phase | 9.4 | **8.4** |
| — client phase | 10.5 | 11.4 |
| gm_construct after it, in all | 30.8 | **27.8** |
| — server phase | 12.2 | **10.7** |
| — client phase | 12.4 | 10.7 |

The second round's own repeat runs differed by 2-4 s (ab1 against ab2), so the totals are within the noise; the server
phase is 1.0-1.5 s shorter in both loads (F). The runs `r3-b1`, `r3-b2` and the warm-up `r3-w1` were partly cold (the
subagents' builds, PoC runs and 15 GB of scratch copies had pushed the game's files out of Windows' cache: in r3-b2 the
main thread was 44-63 % busy in several slices against 95-100 % warm) and are not counted.

- **F**: every load, "1012 ARC9 attachment icons not decoded (the server never draws them)" and "784 ARC9 attachment
  icons left to be decoded when first drawn"; no Lua error in any run.
- **D2**: the end line of r3-w2's modern_house: "Lua callbacks that ran longest: server hook InitPostEntity
  MMDHL.RestorePublishedActors (sharing.lua:295, 1 call) 1.9 s, net mmdhl_actor_registration (actors.lua:516, 151 calls)
  0.8 s, hook InitPostEntity RTXReady_MaterialFixer (cl_rtx_material_fixer.lua:92, 1 call) 0.6 s". The client's own
  line also names Think `BBS.ProcessRagdollMeshPrewarm` 2.3-2.4 s (214-278 calls) and, in r3-b1, `MMDHL.WorkshopScan`
  1.4 s: the next candidates.
- **E**: modern_house's record: 1,962 files, 1,836 MB, 85,869 reads; gm_construct's: 672 files, 1,749 MB, 122,677 reads.
  At menu start the module read modern_house's list ahead ("1765 MB of 1961 files"), at gm_construct's load its own
  (1,725 MB). With the per-read work cut to one lock (an earlier build copied the path twice a read), the record costs
  about 0.1-0.2 s a load (estimated from the reads; not measured apart).

## The gate

`tools\test.ps1 -Config Release` with `NL_FIXES_CLONE` set:

- On `f279b07a` with the docs, in the worktree: exit 0. Its first run on that state failed only the known
  `nl_client_catalog_tests` flake, which then passed three times out of three on its own.
- Merged with `remix-workers` (`2ef7ee21`): exit 0. Conventions OK, CTest 35/35, Python 2,131 + 29 + 26 tests (one
  skipped in each).
- Then merged with `main` (`cf8d7137`), the state merged into `main`: exit 0. Conventions OK, CTest 35/35, Python
  2,141 + 29 + 26 tests (one skipped in each).

## Not checked

- **E's effect on a cold load**: the A/B was not run before the hand-over. `out/load-speedup-2/tools/field_run.py` has
  `--hold-lists` (no read-ahead for that run) and `--purge-list <lst>` (the listed files dropped from Windows' cache
  under the lock, `out/load-speedup-3/tools/purge_list.py`); the lists are kept in the main checkout's
  `out/load-speedup-3/field-data/prefetch` (copy them into the field's `garrysmod/data/nativeloader/prefetch` with this
  branch's package).
- F's client side in a real ARC9 menu (the first opening decodes the icons it shows): covered by the harness, not opened
  in the field.
- A multiplayer client and a listen server's other players; a dedicated server (no RTX package there).
- What a load reads outside `filesystem_stdio.dll` (the Remix runtime's own mod textures) is not recorded.

## Leftovers

- In the main checkout's `out/load-speedup-3/`: the ARC9 extraction and scan, the PoC probes (`poc/pngcache`,
  `poc/pngrealm2`), the tools (`with_poc_lock.py`, `purge_list.py`, the probes), the field's lists and callback files
  moved out of the field (`field-data/`); the runs in `out/load-speedup-2/runs/r3-*`.
- The worktree's `out/ls3-package` (the package used in the field).

## Published

Under the standing permission (AGENTS.md rule 5: `main` pushed and item 3829070317 updated once `tools\test.ps1`
passes), merged into `main` together with `remix-workers` (S1) as `ff2343ef` and pushed (`cf8d7137..ff2343ef`, five
LFS objects, 71 MB). The merge's hook built the package here and uploaded item 3829070317 as
**`0.0.0-dev.20261117102000+a8e6cb04`**: content digest `52682d8a...`, Steam sending a 33.7 MB delta of the 2.2 GB
archive; its one change note is the changelog's two new sections, this round's and the geometry workers'. The push's
hook found the inputs unchanged. The field game deploys it at its next start, with the new `d3d9.dll`.
