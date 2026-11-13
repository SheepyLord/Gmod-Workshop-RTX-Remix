# VR V2-N: native input, simulated sessions and the PoC driver

Branch/worktree: `v2n`, from `vr2` at `bde40fc`. Brief:
[VR-V2-N-module.md](VR-V2-N-module.md); binding interfaces/rules:
[VR-V2V3-plan.md](VR-V2V3-plan.md). No push, merge, Workshop publication, loader change or
modification of F/R's files. The shared `rtxvr_api.h` is unchanged; wire version 3 and Lua version 1 remain.

## Status and authorised provenance follow-up

Claude accepted N and the user authorised its remaining provenance update on 2026-11-11.
Commit `e00e6b1` adds `vr/native/sim_device.cpp` and `.h` to the VR module's declared sources,
then refreshes only `vr/bin/gmcl_nlvr_win64.dll` using
`python tools/ci/repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll`. The stored module and its
build/source record now agree under [ADR 0126](../decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md).
The former source-catalog/stale-module blocker is closed; its earlier failing receipts below
are retained as history. **`tools/test.ps1 -Config Release` now passes in v2n:** **34/34 CTest
entries**, **29 + 26 + 886 = 941 tool Python cases**, **0 failures**, **5 existing skips**.
No code or test-check exceptions were needed after recording the correct packaged provenance.

Packaged module: **499712 bytes**, SHA-256
`980ba98f80e371ff04c2f63af121f0e28d5462e0f1905f1baf5e7d10d5d7d8eb`, identical byte-for-byte
to the Release build. The xz Git LFS input is **201904 bytes**, stored SHA-256
`bd67f2d6f9cd740197b5643a17c17d6250bed1ba8a3fdab6cc28f7045fe5777e`. The source record identifies
accepted source commit `4a6eb59` and the Release/MSVC build; no source hashes were edited to
pretend the old DLL contained the new implementation. `repo_builds.py status` and conventions pass.
Only this module, its package index entry and its native source/build record changed. Runtime,
OpenVR SDK and all other packaged-module records are unchanged. Nothing was pushed or published.

The keyboard is left exactly as found: RequestFailed **23**, no `system.keyboard` overlay with
nobody in the headset. No workaround or SteamVR setting/process change is made. Task M owns the
in-game fallback panel when ShowKeyboard fails; this module retains its clear failure result.
Real render acceptance, corrected binding editor and simulated acceptance receipts remain below.

Follow-up evidence is the main checkout's **`out/vr/v2/n/provenance-followup/`**:
`refresh.log`, `module-identity.json`, `committed-lfs-pointer.txt`, `gate-release.log` and
`ctest-release.log`. Verification decompresses the committed package payload, checks its raw
size/hash against both the package index and Release build, checks its compressed size/hash,
and confirms that every other native record/input is unchanged. The raw module identity above
is unchanged from the accepted final N build; only its previously stale packaged copy/record
was brought current. The runtime import remains task Q's work.

## What changed

- `Start{simulate=true,timeline="NAME"}` is launcher-authorised only. An absolute
  `NLVR_TEST_ROOT` must already exist in the environment; without it Start refuses before a
  renderer load. It reads fixed `simulated-index.json` there and the existing named timeline.
  Lua cannot choose a root, device file, manifest or executable path. Links and invalid names
  remain refused under [ADR 0150](../decisions/0150-vr-client-lua-boundary-and-native-quit.md).
- Simulation loads no OpenVR DLL, initialises no scene application and uses a waitable timer at
  the recorded refresh. High-resolution creation is reported, with ordinary timer fallback.
  Poses/actions are scripted; Info reports simulated=true, sdk_ready=false, openvr_loaded=false,
  and no compositor timing. The runtime gets NO_SUBMIT, null getGenericInterface and no render
  pacing flag. The native worker continues timed keyboard events/native quit independently of Lua.
- Simulated overlays use monotonic owned handles and retain placement, desired/actual visibility,
  texture dimensions, alpha, colour, sort and window-source state. Hand/head attachments compose
  with the scripted pose and report absolute OpenVR-basis transforms in OverlayInfo. Runtime
  copies/captures still own the pixels; bookkeeping is not evidence of a GPU copy.
- ShowKeyboard/HideKeyboard use SteamVR's keyboard and only session-owned keyboard state. Done
  and closed events reach Lua with UTF-8 text. Done/closed duplicates are suppressed and events
  for another overlay/token are ignored. Simulation retains the same state without platform work.
