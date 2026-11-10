# Memory and stability

For players with an 8 GB GPU or 16 GB of system RAM. The same guidance is in the game's **RTX Remix
tab > Start here > Memory and stability guide** (console: `nativeloader_stability_guide`).
Since R14-H the button is **Performance and memory guide** and the guide's page is **Performance and
memory**, with the memory profile and the crash advice shortened to what a player does.

## Before playing

- Use a **system-managed Windows page file** on a drive with at least **30 GB free** so Windows has
  room to grow it. In Windows' Virtual Memory settings, choose automatic management or a
  system-managed size on that drive, apply it and restart Windows if requested. A page file raises
  the system's commit limit; it does not add VRAM or guarantee that a heavy scene will fit.
- Close browsers and stop OBS recording before starting Garry's Mod.
- Open **Task Manager > Performance > Memory** and watch **Committed**. In `used / limit`, the first
  number is memory Windows has promised to programs; the second is how much it can promise in total.
  If they are close, close other apps or use fewer heavy models. Free RAM and free commit are
  different readings; an allocation can fail when commit reaches the limit.
- Turn **frame generation off** in Remix's Alt+X menu and use **User Settings (user.conf): Save**.
  Otherwise a saved value can return at the next start.
- Keep **Garry's Mod's texture detail at its highest**. Lowering it changes the texture data Remix
  hashes and can break replacement matching. Use a lower loader tier or fewer heavy characters to
  reduce memory pressure instead. A character pack with 2048 px PBR maps is lighter than a 4096 px
  pack; the original game textures and the Remix replacement maps both have a cost.

## Check the loader before using its 0.11.0 settings

