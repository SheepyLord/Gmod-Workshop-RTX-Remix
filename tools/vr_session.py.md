# vr_session.py

## Simulated sessions and window size (V2-N)

`--simulate` runs the module's launcher-authorised simulation: no OpenVR load/initialisation and
**no VR lock**. The exclusive PoC lock, snapshot, protected-file checks, captures, normal quit,
restoration and cleanup are unchanged. The launcher sets `NLVR_TEST_ROOT` to the run's native/
folder, copies `vr/native/sim/index-v1.json` to native/simulated-index.json with its hash receipt,
and supplies the named timeline. It changes only the generated probe: both starts receive
simulate=true and use framesRendered for progress. Source `vr_session.lua` is unchanged.
Validation requires positive rendered progress, zero eye submissions, Info.simulated=true and
no loaded OpenVR in either active Info records or the collected module list. Simulated performance
uses frame_fps, with pair_fps=null; it does not claim compositor presents or headset throughput.

`--simulate` cannot combine with --flat, --look or --live-poses; it requires an unattended timeline.
The current V1 companion still checks SteamVR installation. For the two generated simulated
starts only, a test shim presents virtual-backend availability to that UI check, then immediately
restores the real Probe function and actual cached installation facts, including on errors.
It changes neither the host/version/conflict checks nor the module's launcher-root authorization.
This makes the driver work with no SteamVR installation, without editing F's page. Live runs use
no shim. A V1 runtime that rejects the null interface produces its exact native failure;
`--expect-failure native --expect-detail TEXT` can record that clean refusal, without claiming
rendered/captured acceptance. Task R supplies null-interface rendering at integration.

`--window WIDTHxHEIGHT` sets the PoC process window, default **1280x720**, including for flat or
manual runs. Bounds are 320..7680 by 240..4320 pixels; `--window 3840x2160` exercises the user's
desktop size. This is a per-process argument, never a Steam launch option or saved setting.
The selected window and simulated flag are recorded in sources.json. All existing live/headset,
manual-look, dependency preflight and recovery behavior remains in place. Simulation still needs
Pillow for unattended desktop screenshots; native captures are independent of Pillow.

```powershell
python tools/vr_session.py --package out/dist/package.gma --evidence out/vr/n-sim --simulate --window 1280x720 --seconds 30
python tools/vr_session.py --package out/dist/package.gma --evidence out/vr/n-4k --window 3840x2160 --seconds 30
```

## Manual look and screenshot dependencies

A manual look needs Windows and any Python 3.10 or newer, the built loader, local package and
SteamVR/headset. It does not need Pillow. The probe prints the existing `NLVR preview:` line,
but requests no desktop screenshot. Its sub-step uses `poc_session.py --lua-manual`, which ignores
screenshot markers and waits for probe completion or game exit without a Python duration deadline.
`--screenshots 0` is explicit; no look path calls capture_window or imports PIL. Native `nlvr.Capture`
is independent of Pillow and remains an optional user command.

Unattended VR and flat runs require Pillow. Before resolving the evidence root, taking either
lock, creating evidence/scratch directories or touching the PoC, the driver imports PIL.Image,
PIL.ImageGrab and PIL.ImageStat in its own interpreter. Sub-steps use that same sys.executable.
An import/load failure returns exit 2 with one message naming the interpreter and the remedies:
start the command with a Python that has Pillow, or run `"<that python>" -m pip install pillow`.
`--look` and recovery `--rollback` skip this preflight. Unattended screenshot errors remain fatal.

With `--look --seconds 1800`, the following rules apply:

- The probe's SysTime limit is 1800 seconds from probe installation, not from pressing Start VR.
  `nl_vr_demo_done` requests Stop earlier. Both wait for native off before printing NL_SHOT_DONE;
  the driver then restores live settings, sends quit and rolls back. A failed/off VR session is
  still a look: a SteamVR quit returns the game to flat and does not itself end the look.
