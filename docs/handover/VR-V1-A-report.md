# VR-V1-A: SDK pin, probe, S1 and S5

Current startup correction after the second runtime review: the VR creation list guarantees two
instance and four device names independently of FSR, six names in total. The five-name delta
measured in this report belongs to the original installation with FSR present;
VK_KHR_get_memory_requirements2 was then supplied by that optional library. See
[ADR 0157](../decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md) and the
[second-review report](VR-V1-Q-runtime-review-report.md) for the corrected code and renewed evidence.

Implementation date: 2026-11-10. Branch/worktree: `vr-a`, `out/worktrees/vr-a`.
Scope: [the A brief](VR-V1-A-sdk-and-probe.md), [V1 interfaces and test rules](VR-V1-plan.md),
and [the binding design decisions](VR-plan.md). Nothing was pushed, merged or published.

## What was built

- **SDK-only commit `792075a453a5d7340aec04fbd4ba8e4228d945c1`**, the starting point for
  VR-D: Valve OpenVR **v2.15.6**, commit `0924064316de3effbcd1acf1e309182a2deb1c05`.
  `third_party/openvr/include/openvr.h` and `LICENSE` are byte-identical upstream files;
  [the README](../../third_party/openvr/README.md) records their hashes and the DLL's hash.
  The DLL is 837,272 bytes, SHA-256
  `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a`.
- `tools/ci/pins.json` records the DLL with the existing fetched-download fields and one new,
  optional `staged: true` flag. Default fetching skips staged entries; an explicit `--only
  openvr` includes it. Unknown pin names are errors. This keeps the release workflow and gate
  usable before VR-Q creates `packages/vr`. VR-Q removes `staged` when integrating the part.
  **Every later task gets its DLL through** `python tools/ci/fetch_prebuilt.py --only openvr
  --out out/vr/verified`; the checked copy is `out/vr/verified/vr/bin/openvr_api.dll`.
  The initial download folder in the main checkout, `out/vr/sdk/openvr-2.15.6`, was created empty
  and kept as data only; nothing was loaded from it. No binary was imported or committed.
- **Probe commit `6d0b009`**: [vrprobe](../../vr/native/probe/README.md), a standalone C++20
  console tool, dynamically loading the verified SDK and the system Vulkan loader. `info`
  loads neither; it inspects the OpenVR paths file and the three SteamVR process names.
  `extensions` inventories both GPUs and compares SteamVR's requirements with a saved Remix
  enabled-extension log. `submit` is a minimal Vulkan reference, also supporting pose submission.
  `idle` records once-per-second device, wait, timing, event and cumulative-statistics evidence.
- [discovery.cpp](../../vr/native/probe/discovery.cpp) and `probe_data` are reusable by VR-D's
  `nlvr.Probe()`: no OpenVR headers or DLL loading in those sources. The CMake static target is
  `nl_vr_probe_data` (its public dependency is the existing `nl_core` JSON parser).
- Root CMake adds only `add_subdirectory(vr/native)`; the native CMake adds `probe`, leaving
  VR-D's module beside it. Both third-party includes are SYSTEM includes. The configurable
  `NL_VR_VULKAN_INCLUDE_DIR` defaults to the read-only runtime clone specified by the brief.
  Missing headers compile out Vulkan-dependent commands; `info`, plain `idle`, and tests remain.
- Offline CTest coverage: 49 parser/comparison/argument/statistics checks, plus seven executable
  CLI scenarios. The latter use isolated path files and verify that OpenVR remains unloaded.

Each OpenVR session takes the **main checkout's** `out/vr/vr.lock` internally before SDK loading,
holds it through client and Vulkan cleanup, and releases only its own lock. Exclusive Win32
creation, task/PID/UTC ownership and delete-on-close also handle abnormal process exit. The probe
waits three seconds on contention. It never starts SteamVR except through scene `VR_Init`, never
quits SteamVR, never changes its settings or registry, and never substitutes a null driver.

## S1: required Vulkan extensions

**Settled.** The user's unworn Index initialized successfully: `VRInitError_None (0)`.
Headset: Index/lighthouse, **90 Hz**, **2468 x 2740 per eye**, approximately **68.54 mm IPD**.
The SDK interfaces used are `IVRSystem_026` and `IVRCompositor_029`. Both the RTX 5090 and the AMD
integrated GPU were enumerated; SteamVR selected the **NVIDIA GeForce RTX 5090**. Its driver is
**617.42**. No SteamVR resolution or refresh setting was changed.

