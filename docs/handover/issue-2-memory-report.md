# Issue #2: lag, high RAM use, and a game that lingers after End task (diagnosis)

GitHub issue #2 (2026-11-09, an RX 6700 XT player, default configs): when GMod freezes or crashes, "a singular
instance of gmod listed on task manager will usually persist and refuse to close for a while even after 'end task'",
with "a gargantuan spike in Ram usage from a few hundred megabytes to 97-99 percent memory usage." The user added that
several players report near memory overflow; one, with 24 GB of RAM and an RTX 5060 (8 GB), shared their
subscriptions as Workshop collection 3836929038. During the investigation the user observed the game lagging without
any VRAM or RAM jump and asked what causes the lag, likely a heavy Lua call.

Diagnosis only, by Claude, 2026-11-09/10: nothing in the package, the runtime or the loader was changed. Evidence is
in this worktree's git-ignored `out/issue2/`; paths below are relative to it.

## In short

**1. The lag is Lua on the main thread, and one add-on is most of it.** With the collection on gm_friluft (a large
outdoor map whose content is loose files), the RTX game drew 7 frames a second (143 ms per frame); the same add-ons
without RTX drew 50 (20 ms). In the RTX game 60 % of the wall time was spent inside client Lua hooks, and three
quarters of that is **HyperReal FX** (item 3830761570, the collection's first entry):

- `HRX_StageB` (`PreDrawViewModels`) 49.4 ms per frame on average (worst 207 ms) and `HRX_StageC`
  (`RenderScreenspaceEffects`) 17.9 ms (worst 196 ms): about 67 ms of each frame. Without RTX the same two hooks take
  0.46 and 0.31 ms: the Lua is cheap, its render calls are not. Each frame it copies the back buffer several times
  (`render.UpdateScreenEffectTexture`), runs full-screen shader passes, and every half second reads a pixel back to
  the CPU (`render.CapturePixels`, `render.ReadPixel`), which waits for the GPU. Under RTX its screen-space targets
  are inert (the package's RTX guard says so at load), so all of this is cost without a picture.
- The package's own **light updater** (`packages/fixes/.../remixlua/cl/cl_rtx_light_updater.lua:1003-1029`) draws one
  helper model per map light every frame from Lua: 1.95 ms per frame for gm_friluft's 182 lights (10.7 us a light),
  and it was the most expensive client hook on gm_skyport, which has 4,606 lights (about 49 ms per frame at the
  same rate).
- Server side, many add-ons walk `ents.GetAll()` every tick (Combine MindHacks PLUS, NPC Tranquilizer Gun, BSMod,
  NPC Fall Damage, Status Effect Framework; Zipline even re-registers a net receiver in every `Think`). On gm_skyport
  (about 2,400 entities) they were the top server costs, and the hottest Lua lines were the base game's
  `Entity:__index`, `IsValid` and `GetConVarNumber` they call per entity per tick. In single-player the server runs
  in the same thread: at 7 frames a second about ten server ticks run back to back in every frame.
- With the collection the client has 3,150 hooks and 945 net receivers, the server 2,547 and 739.

**2. The lingering gmod.exe and the jump to 97-99 % are Windows Error Reporting's snapshot of the crashed game.**
When GMod fails fast (`0xC0000409`), Windows Error Reporting copies the dying process (a copy-on-write snapshot)
before it reports it, and Windows charges that copy the game's whole private memory again:

- On the RTX game with the collection (20.8 GB of private bytes) system commit rose by 22-26 GB within one to three
  seconds of WerFault starting, Windows grew the page file by 18 GB, trimmed the game's working set into a 5-10 GB
  modified list (page-file writes), and the process stayed 11-12 s. Ending it as Task Manager does removed the
  process in a second, but the snapshot's commit stayed until WER was done (3 s more).
- A plain 8 GB process shows the same on this Windows 11 with default settings, where no LocalDumps setting applies
  (+9.3 GB commit, its working set trimmed to nothing), so every player's Windows does this.
- With `WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH` set in the game (`werapi.h:69-72`), the same injected crash added
  no commit (+0.06 GB), trimmed nothing, and the game was gone in 5.8 s instead of 11.8 s; WER still filed its report
  with a dump.
- On a 24 GB computer a 20 GB game cannot be copied: commit goes past the limit, Windows grows the page file by tens
  of gigabytes and pages until WER finishes: the freeze, RAM at 97-99 %, and a gmod.exe that "refuses to close for a
  while". Meanwhile the crashed process's own working set (Task Manager's memory column) drops toward zero, its pages
  now held by the snapshot: the "few hundred megabytes" beside a full RAM gauge.
- End task on a game that is frozen but not crashed is not the problem: a Lua busy loop, a frozen post-load phase and
  a responsive game all ended within a second, without WerFault, their commit freed at once.

**3. RAM during play is the add-ons' textures, held in memory Windows cannot page out.**

- Source loads the textures of every material it precaches. With the collection on gm_skyport the runtime held
  5.6-5.9 GB of game textures, against 1.2 GB with the RTX package alone.
- Under RTX each such texture is a GPU image or a CPU copy in DXVK's host-visible memory
  (`src/d3d9/d3d9_common_texture.cpp:255-283`, "d3d9 texture copy", `HOST_VISIBLE | HOST_COHERENT | HOST_CACHED`),
  which the driver keeps resident. When commit ran short at a crash, Windows trimmed the game's private working set
  exactly down to its GPU-shared memory (5.99 of 5.99 GB, 6.99 of 6.99 GB) and no further.
- The minimum memory profile (what a 24 GB / 8 GB computer gets) moves this data but cannot free it: its 2 GiB budget
  released 2.85 GB of idle images after 60 s and read the data back into CPU copies.
- At the end of a map load Source draws once with every loaded texture (`mat_forcemanagedtextureintohardware`,
  default 1), and each draw makes the runtime create that texture's GPU image: 7,574 images (4.87 GB) at once. The
  game then wanted 10-11 GB of VRAM; an 8 GB card spills the rest into shared system memory, which is resident RAM
  too. With the convar at 0 that pass is gone (VRAM peak 7.1 instead of 11.0 GB); RAM stays.
- Peaks on gm_skyport with the minimum profile and the low tier: 22.8 GB private bytes, 12.1 GB working set, 11.0 GB
  GPU dedicated, 6.8 GB GPU shared. With the RTX package alone: 12.9 / 6.2 / 6.8 / 3.2 GB. With the collection but
  without RTX: 15.0 / 6.0 / 8.5 / 0.5 GB.

**4. The crashes that start part 2 are GMod's engine, not the add-ons or the package.** Six sessions crashed by
themselves with `0xC0000409`: with and without the collection, with and without RTX, on gm_construct and gm_skyport.
The five with a dump and an event-log entry are all parameter 5 (`FAST_FAIL_INVALID_ARG`) at `engine.dll+0x34b6bc`,
on an engine worker thread (started at `tier0.dll+0x1c9d0`, never the main thread). The same afternoon the PoC's own
game in another session's lab crashed at the same offset (Application log, 17:15), and this computer's WER archive
holds the same family from earlier field, PoC and RTX_c sessions (BEX64 in `engine.dll`, parameter 5). The dumps
hold 4-5 KB of that thread's stack and GMod ships no symbols, so the caller is not known.

## Recommended fixes

1. **Switch HyperReal FX's pipeline off in RTX sessions** (package only). HRX gates every stage on
   `HRX.IsActive()` and has its own `enabled` setting (server side, `lua/hrx/sh_settings.lua:77`); the companion can
   turn it off in RTX starts and say why, as R20-D and R24 do for other add-ons. More generally, add-ons whose
   screen-space targets the RTX guard marks inert could be listed in the companion with their measured cost.
   Expected: about 67 ms per frame back at gm_friluft's 143 (the next costs are the light updater and a HUD).
2. **Bound the light updater's per-frame work** (package only, the fixes' Lua): it draws all `known_lights` helpers
   every frame (`cl_rtx_light_updater.lua:1013-1016`). Drawing only lights near the camera or in view, or a slice of
   them per frame, keeps maps with thousands of lights from paying 10.7 us per light per frame.
3. **Turn off WER's snapshots for the game process.** One call early in the process:
   `WerSetFlags(WerGetFlags() | WER_FAULT_REPORTING_DISABLE_SNAPSHOT_CRASH | WER_FAULT_REPORTING_DISABLE_SNAPSHOT_HANG)`
   (kernel32 exports both; resolve them at run time to keep the bootstrap's KERNEL32-only import table).
   - **Package only** (no loader change, reaches players with the Workshop item): the engine guard's
     `GMOD_MODULE_OPEN` (`engine_guard/module.cpp:146`), which runs in the menu realm at start (R24) and in both
     game realms. Covers every crash after the menu's Lua starts.
   - **Loader** (needs the user's approval): `loader/proxy/startup.cpp:337`, next to
     `observer::disable_window_ghosting()`, also covers start-up and starts without RTX.
   - Measured: commit increase at the crash 22-23 GB -> 0.06 GB; the game gone after 5.8 s instead of 11.8 s; the
     Application log's event 1001 lists the same report files (dump included) with and without the flag. WER then
     reads the suspended process directly, so the process is held while it collects (5.8 s here, LocalDumps
     included).
4. **Turn off Source's end-of-load preload in RTX sessions:** `"mat_forcemanagedtextureintohardware": "0"` in the
   package manifest's `session_cvars` (`mat_` is allowed, `loader/core/src/manifest.cpp:517-530`; the loader writes
   it into `nativeloader_session.cfg` at every RTX start; it is not archived, so nothing is restored without RTX).
   Lua's `RunConsoleCommand` refuses it (`client.dll` lists it beside `mat_picmip` and `connect`). Measured: VRAM peak
   10.96 -> 7.06 GB with the collection. Not changed: RAM, and the 40-43 s from the end of the load to the first
   ray-traced frame. Not measured: R13-A's AR2 alt-fire trigger with the convar off, hitches when textures are first
   drawn later.
5. **Keep the game textures' CPU copies in pageable memory** (runtime patch, package only, larger): ordinary process
   memory or a page-file-backed section that Windows can trim, uploaded through staging when a texture is first
   drawn. Most of the 5.6 GB are precached textures that are never drawn. DXVK 2.x's D3D9 memory allocator does
   something similar for 32-bit games.
6. **Investigate the engine fail-fast separately** (it is what sends the game into WER). A full-memory dump of one
   crash (a one-off WER LocalDumps DumpType 2, the user's call) or a debugger attached to the worker thread would give
   its caller.
7. **Tell players** (the Performance and memory guide, `docs/STABILITY.md`): with hundreds of add-ons an RTX session
   commits 20+ GB and a crash makes Windows copy it once more; keep a system-managed page file on a drive with free
   space at least twice the game's commit; after a crash, wait for WerFault (End task does not release the copy);
   post-process add-ons such as HyperReal FX cost far more under RTX and show nothing there.

Fixes 1, 2 and 4 are about frame rate and VRAM; 3 about the lingering game and the spike; 5 about the RAM held during
play.

## What a 24 GB / 8 GB computer gets from the loader

Loader 0.13.0 and later ([ADR 0101](../decisions/0101-memory-profiles.md), `loader/core/src/memory_profile.cpp`): an
8 GB card reads about 8,150 MiB (>= 7,680) and 24 GB of RAM about 24,400 MiB (>= 14,336 and < 28,672), so both pick
**minimum**: no characters kept ready, game textures over VRAM / 4 (about 2,040 MiB) released after 60 s without a
draw, CPU copies released once the image holds the data. The RTX 5060 is an x60 card with 8 GB, so the performance
tier is **low** ([ADR 0062](../decisions/0062-loader-layers-performance-tiers-and-gpu-dumps.md)). An RX 6700 XT
(12 GB) is also **minimum** and gets no NVIDIA tier layer. The sessions here set `remix.memory_profile` minimum and
`remix.performance_tier` low, which give the same budgets (`[RTX Managed Textures] budget: 2048 MiB (set)`, copies
released). An older loader leaves the runtime to compute the same values itself.

## How it was reproduced

- **The add-on set.** The collection's public page lists 657 items; Steam's public API returns result 9 (not visible)
  for the collection itself and for 3 of them. The other 654 (64.0 GB as uploaded, 65.5 GB unpacked, 125,145 files:
  22.75 GB of VTF, 28.8 GB of BSP, 175 maps, 940 autorun Lua files) were downloaded anonymously with Valve's SteamCMD
  (Valve's signature checked) into `steamcmd*/` (deleted after the report). The user's Steam client, account, subscriptions and Workshop folder
  were not used. None of the 654 is a native-loader package or carries Remix mods or binary modules, so the
  reporter's loader deploys nothing from them either (`collection/gma-index.json`; the item list with IDs, titles
  and sizes is `collection/details.json`, the Lua files each item ships `collection/lua-owners.json`).
- **The install.** The PoC was held all afternoon by another session's lab (`brmovie-rtx`, a `poc_session.py` run with
  `--settle 30000`); the parent session agreed to a copy. These sessions ran on a vanilla copy built with
  `tools/steam/make_vanilla_copy.py` from the field install's depot files (each of the 2,877 files SHA-1 checked while
  copied, nothing taken from the PoC) at `out/issue2/game`, with this branch's loader (e4c84fc) and the published
  package of item 3829070317 (`0.0.0-dev.20261109133732+adc5cf08`), through `tools/poc_session.py --root`.
  `tools/steam/verify_install.py` ran on it only after the last lab, not before the first: 2,877 depot files OK, none
  missing or different, nothing extra in `bin\win64`; only the user-config `autoexec.cfg` differs, as the copy tool
  does not copy it (`verify-copy.json`). Every lab took a `field_snapshot.py` snapshot first and rolled back after
  (all six clean); GMod's shared registry key was checked against its value before the first session, before and after
  each lab. The PoC and the field install were not touched; this lab ended only gmod.exe processes it had started
  itself (by process id and path).
- **Mounting without subscriptions.** GMod x64 does not mount a loose `.gma` in `garrysmod/addons`
  ([RESEARCH.md](../RESEARCH.md) section 13). A test add-on (`probe/`) mounted the 654 archives with `game.MountGMA`
  after the first map and then changed level, so their Lua ran as at any map load. `game.MountGMA` refused absolute
  paths (6 of 6) and took paths under `garrysmod/` (hard links in the copy's `garrysmod/i2gma`): 654 mounted, 0
  failed, 125,145 files, in 1.5-6 s. Sessions ran with `-noworkshop`.
- **The sessions.** 1920x1080 windowed, `-insecure`, gm_construct, then gm_skyport (the largest map, a 1.68 GB BSP) or
  gm_friluft; waves of ten NPCs from `list.Get("NPC")` (706 classes), 20 weapons from `weapons.GetList()` (700), a
  Combine soldier and map changes; for the crash tests a fail-fast injected 180 s after the map loaded (a remote
  thread started at an `int 29h` in ntdll with ECX = 5: the engine crash's exception and parameter). A sampler
  (`tools/memsampler.py`) read every second the game, its helpers and WerFault (private bytes, working set, private
  working set, GPU dedicated and shared memory), the committed private memory by protection every 10 s, and the
  system's commit, limit, free, standby and modified memory. Driver `tools/lab.py`, analysis `tools/analyze.py`,
  dumps `tools/mdmp.py` and `tools/mdmp_stack.py`, WER without the game `tools/wer_probe.py`.
- **The Lua profiler** (`probe/lua/autorun/nl_issue2_prof.lua`, driven by `tools/lab.py`, read by
  `tools/prof_report.py`), per realm: every function in `hook.GetTable()` and `net.Receivers` wrapped and timed with
  `SysTime()`; optionally a count hook (`debug.sethook`, every 1,000 VM instructions) sampling all Lua; frame times.
  The first run (`main-D`, gm_skyport) used the count hook too and slowed the game about tenfold, so its numbers are
  only a ranking; the clean run (`main-E`, gm_friluft) timed frames alone, then hooks alone, 30 s each, 120 s after
  the map loaded.

### Where this differs from the reporters

- An RTX 5090 (32 GB) and 64 GB of RAM: the loader's budgets were the 8 GB / 16 GB computer's, but neither VRAM nor
  RAM ran out for real. Other sessions' jobs on this computer (another lab's PoC game at times, two Python processes
  of 15 GB each, NVIDIA Overlay with 22.9 GB of dedicated memory) lowered the game's driver budget to 12-13 GB in one
  run, about an RX 6700 XT's. No AMD card was available. A slower CPU stretches every Lua cost above.
- **System-wide numbers are shared.** Commit, its limit, the free, standby and modified lists include those other
  jobs; the per-process numbers (this lab's gmod.exe, found by its process id and path) are the game's alone. The WER
  findings rest on increases within one to three seconds of WerFault starting, repeated in three game crashes and
  two Python probes.
- **Endings with exit code 1 and no dump** are not attributed: the RTX-off session of `main-A` (its window stopped
  answering for ten minutes after collection add-ons' Lua errors and a procedural-gib add-on started, then it ended
  with exit 1) and the two NPC rounds of `main-E` may be content or another lab's harness ending games; no finding
  above uses them.
- Archives mounted with `game.MountGMA` are not in GMod's add-on table: the spawn menu's add-on tree and R26's add-on
  index do not see them. A map inside a mounted archive logs "Couldn't write cache/map_pack.bsp to mount embedded
  content!" (GMod writes the file but reports a failure), so a map's embedded textures may be missing: the measured
  texture memory is if anything low.
- This computer has a WER LocalDumps setting for gmod.exe (HKLM, DumpType 0, CustomDumpFlags 0x1965, folder
  `GarrysMod_RTX_c\_debug_tools\hangdumps\wer`); players normally do not. The Python probe, which no LocalDumps
  setting covers, shows the snapshot without it.
- This lab's processes inherit error mode `SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX` from the agent harness,
  which keeps WER away from a plain process (the probe resets it to 0, as a normal launch has it). The game's crashes
  reached WER anyway.

## Evidence

### The lag (`runs/main-E`, gm_friluft, collection mounted)

| | RTX (`rtx-col-prof2`) | No RTX (`off-col-prof2`) |
|---|---:|---:|
| Frame time, frames alone (30 s): average / p50 / p95 / worst | 142.7 / 112.3 / 244.7 / 822.6 ms | 19.9 / 18.2 / 27.0 / 775.0 ms |
| Frames per second | 7.0 | 50.2 |
| Client hooks, all (hooks alone, 30 s) | 599.9 ms/s, 90 ms a frame | 505.4 ms/s, 10.8 ms a frame |
| Server hooks, all | 78.1 ms/s | 109.3 ms/s |
| `HRX_StageB` (`PreDrawViewModels`), average / worst | 49.37 / 206.7 ms | 0.46 / 12.5 ms |
| `HRX_StageC` (`RenderScreenspaceEffects`) | 17.91 / 196.3 ms | 0.31 / 8.8 ms |
| `RTXReady_RenderLightUpdaters` (the fixes, 182 lights) | 1.95 / 9.4 ms | (not loaded) |
| `holohud2` (`PreDrawHUD`, D/GL4 HUD) | 1.63 / 6.0 ms | 0.84 / 2.0 ms |
| `nativeloader_effect_categories` (the package) | 0.83 / 4.7 ms | (not loaded) |
| `gBright_PostProcess` | 0.68 / 2.5 ms | 0.28 / 2.0 ms |

- HRX's three stages: 443.9 of the 599.9 ms/s of client hook time (74 %).
- gm_skyport (`runs/main-D/rtx-col-prof`, with the count hook, so a ranking only): client
  `RTXReady_RenderLightUpdaters` (4,606 lights: "[gmRTX - Lightupdater] Processed 4606 / 4606 lights") 43 % of
  client hook time, then `HRX_StageB` 24 %; server `CMH_PlayerMindHack`, `LambdaTranq_OnServerThink`,
  `SEF_SERVER_PASSIVE_PassiveTenacity1`, `NPCFallDamageTracker`, `BSModThink`, `detect_rope_activity`; the most
  sampled server lines `lua/includes/extensions/entity.lua:30` (`Entity:__index`), `util.lua:316` (`IsValid`),
  `util.lua:588` (`GetConVarNumber`). The add-ons' code quoted here is kept in `evidence/addon-excerpts/` (for
  example 3667518841 `lua/autorun/tbp_stuff.lua:441-470`, a player loop around an `ents.GetAll()` loop with
  networked-var reads; HRX's `cl_pipeline.lua` stages and `ReadRTPixel`).
- The RTX game without the collection could not be profiled on gm_friluft (that session's engine crashed on
  gm_construct first); on gm_skyport it completed a whole tour (`main-A/rtx-none`).

### Memory by session (gm_skyport, peaks)

| Session (`runs/<lab>/<session>`) | Private bytes | Working set | GPU dedicated | GPU shared | Game textures (runtime) |
|---|---:|---:|---:|---:|---|
| RTX + collection (`main-A/rtx-col`) | 22.84 GB | 12.13 GB | 10.96 GB | 6.75 GB | 7,574 images / 4.87 GB in one pass |
| RTX + collection, convar 0 (`main-B/rtx-col-nf`) | 20.16 GB | 13.13 GB | 7.06 GB | 6.99 GB | 470-642 images, CPU copies 5.59 GB |
| RTX, only the map's archive (`main-A/rtx-none`) | 12.88 GB | 6.19 GB | 6.80 GB | 3.15 GB | grows to ~2,540 images / 1.17 GB |
| No RTX + collection (`main-A/off-col`) | 14.95 GB | 5.98 GB | 8.47 GB | 0.45 GB | (native D3D9) |

- Private bytes include the VRAM the NVIDIA driver maps into the process as write-combined memory (R13-B section 1):
  at the RTX peak 11.25 of the 22.84 GB were write-combined, 11.25 read-write. The working set is the RAM the game
  holds; GPU shared memory is system RAM the GPU can reach.

### Source's end-of-load pass

`main-A/poc/rtx-col/remix-dxvk.log`, `[RTX Managed Textures]` (one line per pass):

| Time | Resident images | Resident | CPU copies | Created by draws (total) | Released |
|---|---:|---:|---:|---:|---:|
| 15:10:25 (gm_construct, collection mounted) | 39 | 0.03 GB | 0.05 GB | 670 | 0 |
| 15:12:44 (gm_skyport, first pass after the load) | 6,934 | 4.65 GB | 4.11 GB | 7,574 (4.87 GB) | 0 |
| 15:13:10 | 7,093 | 4.72 GB | 0.93 GB | 7,735 | 0 |
| 15:14:48 (60 s without a draw) | 6,159 | 2.00 GB | 3.73 GB | 7,949 | 1,148 (2.85 GB) |

- `[RTX Memory]` at 15:13:57: app textures 5.85 GB, acceleration structures 1.07 GB, opacity micromaps 0.47 GB,
  render targets 0.36 GB.
- **The mechanism.** GMod's `materialsystem.dll` holds the convar `mat_forcemanagedtextureintohardware` (0xb4e38)
  and, side by side, "texture preload" and "engine/preloadtexture" (0xbe4d0, 0xbe4e0);
  `materials/engine/preloadtexture.vmt` is in `hl2_misc_dir.vpk`. In Source's material system `CacheUsedMaterials`
  ends, while the convar is 1, with `ForceAllTexturesIntoHardware`: one triangle drawn with each texture of the
  texture list bound as that material's `$basetexture`, so that D3D9 pages it in. R13-B counted the same pass on its
  smaller library (1,064 images at every map load, 1,128 at the AR2 alt-fire precache) and named the draw path
  (`UploadManagedTextures` from `PrepareTextures`).
- **The A/B.** `main-B/rtx-col-nf` set the convar to 0 before the level change (the console echoes
  `"mat_forcemanagedtextureintohardware" = "0" ( def. "1" )`). After gm_skyport: 470 resident images (0.41 GB), CPU
  copies 5.59 GB, GPU dedicated 5.45 GB against 9.88 GB at the same point with the default.
- From the end of the load to the first ray-traced frame ("Camera cut detected"): 40 s with the default, 43 s with
  the convar at 0, 96 s on the first, cold run: the wait is other post-load work.

### The crashes and WER

The six crashes (`wer-dumps/`, moved out of the RTX_c folder; `tools/mdmp.py`, `tools/mdmp_stack.py`):

| Lab / session | Map | RTX | Collection | When |
|---|---|---|---|---|
| `main-A/rtx-col` | gm_skyport | on | yes | third NPC wave |
| `main-B/rtx-col-nf` | gm_skyport | on | yes | third NPC wave |
| `main-D/rtx-col-prof` | gm_skyport | on | yes | while quitting after a profiling round |
| `main-D/off-col-prof` | gm_skyport | off | yes | idle, a minute after the load |
| `main-D/rtx-none-prof` | gm_skyport | on | no | idle, 20 s after the load |
| `main-E/rtx-none-prof2` | gm_construct | on | no | idle, before anything was mounted |

All exited with `0xC0000409`. The first five: parameter 5 at `engine.dll+0x34b6bc` (dump and Application log event
1000), on a worker thread started at `tier0.dll+0x1c9d0`, logged by Windows as BEX64 in `engine.dll` (event 1001).
The sixth left neither a WER dump nor an event, so its offset is not known. GMod's own crash handler wrote a report
for all six (`evidence/engine-crashes/<lab>/`, a minidump and a text with each realm's Lua stack): in five no realm was
in Lua; in the RTX-off one (`main-D/off-col-prof`) the client was inside HRX's `render.CapturePixels()`
(`ReadRTPixel`, `cl_pipeline.lua:446`, from `StageB`). Since the sessions without the collection crashed too, HRX is
not the cause, but a pixel read-back waiting on the worker thread is a lead for fix 6.

`main-A/rtx-col/mem.jsonl`, seconds after the session's start:

| s | Event | Game private / private WS | System commit / limit | Modified list |
|---:|---|---|---|---:|
| 676.5 | before | 22.83 / 11.25 GB | 77.4 / 86.6 GB | 0.00 GB |
| 677.5 | WerFault (pid 36348, not openable) | 22.83 / 11.25 | 86.5 / 86.6 | 0.01 |
| 678.5 | the page file grows | 22.83 / 11.25 | 98.9 / 99.2 | 0.00 |
| 680.5 | | 22.83 / 7.47 | 103.4 / 103.7 | 5.30 |
| 682.5 | second WerFault (parent: the game) | 22.83 / 6.76 | 77.5 / 97.3 | 0.00 |
| 689.5 | the game exits | 10.60 / 2.62 | 65.3 / 97.0 | 0.32 |

WER's snapshot, measured on purpose:

| Test | Process at the crash | Commit increase | Working set after | Modified list | Gone after |
|---|---|---:|---|---:|---:|
| Game, injected fail-fast (`main-C/rtx-col-ff`) | 20.76 GB private, 10.10 WS | +23.37 GB | 5.99 GB (= GPU shared) | 6.17 GB | 11.77 s |
| Game, `WerSetFlags(128)` first (`main-C/rtx-col-ff-nosnap`) | 13.78 / 5.63 | +0.06 GB | 5.63 GB | 0.78 GB | 5.76 s |
| Game, terminated 1 s into WER (`main-C/rtx-col-ff-endtask`) | 20.91 / 9.60 | +22.09 GB | 4.45 GB | 9.64 GB | 1.06 s; commit back 3-4 s later |
| Python, 8 GiB, error mode 0 (`wer-probe/default-8g-mode0.jsonl`) | 8.02 / 8.01 | +9.3 GB | 0 | | 2.9 s |
| Python, 8 GiB, `WerSetFlags(128)` (`wer-probe/nosnap-8g-mode0.jsonl`) | 8.02 / 8.01 | 0 | 8.01 | | 1.0 s |

- `WerSetFlags` was called inside the game by a remote thread and checked with `WerGetFlags` (flags 128, S_OK).
- Every test that reached WER filed the same report: event 1001 lists `WER.*.tmp.dmp` with the metadata, with and
  without the flag.
- The extra commit equals the crashed process's private bytes and ends with the first WerFault, which is what a
  copy-on-write snapshot is charged; `werapi.h` (Windows SDK 10.0.26100.0, lines 69-77) documents the two flags that
  switch crash and hang snapshots off.
- End task on a game that is not crashed (`user32.EndTask(hwnd, FALSE, TRUE)`, as Task Manager does): a Lua busy loop
  with the window hung (`main-B/rtx-col-hang`), the post-load freeze with the window hung (`main-C/rtx-col-burst-endtask`)
  and a responsive game (`main-B/rtx-col-burst-endtask`): gone within a second, no WerFault, commit freed at once.

## Not reproduced, and open questions

- **An AMD card and a real 24 GB / 8 GB computer.** The snapshot is Windows' own and applies to any GPU; so do the
  textures' host-visible copies and the Lua costs. Whether AMD's driver also maps VRAM into the process's private
  bytes (and so into the snapshot's commit) as NVIDIA's does was not measured. The spill into shared memory on an
  8 GB card and the page-file growth past 24 GB of RAM are arithmetic from these measurements, not observations. The
  players' own `native-loader\logs\sessions` folders (the owner has asked for them on the issue) would show the
  commit at their crash in `memory.csv`.
- **Hangs.** WER's hang snapshot (the second flag) was not triggered here: with window ghosting off (loader 0.12.1)
  there is no "Not Responding" dialog, and End task terminated the game without a hang report.
- **The engine crash's caller.** Not found (see fix 6). Whether this lab's harness raises its rate is not excluded;
  the same signature in this computer's earlier WER archive argues it is the game's own.
- **The 3 collection items** the API does not show could not be downloaded.

## Side effects of this investigation

- Windows wrote crash dumps of these sessions' games (98-366 MB each) into
  `GarrysMod_RTX_c\_debug_tools\hangdumps\wer` (this computer's LocalDumps setting). Each of this lab's seven was
  moved out, hash checked, to `out/issue2/wer-dumps/` (`moved.jsonl`); the two older dumps there and two newer ones
  of the PoC's own game (another session's lab, pids 21168 and 33816) were not touched. Windows also filed its usual
  reports in `C:\ProgramData\Microsoft\Windows\WER` and the Application log.
- The Remix runtime added its usual `crashpad_wer.dll` value for the copy's runtime folder under
  `HKCU\Software\Microsoft\Windows\Windows Error Reporting\RuntimeExceptionHelperModules`, as every new runtime folder
  does (this computer lists 359 such values, one per deployed runtime folder; one is this lab's copy).
- One run's rollback ran its uninstaller while the next run's game was starting (the labs overlapped); that run was
  discarded, the copy rebuilt, and a lock added.
- After the report, as the parent session asked, the vanilla copy, the files each rollback had moved out of it
  (`runs/*/snapshot/debris`) and the downloaded collection with SteamCMD were deleted (144 GB freed on H:). Kept in
  `out/issue2` (2.3 GB): the item list (`collection/`), the run logs, samples and session records (`runs/`), the WER
  dumps (`wer-dumps/`), GMod's crash reports, the quoted add-on code and the download logs (`evidence/`), the WER
  probe (`wer-probe/`), the tools and the test add-on.
