# 0239: The load accelerator caches links, junctions and the Model Hotloader's character packs

- Status: Accepted 2026-11-16 (the user chose item A2 of the second load speed-up plan: "H1, A2, H2, H3")
- Decided by: the agents, from the field measurements of the plan (`out/load-speedup-2/PLAN.md` in the main
  checkout); package only: the `load-accelerator` part (`fs_accel/`), its add-on and the companion's menu script. No
  loader change.
- Supersedes in part: [0140](0140-the-load-accelerator.md), decision 2's list of the folders cached: "except links,
  junctions, the Model Hotloader's `mmdhl_*` (its worker writes there)". The rest of 0140 stands.
- Report: [load-speedup-2-report.md](../handover/load-speedup-2-report.md).

## Context

GMod tries every loose add-on folder on disk for each game file before the mounted archives. R26's accelerator answers
"not there" from directory listings for the plain folders, but left out links and junctions (a subtree watch of
`garrysmod/addons` does not follow them) and the `mmdhl_*` folders (on the assumption that the Hotloader's worker
writes there while the game runs). The user's field game has 53 loose folders: 8 are links or junctions (4 of them
pointing at folders that no longer exist) and 4 are `mmdhl_*`. Per map load the accelerator answered 3.0-3.6 million
lookups from memory, and 0.75-0.89 million still went to Windows through the loader's hooks, most of them into those 12
folders: 6.9 s of the main thread inside the file system calls of one modern_house load (sampled), a lookup through a
link costing about twice one into a plain folder. The `mmdhl_*` folders turned out to be character packs the loader
deploys before the game starts (`data_static/mmdhl/...`); the Hotloader's imports and exports go to
`data/mmd_hotloader`, and nothing writes into `garrysmod/addons/mmdhl_*` while the game runs.

## Decision

1. **Links and junctions directly in `garrysmod/addons` are cached** when their reparse point is a junction or a
   directory symbolic link (read with `FSCTL_GET_REPARSE_POINT`; a relative link resolved against its folder) and:
   - **the target is a directory on a local fixed drive**: listed through the link as a plain folder, and watched with a
     `ReadDirectoryChangesW` of its own on the resolved target (its subtree);
   - **the target is missing**: every path through the link is answered `ERROR_PATH_NOT_FOUND`, as Windows answers it
     (checked by the tests for the open and the attribute query); the link itself goes to Windows. The nearest folder
     that exists on the way to the target is watched (its own entries): any change there drops the link, so a target
     that appears is seen.
   Any other kind of reparse point (cloud files, deduplication, app aliases), a network or removable target, a link to
   a file, or a missing target behind a file is not cached; at most 48 links are (a watch each).
2. **The `mmdhl_*` folders are cached like plain folders.**
3. **A link's watch drops its own link.** A change seen there, an overflow or an error drops that link alone, for the
   session; its watch then stops. A missing target that appeared between the classification and the arming of its
   watch is checked after arming, and its link is not cached. While any watch has an unread notification, nothing is
   answered, as for the others.
4. **Counted and shown**: `Status().links`; the menu's line ("54 loose add-on folders cached, 8 of them links or
   junctions" in the user's game) and the client's tally after a load name them.

## Consequences

- Most of the lookups that still reached Windows in the user's field game are answered from memory: per first map
  load 75,588 went on to Windows instead of 0.86-0.90 million (3.84 million calls, 3.76 million answered); no folder
  was dropped. Together with ADR 0238 the server's and client's phases of a load fell from about 16 s each to 9-12 s
  each (the report).
- A developer's junction to a working folder stays cached until something in it changes, then goes to disk for the
  session (as a plain folder that changes). A file another program drops into a linked target is seen once the watcher
  has read the change, the same short window ADR 0140 accepted for plain folders; an edited file shows as before
  (positive lookups always reach the disk).
- The verify mode (`nativeloader_load_accel_verify 1`) compares every answer, links included, with Windows.

## Alternatives considered

- **Asking the user to remove the four broken junctions**: saves part of it with no code, but only for this user, and
  the live links stay uncached; offered in the report as well.
- **Merging the package's folders** (R26's C3): declined in R26 (the user's answer 6) and unrelated to links.