The saved R28 PoC log was sufficiently detailed; it identifies Remix `remix-main+17dcc86c` and
the RTX 5090. No new game/PoC session was necessary. Comparisons use **enabled** extension blocks,
not the available-extension inventory. The final JSON compares device enablement only for the
GPU that log names; the AMD device's runtime state is unknown, while its offered list is recorded.

| Required instance extension (6) | Named as enabled by Remix | Offered by loader |
|---|---|---|
| `VK_KHR_external_memory_capabilities` | yes | yes |
| `VK_KHR_get_physical_device_properties2` | yes | yes |
| `VK_KHR_external_fence_capabilities` | **no** | yes |
| `VK_KHR_surface` | yes | yes |
| `VK_KHR_win32_surface` | yes | yes |
| `VK_NV_external_memory_capabilities` | **no** | yes |

| Required device extension (7) | Named as enabled by Remix | Offered by RTX 5090 |
|---|---|---|
| `VK_KHR_external_memory` | yes | yes |
| `VK_KHR_external_semaphore` | yes | yes |
| `VK_KHR_timeline_semaphore` | **no** | yes |
| `VK_KHR_dedicated_allocation` | **no** | yes |
| `VK_KHR_get_memory_requirements2` | yes | yes |
| `VK_KHR_external_memory_win32` | yes | yes |
| `VK_KHR_win32_keyed_mutex` | **no** | yes |

Thus **2 instance names and 3 device names need adding** to the runtime's enabled lists for
SteamVR's exact requirements on this machine. All requested names are offered; the AMD GPU also
offers all seven device requirements. Some functionality has Vulkan core promotions: the table
records literal names, without treating absent names as proof that the underlying functionality
is unsupported. VR-C should retain SteamVR's full requested lists and test its device path.

Evidence, relative to the **main checkout**:

- `out/vr/s1/extensions-final.json`, its command JSON and raw stderr log; `info-before.json`.
- `out/vr/s1/remix-dxvk.log`, copied from the R28 location in the brief. Its enabled instance
  block starts at line 464; device name is line 519 and enabled device block starts at line 524.
- `out/vr/s1/extensions.json` is the initial successful inventory before the final GPU-name
  matching refinement; use `extensions-final.json` for the final comparison.

## Reference Submit for VR-C

The [probe README](../../vr/native/probe/README.md) gives the contract and links Valve's primary
documentation. The implementation supplies two optimal-tiled, single-sample RGBA8 UNORM images
at SteamVR's recommended dimensions; usage is transfer source, sampled and transfer destination
(for clears). Clear-to-copy barriers end in `TRANSFER_SRC_OPTIMAL`; explicit gamma color space
matches the encoded clear colors. A fence protects command-buffer reuse; same-queue ordering and
barriers protect image reuse, without a per-frame queue-idle.

All required extensions are enabled; the timeline-semaphore feature is queried/enabled if requested.
The queue is used by **one thread** throughout application submission, explicit timing, both eye
Submits and application handoff. The explicit mode is
`Explicit_ApplicationPerformsPostPresentHandoff`; `SubmitExplicitTimingData` immediately precedes
the application's first `vkQueueSubmit`. `PostPresentHandoff` follows both eyes. Under that mode,
`WaitGetPoses` can be outside DXVK's queue lock; all the other listed operations need its exclusion.
`--pose` uses `VRTextureWithPose_t` with the frame's actual HMD matrix and `Submit_TextureWithPose`.
OpenVR client shutdown happens **before** Vulkan resources are destroyed; device-idle precedes freeing.

The final **8.002167-second** pose-flag smoke run made **709 waits**, **1418 accepted eye Submits**,
**0 wait errors** and **0 compositor errors**, at **88.601 Hz** including startup. All 709 poses
were valid. The earlier 8.004394-second run likewise accepted 1418 eyes without errors. These are
standalone reference results, **not S3's proof of Submit under DXVK's lock**. The raw timing API
can return startup anomalies, including negative GPU values; retain the raw range and do not
interpret this clear-color test as RTX pass-cost measurement.