- OpenBindingUI opens this application's action set on the desktop. Controller source handles
  are tried first; when sleeping controllers return InvalidDevice, the valid `/user/head` source
  opens the application's editor. An invalid source handle is not silently treated as success.
- OverlaySortOrder and OverlayColor validate their uint32/RGB arguments and require an owned handle.
  OverlayWindow resolves `rtxvr_SetOverlayWindow` privately by name; enable sends SHOW|NO_MIRROR
  (3), disable/removal sends 0. Missing export returns false plus a message while ordinary Start
  continues to work. No shared-header declaration was added in N's branch.
- Skeleton Actions add four splay values, read beside five curls. No new action or binding is
  needed: the existing skeleton summary provides both. Timelines now accept every declared input
  type, interpolate axes/curls/splay, and carry bounded keyboard events. Native quit, deferred IPD
  reads, render-side live pacing and V1's error/pose boundaries are preserved.

The [native README](../../vr/native/README.md) documents the APIs, limits and the complete format.
[ADR 0161](../decisions/0161-simulated-vr-sessions-for-tests.md) records the simulated-session decision.

## Copyable timeline

The launcher copies this to `NLVR_TEST_ROOT/timelines/example.json`; Lua passes only `example`.
Positions are Source tracking axes in metres, angles Source degrees. Every step is a complete
snapshot; omitted actions become neutral. Matching scalar/stick/skeleton actions interpolate,
buttons change at the step, and the final step holds. Keyboard event times are wall time from
native readiness, delivered once by the worker even without BeginFrame. A scripted closed event
also hides the owned real keyboard; opening one still requires ShowKeyboard.

```json
{"version":1,"events":[
 {"time":2,"type":"keyboard_done","text":"a label"},
 {"time":2.1,"type":"keyboard_closed"}
],"steps":[
 {"time":0,"hmd":{"pos":[0,0,1.6],"ang":[0,0,0]},
  "left":{"pos":[0.25,0.25,1.2],"ang":[0,0,0]},
  "right":{"pos":[0.25,-0.25,1.2],"ang":[0,0,0]},
  "actions":{"left_grip":false,"left_grip_force":0,"right_trigger_value":0,
   "left_stick":[0,0],"left_skeleton":{"curls":[0,0,0,0,0],"splay":[0,0,0,0]}}},
 {"time":3,"hmd":{"pos":[0.2,0,1.6],"ang":[0,20,0]},
  "left":{"pos":[0.45,0.25,1.2],"ang":[0,0,0]},
  "right":{"pos":[0.45,-0.25,1.2],"ang":[0,0,0]},
  "actions":{"left_grip":true,"left_grip_force":1,"right_trigger_value":1,
   "left_stick":[1,0],"left_skeleton":{"curls":[1,1,1,1,1],"splay":[1,1,1,1]}}}
]}
```

Timelines remain version 1, at most 1 MiB/10000 steps and events within parser limits. Curls
and splay are 0..1; a skeleton also accepts a compact five-curl array. Event text is bounded to
16384 UTF-8 bytes, with no NUL; only keyboard_done/keyboard_closed types are accepted.

## Recorded device and the driver

[sim/index-v1.json](../../vr/native/sim/index-v1.json) records V1's Index geometry: **90 Hz**, eyes
**2468 x 2740**, IPD **0.068536602 m**, measured raw projection tangents and neutral eye rotations.
Its provenance names/hashes the V1 VR-C console receipt. V2's live full matrices confirm neutral
rotations and zero Y/Z offsets; live IPD had changed to **0.0700000003 m**, so the fixed test file
intentionally keeps V1's offsets. Current physical settings do not silently alter feature tests.

`tools/vr_session.py --simulate` keeps the PoC lock/snapshot/capture/restoration path and omits the
VR lock. It copies the recorded description into the native test root and changes only generated
probe starts/progress checks; the accepted `vr_session.lua` is untouched. A bounded test-only
availability shim lets V1's installation-only page gate start a virtual backend on a clean
machine: it restores the real Probe function/cache immediately, even after errors. Host/version/
conflict checks and native root authorisation remain. Ordinary live/look probes get no shim.