- There is no look --lua-shots limit. The ordinary `seconds + 100` screenshot deadline is used
  only for unattended runs. The shared manual wait has no deadline while the game is responsive.
- --timeout 600 applies to startup/map loading only, never to an established 30-minute look.
  A map that does not load is a startup failure. Each Lua stage gets three attempts, each with
  a 20-second acknowledgement wait; an unacknowledged stage is also a startup failure. Console
  delivery itself has up to six 10-second sends, with health checks between attempts.
- Escape/spawn menus, a paused single-player game, the Steam overlay and lost focus are not
  failure conditions. SysTime continues while CurTime is paused. The health check uses the
  Remix device-loss log and window responsiveness, not menu state, pause state or focus.
- A window Windows calls hung is confirmed with a WM_NULL response check limited to 2 seconds.
  Continuous confirmed unresponsiveness for 120 seconds fails the run; recovery resets that
  grace. GPU device loss fails as soon as its log marker is observed. These real faults retain
  the 60-second exit grace, then end only the owned game/helpers. Crash-upload prompts in that
  game are declined; ordinary game/Steam menus are not answered by that watchdog.
- After normal probe completion, quit has a 90-second exit wait before owned-process cleanup.
  If the user closes the game first with exit 0, the outcome is game_closed and restoration
  still runs, with a clear message and no traceback. The SDK is unloaded by process exit.
  Live selector/settings restoration cannot be observed after exit; the receipt says so and
  the PoC snapshot is restored instead. A nonzero/crash exit remains a failed run with its code.

Use a fresh evidence folder. For a normal end, prefer nl_vr_demo_done so the live settings/SDK
cleanup can be verified before the process exits. The driver's own generated bulk copies are
removed only after verified rollback; logs, receipts and JSON remain.

--first-camera-mismatch deliberately offsets only the published camera metadata by 1000 GMod
units for five seconds after the first push. The rendered view stays under the normal add-on.
This safely exercises startup rejection on the real renderer: require logged initial skips,
then matched output with no unmatched submissions. It is a diagnostic run, never a timing control.

Manual look also checks Submit/unmatched counters. A previous physical-pose run exposed a
queued flat camera at startup despite the correct VR projection; counters from manual sessions
must not be ignored merely because they have no scripted final-vr record. Initial camera skips
are recorded separately from submitted unmatched poses.

Accepted captures must contain visible wrist glyph pixels, not merely a PNG and a positive copy
counter. The checker reads the runtime's filter-zero RGBA8 PNG with the standard library and
rejects blank, malformed or oversized data. It requires at least 16 bright visible glyph pixels;
numeric values and labels are also inspected in the saved images. The real queued and queue-zero
neutral canvases are byte-identical and contain 8223 bright glyph pixels; a preview discrepancy
was checked against those bytes rather than treated as a new runtime failure.

Probe transport uses acknowledged --lua stages of at most 512 source bytes. Each stage assigns a
numbered hex fragment, so a retry is idempotent; the final stage decodes the exact UTF-8 source and
releases the assembly table before running it. This bounds each command-buffer burst as well as
each command's argument length. A loaded host exposed Cbuf_AddText overflow when the whole 20 KB
probe was queued at once; a successful retry still left a Lua error and correctly failed that run.
One 2048-byte staging launch never acknowledged its first stage while client startup continued;
later fragments correctly failed rather than producing a successful probe. Startup also logged
command-buffer overflows, but the cause of that lost stage was not isolated. A tiny client-Lua
readiness acknowledgement now precedes fragments. Final 512-byte stages bound each serialized
command burst below 4096 bytes, including protocol overhead.
All staging files remain under the run's repository evidence folder. No game file is read or loaded.

`--mcore 0|1` passes gmod_mcore_test on the command line. A threading fixture must omit
the package's forced gmod_mcore_test value; otherwise its later session config can select mode 2.
Always judge the exercised mode from the before record, not the requested argument alone.
Installation-stage and probe-ready markers distinguish a loaded chunk from a controller that
produced frames. The server HUD setup travels in 200-digit hex console packets, below Source's
separate 512-byte argument limit. First-camera projection, known stale-camera skips and unknown
camera details are retained in the summary.