Evidence: `out/vr/s1/submit-pose-final.json`, command JSON and stderr; the earlier
`submit-pose.json` is retained too. No OpenVR/Vulkan import library is linked; `dumpbin /dependents`
shows only `KERNEL32.dll` (`out/vr/probe-dependents.log` in this worktree).

## S5: unworn Index behavior

The first run used **10 minutes without Submit**. The submitting run is deliberately extended
to **14 minutes**: one scene application must exceed the historical 12-minute-48-second standby
interval, while also supplying the requested ten minutes of submitting evidence. Controllers
remained asleep/disconnected; nobody wore the headset. Builds/offline checks and ordinary desktop
applications ran concurrently, so the timing ranges include system jitter and are not isolated
GPU benchmarks (`out/vr/gpu-context.csv`, `compute-context.csv` in this worktree).

**Settled for an active scene:** nominal 90-Hz waits and accepted eye submissions continued in standby,
with the stalls and overall averages recorded below.
The 14-minute scene outlasted the historical standby interval without a quit event.

| Metric | No Submit, 10 minutes | Submit, 14 minutes |
|---|---:|---:|
| Measured seconds | 600.006759 | 840.010121 |
| WaitGetPoses returns | 53,846 | 74,763 |
| Overall waits/second | 89.742322 | 89.002499 |
| Return interval ms: min / mean / max | 0.052100 / 11.143214 / 958.356800 | 0.539000 / 11.235776 / 285.658000 |
| Inside WaitGetPoses ms: min / mean / max | 0.009500 / 11.068531 / 280.964100 | 0.009200 / 10.566328 / 99.480200 |
| Valid / invalid pose frames | 53,846 / 0 | 74,763 / 0 |
| Wait errors | 0 | 0 |
| Accepted eye Submits | 0 | 149,526 |
| Submit/explicit-timing errors | 0 | 0 |
| Standby activity samples / total | 593 / 597 | 831 / 835 |
| Compositor presents, after | 53,994 | 75,625 |
| Compositor dropped frames, after | 0 | 292 |
| Compositor reprojected frames, after | 0 | 1700 |
| Reported app GPU ms: min / mean / max | 0.000000 / 0.000000 / 0.000000 | -18.606113 / 0.828905 / 105.706398 |
| Reported compositor GPU ms: min / mean / max | 0.297984 / 0.328538 / 3.848608 | 0.000000 / 0.322425 / 4.534432 |
| Quit events | false | false |

All sampled tracking results were `Running_OK (200)`. Each sample contained the Index and one
tracking reference; no controller was connected. Activity was `Standby (3)` after the initial
`Idle (0)` samples. Nominal cadence remained 90 Hz, with the recorded transient intervals above;
this does not claim every frame met its deadline. Compositor drops and reprojections are retained.

The table uses **after** cumulative statistics for the measured process. Before readings can
still name the previous scene PID, so they must not be blindly subtracted. The compositor
"submits" statistic also advances during no-submit waits; `eye_submits_accepted` counts the
probe's actual successful Submit calls. No headset display visibility or refresh setting
was forced. Both runs logged zero compositor API errors.

Evidence in the main checkout: `out/vr/s5/idle-no-submit.json`, `idle-submit-14m.json`, their
command JSON/stderr logs, `summary.json`, and `after-vrmonitor.txt`, `after-vrserver.txt`,
`after-vrcompositor.txt`. The first run used the initial probe build; the second used the final
probe code (also querying/enabling the timeline-semaphore feature). The wait/device measurements
are the same implementation; the final code additionally reports completion/success flags.

Before/after settings snapshots and their SHA-256 values are retained in `summary.json`.
The probe made no settings calls or writes; SteamVR owns any automatic changes.

The settings differences are limited to the settings window's geometry and automatic GPU
benchmark bookkeeping (`gpuSpeed1`, count 1 to 2, horsepower 8979 to 9047). Power, resolution and
refresh preferences did not change. These runtime-owned updates were not overwritten.

**Timing limit:** the submitting run emitted one display-disconnected/reconnected pair at
**0.936 / 2.446 seconds** and **15** application-not-responding events between **351.439 and
365.447 seconds**, each followed by a resumed event. The compositor log also records signal-thread
timeout warnings. All eye Submit calls still succeeded and tracking stayed valid, but this is
**not stall-free rendering**. The raw application GPU timing range includes negative readings
(-18.606 ms); it cannot establish RTX pass costs. The probe deliberately retains those values.
No cause was isolated for the transient burst under concurrent verification/desktop workloads.
VR-C/VR-Q must separate integration behavior from host scheduling before claiming stable pacing.

