# 0140: The load accelerator: GMod's slow file system answered from memory, from the package

- Status: Accepted 2026-11-09 (R26)
- Context: the user, 2026-11-09: "Please proceed with the load speed-up optimization, during load there should be
  verbosity so user see the progress. ... implement each item to a deliverable state ..., decide which one is really
  necessary and which should be dropped, start with lower risk ones." The plan
  (`out/load-speedup/PLAN.md` in the worktree `recursing-cartwright-4600e1`, R24's evidence) and the user's answers to
  its questions: hooking or packing anything in the Workshop add-on is allowed (1); package only, reporting what cannot
  be done that way, and it should also run without RTX (2); on by default (3); a dropped-in add-on may wait for a
  restart, but an edited Lua or material file must show (4); the user's own Workshop items may be updated (5); the
  package keeps its add-on folders (6); the implementation is ours to choose (7); third-party add-ons may be patched
  only from the package and robustly across their updates, and the optimization should be general (8); no refusal
  after a GMod update: trust the patterns and the consistency checks (9).
- Builds on: [ADR 0010](0010-rtx-session-extras.md) and [ADR 0013](0013-rtx-only-addons-hidden-without-rtx.md) (what
  a start without RTX shows), [ADR 0126](0126-a-record-of-what-this-repositorys-modules-were-built-from.md) (this
  repository's modules), [ADR 0133](0133-the-multiplayer-notice-in-the-companion.md) and
  [ADR 0134](0134-what-a-map-load-is-doing.md) (the menu realm's scripts and the load overlay).

## What costs the load (R24 and the plan, RESEARCH.md)

With the user's 774 subscriptions an RTX gm_construct load took about 28 s until the game responded, 20 s without RTX.
Two costs on the main thread lead: failed file probes into the loose add-on folders (8.2 s with RTX, where the
package's 22-24 folder add-ons are mounted; 1.5 s without), and GMod's per-add-on search, which walks every entry of
every add-on for each `file.Find(pattern, <add-on title>)` (2.5-2.9 ms a call; Extended Spawnmenu makes 2,263 right
after a map loads: 4.7-5.5 s with the game frozen). The bundled bullet-break simulator also rebuilt the spawn menu on
every start.

## Decision

1. **A new package part, `load-accelerator`, in RTX starts.** Its add-on (`garrysmod/addons/nlloadaccel`, from
   `fs_accel/addon`) and its two modules (`gmcl_`/`gmsv_nlfsaccel_win64.dll`, from `fs_accel`, this repository's code,
   MIT). The companion's menu script `load_accel.lua` loads the module at menu start and installs part A for the
   process; the add-on's first autorun adopts it in the server and the client realm and sets up part B. The part is
   not marked `requires_remix` (nothing in it needs Remix), but the combined package is, so in a start without RTX the
   loader leaves its add-on out of GMod's searches like every other add-on folder of the package (ADR 0013), and GMod
   never mounts the package's own archive (its native files are outside GMod's whitelist): no Lua of the package runs
   there and nothing loads the modules. Running it without RTX (answer 2) takes a loader change, for example a
   part-level flag that keeps one add-on folder visible; the answer also says "package only, report what cannot be done
   that way", and loader changes wait for the user's approval, so none is made and the R26 report says so.
2. **A: the loose-folder negative cache.** Import hooks on `filesystem_stdio.dll`'s `CreateFileA/W` and
   `GetFileAttributesExA/W`, chained after whatever the slot held (the loader's read redirects in an RTX start, else
   Windows), answer "not there" for a read-only lookup inside a cached folder whose directory listing has no such name,
   with Windows' own error codes. Cached: every plain ASCII folder directly in `garrysmod/addons` except links,
   junctions, the Model Hotloader's `mmdhl_*` (its worker writes there) and two folders whose names differ only in
   case, and the missing `garrysmod/workshop`. A watcher drops a folder that changes; every positive lookup still
   reaches the disk, so edited files show (answer 4). Verify mode (`nativeloader_load_accel_verify 1`) asks Windows too
   and counts disagreements. The switches live in the installing copy's counters, so the module's other copy reaches
   them. Once the process shuts down nothing is answered and no lock is taken.
3. **B as an index, not a patch.** The plan's B patched `Addon::FileSystem::FindFirst`. Instead the module reads
   GMod's add-on table (found by the file system's exported `g_pFullFileSystem` and the RTTI name
   `.?AVFileSystem@Addon@@`; every link and size checked, every tree walk with a step budget so that links which never
   end are refused rather than followed, under SEH, nothing written; built again when its sizes or any list node
   change, at most every 2 s, and on `GameContentChanged`), and the add-on replaces Lua's `file.Find` for add-on titles
   only (not
   GMod's search paths, not date sortings), answering from the index. Two add-ons with one title give a name once, as
   GMod's search does; a wildcard in the folder part of a pattern goes to GMod (which answers none). The only callers of
   that search are Lua's, so this is as general as the patch (every add-on that searches every add-on gains), with no
   code of GMod's changed: a wrong answer is the worst a layout change could cause, and a self-test against GMod's own
   answers in three mounted add-ons comes before the first one (none to compare with: no index), with verify mode
   comparing every answer. The plan's B0 (a patch of Extended Spawnmenu alone) is dropped: B covers it generally
   (answer 8).
4. **C1: no spawn-menu rebuild on a fresh start.** The bullet-break simulator rebuilds the spawn menu after its
   settings-layout migration only when the menu already exists when its file runs (a Lua refresh), in the package's
   copy and in the user's Workshop item 3789611737 (its 0.19.15 with that change alone, as 0.19.16). The Workshop item
   is an ordinary add-on, mounted in every start, so this part also reaches starts without RTX.
5. **Progress while loading.** The load overlay's status line (ADR 0134) goes on with the number of file lookups the
   cache answered in this load, and the end-of-load summary names it; the client prints the load's tally (lookups
   answered, searches answered from the index).
6. **Off switches and fallback.** `nativeloader_load_accel 0` (archived) leaves the module out from the next start.
   It is the add-on's client convar, which the menu realm cannot see (RESEARCH, R24), so the client keeps
   `data/nativeloader/load_accel_off.txt` while it is 0 and the menu script reads that. The crash-loop guard is native,
   since the menu realm cannot write files: just before the hooks go in, `install()` writes
   `garrysmod/data/nativeloader/load_accel_pending.txt` with the process's id and creation time, and a thread of its own
   deletes it once a map has loaded with the hooks (the menu script tells it 10 s after the first load ends, the add-on
   5 s after `InitPostEntity`) and at least 20 s have passed: most lookups are in a load, and the menu opens well before
   one. A start that finds the marker of a process that is gone (a crash, a hang ended by force, a quit before a map
   loaded) leaves the hooks out once and deletes it; an environment variable naming the process makes the module's other
   copy refuse too, and a child process, whose id differs, ignores it. Another running game of the same install is no
   reason to refuse. Any failed check (imports, the game's folder, the table, the self-test) leaves that part off with
   one console line; GMod's own behaviour is always the fallback, and nothing changes on disk but the two files in
   `data/nativeloader`.

## Dropped, with the reasons

- **C2** (the companion's `i18n.lua` included 49 times): it returns its cached table already; what is left is the
  include's own search, which A makes cheap.
- **C3** (merging the package's folder add-ons): kept as they are (answer 6); A removes their cost instead.
- **D** (per-add-on blame in the summary), **E** (prefetch for cold loads; warm loads here read nothing from disk and
  no cold-cache measurement is possible without an administrator tool), **F** (ARC9's PNG icons, an ARC9-only patch or
  hooks in GMod's image library), **G** (memoizing Lua calls): not built.

## Consequences

- No native code of the package runs in a start without RTX (ADR 0010 and 0013 unchanged); the accelerator's modules
  sit in `garrysmod/lua/bin` there, unused, like the fixes' module. The loader's rules are unchanged (the item is
  allowlisted; ADR 0003).
- A folder add-on that a developer edits while the game runs stops being cached for the session; a file dropped into
  a cached folder by another program is seen once the watcher has read the change (for a moment after the drop a
  lookup of it may still be answered as missing; nothing in the package writes there while the game runs).
- A game quit before any map loads leaves the marker, so its next start goes without the hooks once.
- A GMod update that changes the add-on table's layout turns B off at the self-test or the consistency checks; one that
  stops `filesystem_stdio.dll` importing those functions leaves A off. Both say so in the console.
- The two modules are recorded in `tools/ci/pins.json` `repository_builds` like the engine guard's.
