# 0142: No Windows Error Reporting snapshot of the game, and no texture preload at the end of a load

- Status: Accepted 2026-11-10 (R28)
- Context: GitHub issue 2 (an RX 6700 XT player, 2026-11-09): when the game freezes or crashes, "a singular instance
  of gmod listed on task manager will usually persist and refuse to close for a while even after 'end task'", with "a
  gargantuan spike in Ram usage from a few hundred megabytes to 97-99 percent memory usage"; the user: several players
  report near memory overflow, one with 24 GB of RAM and an 8 GB RTX 5060 and 654 Workshop add-ons. The diagnosis is
  [handover/issue-2-memory-report.md](../handover/issue-2-memory-report.md); the user, 2026-11-10: "Resolve Issue 2".
  Loader changes need the user's approval (2026-11-08), so both decisions are in the package.

## What the diagnosis measured

- **The spike and the lingering process are Windows Error Reporting's snapshot.** When the game fails fast
  (`0xC0000409`), Windows copies the dying process (copy on write) before it reports it, and charges the copy the
  game's whole private memory again: +22 to +26 GB of system commit within three seconds for an RTX game with the 654
  add-ons (20.8 GB of private bytes), an 18 GB larger page file, the game's working set trimmed into the page file,
  and a process that stayed 11-12 s. End task removed the process, not the copy. A plain 8 GB Python process showed
  the same on this Windows 11 with default settings.
- **With `WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH` set in the game** (`werapi.h`), the same injected crash added
  0.06 GB of commit, trimmed nothing, and the game was gone in 5.8 s; Windows filed the same report, dump included.
- **At the end of every load Source draws one triangle with each loaded texture**
  (`mat_forcemanagedtextureintohardware`, default 1; `CacheUsedMaterials` ends with `ForceAllTexturesIntoHardware`),
  and the Remix runtime makes a GPU image for every texture drawn: 7,574 images (4.87 GB) in one pass with the
  add-ons, where the map with the RTX package alone grows to about 2,540 (1.17 GB). With the convar at 0 the pass is
  gone: 470 to 642 images after the load, a peak of 7.06 GB of dedicated GPU memory instead of 10.96 GB. An 8 GB card
  spills the difference into shared memory, which is system RAM. The same pass ran at later precaches (R13-B counted
  1,128 images at the AR2's alt-fire).

## Decision

1. **The engine guard switches Windows Error Reporting's snapshots off for the game.** `gmod13_open` of
   `gmcl_`/`gmsv_nlengineguard_win64.dll`, in every realm, calls
   `WerSetFlags(WerGetFlags() | WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH | WER_FAULT_REPORTING_DISABLE_SNAPSHOT_HANG)`
   (`engine_guard/crash_report.cpp`; kernel32's functions resolved at run time; where Windows refuses the hang flag,
   the crash flag alone). The menu realm loads the module at menu start (R24), so the flags are set before any map
   loads. The process's other flags are kept, and `nlengineguard.crash_snapshots_off` and `.crash_snapshots` say how it
   went. The report and its dump are unchanged: Windows reads the suspended process instead of a copy.
2. **RTX sessions run with `mat_forcemanagedtextureintohardware 0`.** The fixes' RTX settings
   (`packages/fixes/garrysmod/garrysmod/cfg/autoexec.cfg`) name it, so it is one of the package's `session_cvars`
   (`mat_` names are allowed, [ADR 0010](0010-rtx-session-extras.md)): the loader writes it into
   `nativeloader_session.cfg` at every RTX start. It is not an archived convar, so nothing of it stays for a start
   without RTX, and Lua cannot set it (the game refuses it from `RunConsoleCommand`). A texture gets its GPU image
   when something draws it, which is what the runtime's managed textures (R13-B) already do for every texture
   released after a minute without a draw.

## Consequences

- A crashed RTX game no longer doubles its memory while Windows reports it, and leaves sooner. Covered: every crash
  after the menu's Lua has started. Not covered: a crash earlier in start-up, when the game is still small, and a
  start without RTX, where the loader hides the package's add-ons (the loader could set the flags for both, next to
  `observer::disable_window_ghosting()` in `loader/proxy/startup.cpp`; not done, a loader change).
- With hundreds of add-ons the end of a load no longer makes thousands of GPU images for textures that were only
  precached, nor does a later precache. In an RTX session the map itself is drawn whole from its first frame
  (`r_novis 1`, no frustum or occlusion culling), so its textures get their images in the first frames as before;
  what waits for its first draw is content that was precached and never shown.
- Not changed by either: the RAM the game holds during play for the add-ons' textures (5.6-5.9 GB of CPU copies in
  the driver's host-visible memory, which Windows cannot page out), and the crashes themselves. The fail-fast at
  `engine.dll+0x34b6bc` that every one of them ended in is GMod's own crash handler failing while it writes its
  report (R28, RESEARCH): whatever the first fault, a GMod crash on this path reaches Windows Error Reporting,
  which is why the snapshot mattered. Both are in the R28 report as open.
- The engine guard module is rebuilt and imported (`tools/ci/pins.json` records the build); no loader or runtime
  change.

## Alternatives considered

- **Set the flags from the loader.** Covers start-up and starts without RTX too, but needs a loader release; the
  module reaches players with the Workshop item. Offered to the user in the R28 report.
- **Leave the snapshot and tell players to enlarge the page file.** The advice stays in the stability guide for the
  game's own memory, but a copy of 20 GB that no player asked for is not something a page file should pay for.
- **`mat_forcemanagedtextureintohardware 0` only for the smaller memory profiles.** The convar must be set by the
  session cfg (Lua cannot), which is the same for every profile; a module could set it through the engine's convar
  interface, but the pass has no benefit under this runtime at any size: what it uploads beyond the drawn map is what
  the memory profiles release again.
- **Keep the textures' CPU copies in pageable memory** (a runtime patch: ordinary process memory or a page-file
  backed section, uploaded through staging). It would let Windows trim the 5.6 GB of copies; larger and riskier than
  this round, and left open.