After client shutdown, `info-after.json` confirms **vrserver, vrmonitor and vrcompositor still
running**, with OpenVR unloaded in the discovery process. The shared VR lock was absent.


OpenVR reported the proximity sensor's presence, but its legacy HMD button-state query returned
no readable state. `proximity_pressed` is therefore `null`. The optional display-suppressed
property returned `TrackedProp_UnknownProperty (4)`, also recorded as `null`. The desktop-display
flag was false (direct mode); that does not say whether pixels were lit. Activity, events,
tracking validity and accepted frame counts are the evidence for standby operation. Actual panel
luminance was not measured. All unknown/reserved event IDs are retained numerically.

### The earlier shutdown at 04:02:37

The preserved `vrmonitor.txt` records standby beginning **03:49:48.785**, then
`ShutdownRequested` at **04:02:37.168**, **768.383 seconds** later. `vrserver.txt:1387` says
**vrmonitor PID 13080 initiated a quit-all at 04:02:37.179**. Steam's process log records exit
code **0**; this was an orderly shutdown request, not evidence of a compositor crash.

The user settings file has **no power overrides**. Installed defaults record screen timeout
**5 s**, controller timeout **300 s**, watchdog-return timeout **0**, pause-on-standby **true**.
Those values alone do not identify who requested shutdown. Additional read-only Steam logs show
GMod launch attempts at **04:02:24** and **04:02:31**, both waiting on an interstitial, then a
successful launch immediately after SteamVR exited (**04:02:40-42**). This supports a desktop
launch/UI shutdown context; it does **not prove which user/UI action initiated quit-all**.
No source log names an automatic 13-minute standby timer. The exact initiating UI action remains
unrecoverable from these logs. The active-scene duration measurement below tests the practical
concern without changing any setting.

Historical evidence: `out/vr/s5/vrmonitor.txt`, `vrserver.txt`, `steamvr.vrsettings`,
`default.vrsettings`, `before-vrcompositor.txt`, `before-vrdashboard.txt`,
`before-vrwebhelper_systemui.txt`, and `historical-shutdown.json` (line-numbered excerpts).
These are read-only copies, not changes to Steam's files.

## Validation and local build records

- `tools/test.ps1 -Config Release`: **passed**, **32/32 CTest entries**, **843 Python tests**
  across three groups (29, 26, 788), **7 reported skips**, no failures. `release-gate.log` records
  the full command output. The SDK-only gate also passed (30 CTest entries, 843 Python tests)
  before the probe was added (`sdk-gate.log`).
- Header-present and header-absent builds both passed the probe's **49 offline checks** and
  **7 CLI scenarios**. The absent-header `submit` check exited **1** with the explicit compiled-out
  message, before SDK loading/VR locking (`no-vulkan-capability.json`).
- The **full Release gate also passed with Vulkan headers disabled**: 32 CTest entries and
  843 Python tests, seven reported skips (`no-vulkan-release-gate.log`). The normal header path
  was restored and the Vulkan-enabled probe rebuilt afterwards (`vulkan-restore-build.log`).
- `git diff --check` and `python tools/check_repo.py`: passed. Vendored header/licence bytes
  retain their recorded upstream SHA-256 values.

The root CMake addition changes a recorded build input of six existing package modules. Their
source hashes were refreshed with `tools/ci/repo_builds.py refresh`, **retaining all six existing
payload hashes**. No package file changed. Fresh worktree paths have a different CodeView-path
length from the original builds; the existing image comparator requires equal lengths. For the
comparison build only, a generated CMake include set `/PDBALTPATH` to each retained image's
original debug path. All six then compared equal under the repository's normal PE normalization.
The include was removed from the cache before the final standard Release gate. Sources/compiler
flags and executable behavior were otherwise unchanged. This avoids importing identical native
code merely because the task's worktree name has another length.