`--queue-mode default` selects engine automatic mode (`mat_queue_mode -1`); `--queue-mode 0`,
`1` or `2` selects that session's mode. It is passed on the process command line, never saved
to a game file. The default for this driver remains 2 for comparison with earlier receipts.
The probe records the engine variable and its declared default so a queue test can identify
the mode actually exercised. `RTX_VR_WARP_TAPS` in the launching process selects the runtime's
diagnostic search-tap count; each timing/picture comparison uses a new process and evidence folder.
`--expect-failure native --expect-detail TEXT` validates a recoverable runtime failure, including
one after frames have started. The probe waits for cleanup and flat-setting restoration before
passing. A cancelled capture in that expected-failure case is not treated as an image acceptance.
The launch-only diagnostics `RTX_VR_TEST_ALLOCATION_FAILURE=1|2|3` inject a non-standard DxvkError
at eye, overlay or capture allocation; `RTX_VR_TEST_FOCUS_INTERVALS=N` replaces N successful
wait results with temporary focus loss. Zero or unset disables them. They do not change SDK
settings or add Lua options. The normal acceptance runs use neither fault variable.

Review follow-up: --pacing render|serial selects the mode for retained comparison packages; the shipping module accepts only render. The launcher sets
NLVR_TEST_ROOT to evidence/native, copies --timeline FILE into timelines/timeline.json there and
passes only the name timeline to Lua. Captures use names and are collected from native/captures.
--test-quit adds a wall-clock native quit_at event and pauses SP through the escape menu, proving
cleanup while CurTime stops without closing SteamVR. The controller probe runs from PreRender
as well. Non-flat runs test refusal of all three removed path keys and three capture escapes
before starting the SDK. The native module never accepts an arbitrary Lua DLL or capture path.

Long JSON records are reassembled from bounded, numbered base64 console packets. Missing,
duplicate, malformed and truncated records fail explicitly rather than disappearing from a summary.
Each run retains its generated Lua/config, driver/probe hashes and checkout commit in sources.json.

`--exit-paused` with `--scene-pause` exits while traced world draws are still suppressed, then
restores them for the flat control. `--look --seconds 900` is the manual headset preview: start
VR from the page or console yourself, and type `nl_vr_demo_done` to restore/quit early. It also
ends/restores at the timeout. Use that command to finish, allowing the standard driver to restore
shared settings before its normal quit. Manual preview uses real tracking and no scripted start.

Summary `steady` fields separate recorded GPU command/SDK intervals, queue gaps, elapsed runtime
spans and SteamVR's app metric. Long runs use static poses after the 60-second capture/motion period.
GPU/process CSVs record shared host load. Acceptance rejects Submit errors, unmatched poses,
unequal rendered/accepted pairs, leftover session hooks/timers or an SDK left loaded after Exit.
An optional `--inspect-dll <out/.../gmcl_nlvrqinspect_win64.dll>` installs the task's read-only
evidence helper. Its receipts include a SHA-256; it queries main-thread CPU time and the already
initialized SDK's eye projections/transforms, and never initializes OpenVR or renders/submits.
It is absent from the shipped package and is removed by rollback. Ordinary runs do not need it.
`--camera x,y,z,pitch,yaw,roll` selects the reproducible flat eye and positions the test player
without gravity so tracking's floor stays fixed. The default is the gm_construct fixture;
modern_house uses its spawn eye `80,928,545,0,0,0`. `--fps-cap 60` exercises the cap warning;
only the launch command line sets it, and the usual shared-setting restoration runs at quit.
Source convars are dumped/compared before/after. The actual GetUpscalingState snapshot checks
live upscaler/frame-generation selectors and support flags when ready. GetConfigVariable reads
file configuration and cannot prove live layered-option restoration; it is not used for that.
`--live-poses` starts with the unworn headset's actual tracking and pose-tagged submission;
the default uses the timeline. Combine it with `--quit-in-vr` to exercise actual active shutdown.
The clear/noon fixture sets zero weather-transition time and a fixed sun direction for repeatable
flat controls; all fixture variables are saved and restored.
`--players 2` exercises the supported listen-server host; the default is single-player.
`--expect-failure runtime` checks the real page's refusal with the baseline runtime package;
only the exact named reason is accepted, with its actionable status text retained.