Simulated evidence requires positive framesRendered progress, zero submitted eye pairs, explicit
simulation and no OpenVR observed in active Info or the module inventory. `frame_fps` is rendered
throughput; `pair_fps` is null. Live checks still require equal rendered/submitted/matched pairs.
`--window WIDTHxHEIGHT` is process-local, default **1280x720**, bounded to 320..7680 by 240..4320;
3840x2160 is accepted. It changes no Steam option or saved setting. Unattended Pillow preflight,
manual look without Pillow, expected failures, rollback and protected-file checks remain.

## Tests and receipts

All evidence is under the **main checkout's `out/vr/v2/n/`** unless a worktree path is stated.
Working build/package/log files stay under this worktree's ignored `out/v2n/` and `out/build/`.

- Native CTest has the original 16 cases plus 6 V2 cases: timeline interpolation/events, missing
  launcher root, simulated timing/state/restart without an SDK, malformed inputs/native quit,
  actual SDK method forwarding/errors via stand-ins, and optional window source/ownership/flags.
  Held-init responsiveness also includes all six new Lua-facing methods. Explicit forwarding
  checks cover multiline/maxchars/modal keyboard, binding context, RGB/sort and distinct splay.
- Driver tests cover simulation lock selection, device-copy identity, both generated starts,
  rendered progress/zero SDK/zero submissions, window validation, mode conflicts and the temporary
  GUI adapter's restoration on success/refusal/error. The module's native boundary is tested
  independently. No test creates real SteamVR state unless explicitly launched on the Index.
- `poc-sim-01`: launch failed **before map/Lua**, access violation **0xC0000005** at
  **nvoglv64.dll+0xe622f8**, matching the plan's old startup driver crash. The saved minidump is
  hashed/classified in `crash-classification.json`; the clean restoration is retained. No module
  behavior is inferred from this failed launch. It was rerun as instructed.
- `poc-sim-02`: real V1 package plus N's built module; **1327 rendered/matched frames**, **0 eye
  submissions**, **0 Submit errors**, **0 unmatched poses**, **88.148 rendered frames/s** in the
  steady window. Two native Start/Exit cycles passed; both neutral and HUD-change captures contain
  centre/depth/left/right/mirror/timing/overlay PNGs, with valid visible wrist glyphs. SDK absent in
  active Info and the module list. This runtime already accepts null-interface NO_SUBMIT: the
  anticipated native-refusal path was not taken. Normal quit, **0 Lua errors**, settings restored,
  **2877 depot files** verified without missing/size/hash mismatches; protected files unchanged.
  See `simulated-receipt.json`, the summary, captures and restoration.json. I inspected the mirror.
- `poc-index-01`: V1 real-render acceptance passed (**685 matched/submitted pairs**, **0 errors**,
  **0 unmatched**), but the custom feature record was truncated at Source's 4095-byte line limit.
  That feature witness was rejected, reduced below 3000 bytes and rerun. Normal quit/restoration
  remained clean; see `index-first-receipt.json`. No truncated record is treated as UI success.
- `poc-index-02`: full eye matrices, real tint/sort and controlled failures were recorded with no
  truncation. Keyboard Show returned **VROverlayError_RequestFailed**, binding UI **InvalidDevice
  (9)** for an invalid/no-controller source. Scripted done/closed events arrived; they do **not**
  prove a refused keyboard opened. This led to the device-source correction and native probes.
  Ordinary real acceptance still passed: **686 rendered/submitted/matched pairs**, **0 Submit
  errors**, **0 unmatched**, **0 Lua errors**, normal quit/settings restoration, **2877** verified
  depot files and no protected-file changes (`index-second-receipt.json`).
- `ui-native`: direct SDK comparison, both shared locks, no game window: modal and ordinary
  ShowKeyboard both returned **23**, left/right input paths returned binding error **9**, but
  `/user/head` returned **0**, proving a valid editor target with sleeping controllers. N now uses
  controller sources and that head fallback. SDK/SteamVR settings were not edited or processes
  ended. The current keyboard service result remains explicit rather than being mocked as success.
- `ui-native-02`: the same scene-app probe also queried `system.keyboard` (**UnknownOverlay 10**)
  and tried ShowKeyboardForOverlay on its own textured overlay (**RequestFailed 23**). Modal and
  ordinary ShowKeyboard still returned 23, while head-targeted binding UI again returned 0.
  This is an unresolved platform/UI availability finding, not proof that the keyboard opened.
  No dashboard/helper was started manually and no SteamVR setting was changed to work around it.