Open `garrysmod\data\native-loader\status.json`. The **0.11.0-only** instructions below apply only
when it has an `activation.performance_tier` object. The Workshop companion updates independently
of `bin\win64\winmm.dll`; update that DLL to loader 0.11.0 or later if this field is absent. Older loaders
(including 0.10.1) reject the new tier and diagnostics configuration keys and start **without RTX**.
Until updated, skip both 0.11.0-only sections. After a crash, **copy `rtx-remix\logs\`, `status.json`
and `session.json` before restarting**; older loaders do not collect session evidence automatically.

## Performance tiers (loader 0.11.0 or later)

When an NVIDIA adapter is identified, the RTX Remix tab's **Start here** panel shows the loader's
tier, selection source, GPU and dedicated VRAM. When a non-high tier has no layer, the panel shows
the loader's reason instead of claiming the tier is applied. This is a loader default, separate
from **Graphics Preset** in Alt+X. Non-NVIDIA and unidentified adapters show no tier line.

| Loader tier | What it does |
|---|---|
| `high` | Keeps the classic RTX defaults, with no additional tier layer. |
| `medium` | Uses the package's lighter rendering and memory settings. |
| `low` | Reduces memory and rendering costs further, including the micromap cache, sky/fog/terrain settings and streamed replacement texture detail; uses smaller night-sky textures. |

With `auto` (the default), the loader uses the NVIDIA adapter with the most dedicated VRAM. The
VRAM tier is `low` through 8.5 GiB, `medium` through 12.5 GiB and `high` above that. Recognized GeForce
RTX model classes also constrain the tier: x80/x90 are `high`, x70 `medium`, x50/x60 `low`; laptop
models move down one class tier. The lower of the VRAM and model tiers wins. Unrecognized model
names use VRAM alone. Non-NVIDIA adapters follow their existing compatibility defaults.

To override the choice, add `remix.performance_tier` to `native-loader\config.json`. The shipped file
has only `schema` and `allow`, so there may be no `remix` or `diagnostics` object yet. This **complete
minimal example** retains the shipped trust allowlist, selects `low` and leaves GPU dumps off:

```json
{
  "schema": 1,
  "allow": {
    "workshop": ["3829070317"]
  },
  "remix": {
    "performance_tier": "low"
  },
  "diagnostics": {
    "gpu_crash_dumps": "off"
  }
}
```

If you customized the file, preserve your `allow` entries and all other settings when adding or
merging these objects. **Invalid JSON turns RTX off**; keep the braces, commas and quotes valid.
Tier values are `auto`, `high`, `medium` and `low`. **Restart Garry's Mod** to apply a change. Your
saved Remix settings can override these defaults; check the effective values in
`rtx-remix\logs\remix-dxvk.log`. A loader
with an older runtime package may report no layer, or use the loader's low compatibility fallback
without the package's smaller night-sky assets. Read the reason shown in **Start here**.

## With hundreds of add-ons (R28)

What the diagnosis of GitHub issue 2 found with a player's 654 Workshop add-ons
([handover/issue-2-memory-report.md](handover/issue-2-memory-report.md)), and what the package does about it since
R28 ([ADR 0142](decisions/0142-no-crash-snapshot-of-the-game.md),
[0143](decisions/0143-read-backs-font-definitions-and-slow-render-hooks.md),
[0144](decisions/0144-the-light-updater-draws-what-the-runtime-needs.md)):

- **An RTX session needs more memory than the same add-ons without RTX**: about 20 GB committed and 12 GB of RAM in
  use on the largest map of that set, against 15 and 6 GB. The textures of everything the add-ons precache are kept
  in memory Windows cannot page out. Fewer weapon, NPC and model packs is what lowers it; the page file advice above
  still applies.
- **When the game crashes, wait for it to go.** Before R28 Windows copied the crashed game for its error report and
  charged that copy the game's whole memory again: the memory gauge at 97-99 %, a frozen desktop and a gmod.exe that
  stayed for ten seconds or more, End task or not. The package now tells Windows to report without the copy (same
  report, no second 20 GB). This needs the current Workshop item; the loader need not be updated.
- **Post-processing add-ons show nothing under RTX** (screen-space shaders cannot be applied to the path-traced
  picture; the console lists what the render guard refused), and some cost a great deal anyway. HyperReal FX read
  the screen back twice a second, and each read waited one to two frames for the path tracer: 67 ms of every frame
  on that player's set. Since R28 such repeated read-backs stop within a few seconds
  (`nativeloader_guard_readbacks 1` allows them again, with their cost).
- **On a map with hundreds of lights** (256 or more) the package's light updater no longer draws a helper for
  every light every frame, only for the lights in view, near you and near lamps, and the rest in turns. If a
  light out of view should ever come and go, or while you use the Remix free camera (developer menu), enter
  `rtx_lightupdater_all 1`: every helper every frame, as before R28. `rtx_lightupdater_status` prints the counts.
- **To see which add-ons cost a frame's time**, stand where the game lags and enter `nativeloader_lag_report` in the
  console. Ten seconds later it lists the most expensive hooks of the client and of the local server with their
  add-ons, and writes the same to `garrysmod\data\nativeloader\lag_report_client.txt` and `lag_report_server.txt`.
  Attach those to a report about lag.

## Read memory during a session

Console `rtx_vram_stats` prints the driver's VRAM budget/use, DXVK totals and Remix categories when
the RTX fixes are available. The local CSVs are:

- **Loader 0.11.0 or later:** `native-loader\logs\memory.csv` and its rotated `memory.1.csv`: process RAM,
  system commit and GPU local/non-local memory, sampled by the loader every 10 seconds.
- `garrysmod\data\native-loader\vram.csv` and `vram.previous.csv`: Remix totals/categories every
  30 seconds, when `RemixResource.GetVramStats` is available. Two hourly segments keep at most 240
  samples. `nativeloader_vram_telemetry 0` disables this sampler; `1` enables it again. Missing APIs
  produce no file or warning. After three consecutive failed calls the sampler stops for this map
  to avoid repeated native warnings; toggle it off and on to retry. Missing fields from an older
  module are blank rather than zero. Damaged, incompatible, CRLF or oversized CSVs are moved intact
  to `vram.previous.csv` and sampling starts a new segment. That saved file may exceed the usual
  bounds until the next rotation replaces it.

These files stay local. For how to interpret their units and compare the readings, see
[TESTING.md](TESTING.md#r6-testers-reading-memory).

## After a crash

**Before restarting**, copy `status.json` and `session.json` from
`garrysmod\data\native-loader\`, both companion VRAM CSV segments and `rtx-remix\logs\`.
The next start rewrites both JSON reports and may overwrite runtime logs. The session evidence
collector does **not** copy those JSON reports.

**Loader 0.11.0 or later (with `activation.performance_tier`):** at the next start, the loader keeps
available previous-session logs, dumps and a tail of the memory history under
**`native-loader\logs\sessions\<UTC time>-<reason>\`**. It keeps the last five sessions,
at most 200 MB in total, leaves original files in place and does not upload these copies. Files
that are locked or exceed the retention allowance may be missing. The status report's
`previous_session.folder` and main-menu diagnostics identify the folder when available.

With an older loader, preserve logs and matching dumps manually before restarting and update
`bin\win64\winmm.dll` (0.11.0 or later) for this collection. Copy any retained session folder before it rotates. Send:

- That **session folder**, which already contains the available runtime log, crash dumps and memory
  history. If no folder was kept (including with older loaders), preserve `rtx-remix\logs\`, the
  matching `crashes\*.dmp`/`.txt`, `native-loader\logs\gpu\` and `native-loader\logs\memory*.csv`.
- Both `garrysmod\data\native-loader\vram*.csv` files, plus the `status.json` and `session.json`
  copied **before restarting**. These files are separate from the bootstrap's automatic collection.
- Copies of the game root's `rtx.conf`, `dxvk.conf` and saved Remix settings (`user.conf`), if present,
  plus `garrysmod\console.log` if console logging was already enabled. Copy settings as they are;
  keep the originals unchanged.
- The map, model/mod names, actions just before the crash, local time and time zone, frame rate and
  Task Manager **Committed** reading, if available.

For a GPU hang, also include matching **Event Viewer > Windows Logs > System** events from `Display`
or `nvlddmkm` and any matching `C:\Windows\LiveKernelReports\WATCHDOG\` dump. If a file was not kept
automatically, attach its matching original dump or shader debug data (`*.nv-gpudmp`,
`shaderDebugInfo\*.nvdbg`, `gmod_*_gpucrash_state.log`/`.bin`), where available. Dump files can contain
process memory; review them before sharing. There is no need to send duplicate copies of files
already in the session folder.

## GPU crash diagnostics (loader 0.11.0 or later)

Use this section **only when `status.json` has `activation.performance_tier`**. Otherwise update
`bin\win64\winmm.dll` first; older loaders reject `diagnostics` and start without RTX.

For a requested GPU-crash reproduction, change `diagnostics.gpu_crash_dumps` from `"off"` to
`"next_start"` in the complete minimal config example above, preserving `allow` and any other
settings, then restart Garry's Mod. Invalid JSON turns RTX off. The value **stays `"next_start"`
in config.json**. To request another diagnostic start, delete
**`native-loader\remix\gpu-crash-dumps.used`**; that re-arms the switch. The diagnostics can add
overhead; a GPU dump is produced only when supported diagnostics capture a crash. Keep the first
reproduction's map/mods/settings and record what
happened. A later comparison should change one setting at a time.
