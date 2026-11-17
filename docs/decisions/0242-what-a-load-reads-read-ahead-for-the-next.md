# 0242: What a load reads, read ahead for the next one

- Status: Accepted 2026-11-17 (the user: "Let's also do the remaining 6 points in the plan. Every second matters"; item
  E of the second load speed-up plan)
- Decided by: the agents; package only: the `load-accelerator` part's module (`fs_accel/prefetch.cpp`, `hooks.cpp`,
  `module.cpp`) and add-on, the companion's `menu/load_accel.lua` and `menu/loading_status.lua`. No loader change.
- Report: [load-speedup-3-report.md](../handover/load-speedup-3-report.md).

## Context

A load reads gigabytes of game files (add-on archives, the map, models, materials, sounds). When Windows' file cache
holds them (warm) the user's modern_house load took about 26-30 s after the second round; after the cache let them go
(a reboot, memory pressure) the main thread waits on the disk: the plan's cold run (2026-11-16, before the second round)
took 19 s longer for the first load on this NVMe drive, 5-6 s of disk waits in each phase, and several times more on a
SATA SSD or a hard disk. Windows' own prefetch serves an application's start, not its later loads.

## Decision

1. **Record.** While the load overlay records a load (from its start to its end), the module's hook on
   `filesystem_stdio.dll`'s `ReadFile` import notes which 64 KiB blocks of which file the load reads, in the order the
   files are first read. The offset comes from the read's `OVERLAPPED`, or for a synchronous read from the handle's
   position, asked before the read; the file from the `CreateFile` hooks or, for a handle opened earlier (the
   Workshop's archives), from Windows. Not recording, the hook only passes the call on.
2. **List.** A load that reached the game is saved as its map's list,
   `garrysmod/data/nativeloader/prefetch/<map>.lst` (an extension Lua's `file.Write` cannot make): local fixed drives
   only, not the game's `cache` or `data` folders, 8 GiB at most, each file with its size and time. A game's first load
   is also written as `last.txt`.
3. **Read ahead.** At menu start the module reads the last first load's list ahead; when a load's map is named and has
   a list (not the one read ahead last), that list. A thread of the module's own opens each file only when it is a plain
   file on a local fixed drive of the size the list names, marks its reads low I/O priority, and reads the listed
   blocks 1 MiB at a time into a buffer it throws away, at most a quarter of the memory (4 GiB); a later read-ahead
   supersedes it. Windows keeps what it read in its file cache.
4. **Switch:** `nativeloader_load_accel_prefetch` (archived, 1), which the client keeps for the menu realm as a file.

## Consequences

- Expected: a cold load finds most of what it reads in the cache when the menu was up long enough (or reads it
  sooner); a warm load reads the list from the cache at memory speed, on a thread of its own. In the user's game a modern_house load
  read 1,836 MB of 1,962 files in 85,869 reads, and the menu read the list ahead (1,765 MB). Its effect on a cold load
  was not measured before the hand-over (the report says how).
- The lists hold paths of the player's own files on their computer (game and Workshop folders); nothing leaves it.
- A list names what one load read; the next load of another add-on set reads some blocks it does not need (bounded by
  the budget) and misses some it does.
- What the Remix runtime reads itself (its mods' textures) is not recorded.

## Alternatives considered

- **Whole files:** the Workshop archives are up to gigabytes, of which a load reads a part.
- **Very low I/O priority (background mode):** also lowers the cached pages' memory priority, so Windows would drop them
  first.
- **In the loader (before the game starts):** a loader change, which needs the user's approval and a release; the
  module runs at menu start, seconds later, without one.