- `ui-binding-final`: the corrected **Session::open_binding_ui**, not just direct SDK calls,
  returned **0** on the Index with sleeping controllers, then Stop acknowledged **off**. Both
  shared locks were taken/released; no game window was opened. SteamVR was already running before
  N's hardware tests (F's run had started it) and was left running. N started no SteamVR helper.

The simulated native unit cycles each acquired **36 frames** in **0.389281 / 0.389054 s**, measured
**89.909 / 89.962 intervals/s**, with the high-resolution timer available. All **22 native cases**
and the input checker pass. The driver suite has **27 passing cases**, including a real LuaJIT
test of the no-installation adapter and restore-on-error. The same 27 pass in an actual venv
created **without pip or packages** (`no-packages-driver.log`); look still skips Pillow preflight,
and unattended live/flat/simulated modes refuse missing Pillow before locks or evidence creation.

The final module is **499712 bytes**, SHA-256
`980ba98f80e371ff04c2f63af121f0e28d5462e0f1905f1baf5e7d10d5d7d8eb`.
The tested simulated/Index package used the preceding 499200-byte module; the final binary adds
the valid-device binding-UI fallback and a simulation-specific startup message. The fallback is
independently hardware-verified above and all final native cases pass. `build-final.json` records
the selected final artifact and unchanged shared header. The fresh final local package is
`out/v2n/package/gmod-rtx-remix-0.0.0-v2n-final.gma`, **2085387134 bytes**, SHA-256
`c5579bfd64ed53d9b43dfc12f2e90794b5acb4008822af50e6a88f00f7511cbb`, checked by nlctl. Its
summary records that only the VR module came from the build overlay; all other native inputs
were retained packaged. The older generated GMA was removed after all run restorations verified;
its summary/hash receipts and all images/logs remain. The initial delivery committed no binary or
package index; the authorised follow-up now commits the selected module and its provenance above.

`provenance-actions.json` retains the originally deferred actions. They are now completed by the
authorised module-only refresh above; it is a real import, not a source-hash-only edit. The
earlier failing gate and all native/Python/source receipts remain distinct from the follow-up.

The initial `tools/test.ps1 -Config Release` ran to completion in this worktree and returned **1**:
**34/34 CTest entries pass**, tool Python groups **29 + 26 + 886 = 941 cases**, **1 failure** and
**5 skips**. The one Python failure is exactly
`test_repo_builds.ThisRepositoryTests.test_the_sources_cover_what_this_checkouts_build_read`:
new `vr/native/sim_device.cpp` and `.h` are not in the packaged module's explicit source catalog.
The other failed gate step is conventions, for the stale packaged VR module source record.
All other Python assertions pass. These are the two manifestations of the unassigned provenance
update that was initially outside N's paths; neither was suppressed or described as a passing gate.

Final receipts: `gate-final.log`, `ctest-final.log`, `native-final.log`, `no-packages-driver.log`,
`build-final.json`, `provenance-actions.json`, `simulated-receipt.json`, `index-first-receipt.json`,
`index-second-receipt.json`, the named run folders/captures, and `ui-binding-final/console.log`.
The last confirms the final binding method returned 0 and native off. All test-owned processes
and locks ended; other tasks may already own the shared locks. Protected-file and restoration
receipts are retained for every PoC run. The later module-only import changes the package input
as authorised; no artifact is published.

## Shared-document text for Q

- CHANGELOG/COMPONENTS: add launcher-only simulated VR, typed keyboard events, skeletal splay,
  binding UI, owned overlay sort/tint and the optional window-source bridge. The driver gains
  simulate/window switches; live render pacing, off-state behavior and Lua path restrictions remain.
- ROADMAP: N's primitives are implemented on v2n; integration still needs R/F and the later
  features/acceptance. V2/V3 as a whole is not completed by this native task.
- RESEARCH/TESTING: add the timed no-SDK native tests, recorded device data and exact simulated/
  live receipts above; distinguish simulated frames from actual compositor submissions and real
  platform UI refusals from scripted event delivery. The packaged VR module's source catalog and
  build record are now refreshed under ADR 0126; no stale-input checker was bypassed.

Open: task M's in-game keyboard fallback for RequestFailed 23/no registered system.keyboard,
and R's real window-source integration. The module's failure behavior is intentionally unchanged.
Other physical devices, worn comfort and optical latency
are not claimed. Task Q owns whole-milestone acceptance; no merge or publication is authorised here.