Runs the production VR page, add-on and native module on the PoC and real SteamVR, using
`poc_session.py` for launch, crash-prompt refusal, screenshots, health checks and shared-setting
restoration. It acquires the main checkout's PoC lock and VR lock by exclusive create, waits
on an existing owner and removes only its own lock. Flat controls take only the PoC lock.

```powershell
python tools/vr_session.py --package out/dist/rtx-remix.gma --evidence <main>/out/vr/q/run-1
python tools/vr_session.py --package <development-package-folder> --evidence <main>/out/vr/q/scale-085 --render-scale 0.85
python tools/vr_session.py --evidence <prior-evidence> --rollback
```

The package path must exist. Evidence must be a new folder below this worktree's or main's
`out/`. `--seconds` is the active VR sample interval (15..3600, default 190); `--render-scale`
selects the session's V1 scale. `--timeline` selects a module timeline; otherwise a deterministic
head-turn/lean and controller timeline is generated. `--flat` leaves VR uninitialized;
`--quit-in-vr` checks actual game shutdown in VR; `--scene-pause` exercises absent traced draws.
`--map` and repeatable `--mount-workshop` select a heavier, already-installed map through the
standard driver's mount/change-map path. SteamVR settings, launch options and registry are
never edited; SteamVR is never quit. Start is through `nl_vr_start`.

Before changes it takes a depot-aware field_snapshot snapshot, checks running processes and
saves hashes of every existing PoC user.conf. Existing loader/add-on/data/settings/module and
Remix mods/logs/captures trees are renamed into evidence originals, with durable receipts;
user.conf is never moved or written. Linked roots or user.conf within a moved tree are refused.
The bootstrap is installed with an allowlist for only the local package. All scratch stays in out/.

After the run it restores original trees/files, runs field_snapshot rollback and requires its
clean depot/settings checks. `--rollback` recovers interrupted preparations after the PoC exits.
After verified restoration only owned bulk copies are deleted (originals, generated trees,
snapshot files/debris); `--keep-copies` retains them. Failed restoration retains all copies.
Logs, receipts, JSON numbers, timelines and PNGs remain. A cleanup refusal is recorded.

Outputs: production `nlvr.Info()` samples, state transitions, before/after convars and hook
inventories, captures, desktop screenshots, per-frame intervals, runtime fine timing profiles,
session-specific SteamVR/Steam log tails, protected-file hashes and restoration/cleanup receipts.
`summary.json` records success and raw measurements; it does not substitute scripts for real
SDK/runtime measurements. No field/legacy install is written. Exit 0 means the scenario completed
and rollback verified; 1 means failed checks/operation (read logs and restoration receipt).
Exit 2 means the unattended screenshot preflight refused before locks, evidence or PoC changes.
Offline tests live in `tests/test_vr_session.py`.

Integration: capture validation uses a probe manifest of overlay handles and semantic roles, never image dimensions. Wrist glyphs remain required; large panels, black comfort canvases, window sources, keyboards and markers get bounded RGBA validation. Unlabelled/unknown roles fail. The decoder needs only the standard library.

Flat controls retain a flat-window frame summary at the requested duration and hold the fixed
camera for three more seconds to collect the final screenshot before teardown.

After verified rollback, cleanup checks every native/captures file against the retained captures
copy by relative path, size and full SHA-256, writes capture-deduplication.json, and removes only
the duplicate native tree. Any missing/different/link file refuses deletion. Every raw image,
depth float and timing record remains once under captures, including for failed runs.