Evidence in **this worktree's** `out/vr`: `package-image-comparison.json`,
`retained-pdb-paths.cmake`, `pdb-compare-configure.log`, `pdb-compare-build.log`,
`repo-build-refresh.log`, `default-build-restore.log`, `probe-build.log`,
`no-vulkan-{configure,build,tests}.log`, `no-vulkan-capability.json`,
`vulkan-check-{configure,build,tests}.log`, `probe-dependents.log`, `sdk-gate.log`,
`release-gate.log`, `no-vulkan-release-gate.log`, `no-vulkan-gate-configure.log`,
`vulkan-restore-configure.log`, `vulkan-restore-build.log`. The SDK gate passed before its own
commit and before a VR package part existed.

No game session ran for this task: preflight `gmod.exe` instances were this worktree's CTest
fixtures under `out/tmp`. No PoC lock/deployment/rollback was needed. The field install, PoC,
Steam depot files, `user.conf`, launch options, Steam settings and registry were untouched by this
implementation. SteamVR was started only by scene initialization and left running; only probe
clients were shut down. No loader source changed.

## Open work and hand-over

- VR-C: implement/measure S3 in the actual runtime; S1 names above must be available there before
  Start VR. This reference's changing colors demonstrate submission, not path tracing or stereo.
- VR-D: start from the SDK-only commit; reuse the read-only discovery source/target and current
  pinned header. The probe is not a package payload. Do not load the quarantine DLL.
- VR-Q: create the VR package part and import the checked SDK DLL once, remove `staged`, integrate
  runtime/module/add-on tests, and measure actual RTX GPU passes at 80 and 90 Hz. A kept 90-Hz
  headset setting in this task does not settle that performance work.
- Public OpenVR queries used here cannot expose raw proximity state/panel brightness on this
  setup. The historical quit-all initiator is known; its exact initiating UI action is not.
- Standalone submission acceptance is proven; the brief stall burst, initial display reconnect
  and anomalous raw GPU timing require follow-up in the runtime/integration measurements.
- Independent Claude review and the user's V1 merge approval belong to the milestone integrator.

## Text for integration's shared documents

**CHANGELOG / Unreleased:** Pinned Valve OpenVR 2.15.6 and added an optional, unshipped SDK/Vulkan
probe for VR startup requirements, reference eye submission and unworn-headset measurements.
Staged downloads are available explicitly before a package part exists; default fetching skips them.

**COMPONENTS:** `third_party/openvr` contains Valve's unchanged BSD-3-Clause header/licence;
`vr/native/probe` contains the MIT console probe and its offline CTest checks. `tools/ci/pins.json`
stages the checked win64 SDK DLL; `fetch_prebuilt.py --only openvr` is the shared fetch path.

**ROADMAP:** VR-V1-A implemented; S1 and S5 measured on the unworn Index. VR V1 remains on its
separate branch pending runtime/module/add-on integration, review and the user's approval.

**RESEARCH:** Copy the two S1 tables and S5 numerical results above, keeping the distinction between
literal extension enablement, core promotions, wait cadence, successful Submit calls, compositor
statistics and unknown display/proximity readings. Retain the historical shutdown evidence and
its attribution limit. The reference Submit ordering/resource contract is in the probe README.

**TESTING:** Build with `tools/build.ps1 -Config Release`; fetch only the checked DLL using the
command above. Run `vrprobe info` without initializing OpenVR. Each `extensions`, `submit` and
`idle` command holds the main checkout's VR lock internally. Follow the work plan's stop-on-init-
failure rule; leave SteamVR running and change no settings. `--out` writes final JSON and stderr
is JSON-lines evidence; collect both under `out/vr/s1` or `s5`. Use `idle --minutes 10` with and
without `--submit`; for a shutdown concern, use a continuous submitting scene longer than the
suspected interval. No game is needed. The 49 offline checks and seven CLI scenarios require
neither SteamVR nor Vulkan headers. A missing-header build reports unavailable Vulkan commands
before loading OpenVR. The whole repository still requires the Release gate.

**Decision rationale:** Keep the SDK pin separate for VR-D; extend the existing download format
by one opt-in staging flag rather than creating a second pin store or a premature package part.
Use dynamic loading and SYSTEM headers so neither an installed SDK nor a link library is required.
Keep unavailable sensor/display readings explicitly unknown. Extend S5's second measurement to
cross the historical standby interval, without changing power settings or manufacturing tracking.