An isolated production module/cleanup/Stop error is a fatal acceptance finding, recorded in
module_failures, even if native rendering continues and a probe's done record is successful.
Isolation is correct in gameplay; it cannot certify that every integrated feature worked.

Q role validation explicitly recognises the seven move_arc_2..8 dot roles; arbitrary similarly named roles still fail.

Role-selected validation checks source extents against the declared source; window sources use their own 1920-pixel/aspect contract, not the panel render target dimensions.

Capture collection now atomically renames native/captures to captures after the owned game
has exited, on the same evidence volume. Both resolved paths must stay inside the evidence
root, reparse links and an existing destination are refused, and capture-collection.json
records the move. Raw file bytes are unchanged; this avoids copying gigabytes while holding
the shared locks. The hash-based duplicate cleanup remains for older completed runs.

The optional read-only clock helper is staged for both client and server realms under the
snapshotted lua/bin tree. It has no realm-specific implementation or SDK calls; rollback
restores both paths. No development helper is included in the package.

Disk-space recovery safeguards: --minimum-free-gib defaults to 8; the combined runner requests
12. Check before taking locks and again afterward, before creating the evidence tree or moving
PoC roots. Exit 2 also covers this preparation refusal. Rollback bypasses the space check.
A fsynced shared out/r10/vr-poc-pending.json is created before preserving PoC and removed only
after clean restoration/protected-hash checks. A later session refuses an unfinished transaction;
--rollback validates the matching evidence/root before any restoration. Legacy interrupted
receipts without this marker remain recoverable. Neither a failed capture nor a failed rollback
is a pass. The marker guards PoC between sessions, separately from the two live locks.


Review correction: semantic capture roles accept the centrally reserved teleport_arc_2 and teleport_arc_3 canvases. Historical move_arc_2..8 evidence remains readable.


An explicitly empty overlay inventory permits no overlay PNGs when hidden resources retired. Every declared live handle must have its image; an unlabelled image still fails. No first-image/size heuristic or unconditional wrist allocation is used.


Q3 capture readiness embeds vr_capture_queue.lua. Captures wait for new visible handles to have painted for two frames and dispatch at most once a frame. Every declared visible source still needs a PNG; hidden sources may retire before asynchronous copying. Errors/timeouts/cancelled captures remain failures.


Expected roles are mandatory by role, handle or not. Legacy records default to requiring the wrist; explicit expected_roles=[] is needed for intentionally empty captures. Visible/required declared images, role dimensions and glyphs remain checked.

After abnormal native exit, the shared crash step immediately copies exact-PID WER evidence read-only, uses vr_crash.py to classify exception-context stack evidence and retains Application event1000. A known fixes-module build/return address or known NVIDIA startup crash can re-execute the complete caller CLI once in a fresh sibling evidence folder, only after clean rollback. The complete child performs its own semantic reducers; the failed parent is not re-analysed as success. A persistent parent claim plus process token prevents further retry. Unknown or second crashes stop. NLVR_CRASH_RETRY_OF names the verified restored parent; it is not a crash-avoidance switch. Entity removals, queue mode, lighting and player cvars are not altered by classification.


--both-locks explicitly takes the shared VR lock even for --simulate/--flat; normal defaults remain compatible. The limited medium fixture always requests both.


--depot-manifest forwards explicit stock revision manifests through preparation and matching rollback. It does not skip or relax full depot verification. Use repeated official cached manifests when the PoC remains at an older stock build than the field install.


A matching old-copy recovery can explicitly choose cached official manifests without skipping any depot file; actual immutable full verification still controls clean status.

Round5: after the reviewed queued-draw repair, any fixes stack marker (including an unreviewed build) stops; only the NVIDIA startup signature permits one restored fresh-folder retry. Old receipt flags cannot override current policy. The normal field-quit helper is driver-only; exit5 after a quit crash is fatal and its evidence is retained.

Current round5 lock rule: every PoC mode, including simulation, flat and rollback, takes both shared locks. --both-locks remains accepted for compatibility; callers need not remember it.
