# VR V2 task M: menus, panels and settings

**Initial handover (2026-11-11):** M's Lua implementation was built and tested; full task acceptance was not complete. Painted panels,
the wrist, stock prop spawning, hand-ray properties, simulated keyboard delivery, settings, drag/scroll,
fixed canvases and teardown pass. The actual post-2D window picture works. Required MENU/HTML Resume input
does not work through CLIENT's input API, and the real SteamVR keyboard returns RequestFailed on this rig.
Both are explicitly open below. A passing renderer summary is not presented as passing UI acceptance.

Claude accepted this initial handover and merged `v2m` at `918a6e9` into `vr2` as `2347484`.
The user then assigned M the native input and fallback keyboard follow-up; its results are recorded
in the dated **Follow-up** section at the end. Initial open-item statements below describe that
earlier boundary, not a claim about the follow-up's current result.

**Follow-up result: both M items pass their requested acceptance in simulation and on the Index.**
The bounded native path drives MENU/console; the fallback handles SteamVR's continuing RequestFailed.
The game-window path requires foreground input on this engine build. Final evidence, module identity,
gate and remaining integration limits are in the Follow-up section.

Branch/worktree: `v2m`, initially `vr2` at `1a11de5`. Reviewed N was integrated in `524139c`; reviewed H/L
and current plans in `ededfc5`. Those inbound changes are not M edits/imports. Only M's assigned paths were
implemented. No loader source edit, push, merge into main/vr2, publication, workflow, SteamVR setting change
or native binary import. Commits use configured SheepyLord identity and the required Codex trailer.

## Built

- `cl_ui.lua` composes panels, pointer and beam through F's registry. Off-hand B toggles the wrist; logical
  main/off roles and its attachment mirror. The wrist offers Spawn, Context, Flat screen, Settings, Calibrate,
  Recentre and Exit. `NLVR.Emit("ui_toggle", key)` is the owned test/event entry point.
- `cl_ui_panels.lua` borrows actual `g_SpawnMenu`/`g_ContextMenu`, preserving tabs, search, icons and stock
  callbacks. Roots, borrowed MakePopup panels and property popups are explicitly PaintManual'd into their
  own odd-sized targets. GUI layout sees a scoped virtual desktop; errors restore ScrW/ScrH. Native cursor
  bookmarks are suppressed only during the borrowed open/close operations. Native VGUI callbacks enqueue
  actions for the next owned UI frame, because DoClick can execute after F's current module context ends.
- Ordinary panels open at the head's tracking-space yaw, **1.15 m** ahead, **1.25 m** wide, then stay fixed
  there. Wrist width is **0.32 m**. F's sizes remain wrist menu **513 x 515**, spawn **1537 x 1025**, context
  **1281 x 961**, flat **1921 x 1081**, laser **65 x 1027**. M adds settings **1283 x 963** and flat close
  **131 x 133**; Q can add those two reservations to the central table. All are unique odd pairs.
- `cl_ui_input.lua` maps the main-hand ray to pixels, claims trigger/stick, dispatches actual VGUI cursor,
  press/release/wheel events, retains capture through holds/misses, consumes the release and restores the
  desktop cursor. A mirrored capture retains its old physical trigger claim until release. The UI clears
  both attacks and synthetic mouse deltas before L's mouse turning. Context world properties use **both**
  origin and direction of the controller, including outside the canvas. No screen-derived aim replacement.
- `cl_ui_laser.lua` paints a narrow billboard beam/dot through SteamVR, never scene geometry. Canvases and
  overlays are lazy; Exit destroys owned roots/handles and restores borrowed parent, position, size, dock,
  raw layout slot, divider width, manual painting and initial visibility/input/hang flags.
- Flat calls N's `OverlayWindow`, requesting R's SHOW|NO_MIRROR source, and disables it before destroying
  its handle. Missing exports show the translated update notice. A separate close overlay remains usable.
  The actual window cursor is positioned without the painted-client cursor-move path. This does not solve
  MENU input; that limitation is retained in the assertions rather than hidden by an automatic Resume.
- Text focus identifies engine **TextEntry**, uses **IsMultiline**, requests SteamVR's keyboard, routes
  native events through the page's sole reader and F's owned `native_event` subscription. Results use normal
  text-change/Enter callbacks and a UTF-8 character caret. Focus changes wait for the old closed event;
  closed/removed fields reject late results; numeric fields reject invalid/nonfinite input. Native failures
  remain visible in panel/page status with their exact error.
- The page's reusable BuildOptions exposes interface 10 without redefining F's variables. Calibration emits
  **height_calibrate**, matching L. Binding UI is called only while running. Fixed 20/26-pixel owned fonts,
  full-width titles and GUI Scaler's public `gScF` opt-out keep owned controls readable. The settings combo
  wrapper also receives the control's row height. Borrowed stock controls retain the user's own styling.
- Debug: open keys/handles/sizes, laser UV, last click, drag, keyboard/detail, source state, context ray.
  No new autorun, server channel, permanent hook or idle poller. Source retains named render targets/fonts
  in its engine cache until process exit; active overlay bindings/runtime VR resources are torn down.

Decisions: [0167](../decisions/0167-vr-panels-painted-vgui-and-the-laser.md),
[0168](../decisions/0168-the-vr-flat-screen-panel.md). Forty new messages per language in all six catalogs
are generated by `companion/i18n/vr_ui_catalog.py` from ASCII-escaped data through explicit UTF-8. Complete
catalogs, printf conversions, replacement characters and question-mark runs were checked. Agent-written
translations await human review.

## Tests and evidence

All paths below are local, git-ignored **out/vr/v2m/** in this worktree. Pictures are paths rather than
repository Markdown links so a clean checkout's link check does not require local laboratory images.

- Dedicated suite: **24 PASS** (23 LuaJIT cases and isolated no-Pillow preflight). Command:
  `python -m unittest discover -s companion/tests -p vr_ui_test.py -v`; `offline-ui.log`.
  Covers hit/pixels, claims, click/drag/miss/release, cursor exceptions, mirroring, keyboard focus/lifetime,
  numeric input, callbacks removing fields, deferred VGUI actions, widget restoration, invalid tracking,
  flat fallback, menu ownership, actual page controls/value mappings and no idle native work.
- Original page/framework suite **80 PASS**; driver suite **28 PASS**. `offline-framework.log` and
  `offline-driver.log`. The dedicated prefix is run separately from the tools gate's existing import.
- Release gate **PASS** in `release-3.log`: **34/34 CTest**, **29 + 26 + 909 = 964 Python tests**,
  **3 availability skips**, zero failures; CTest **39.09 s**, main Python group **126.028 s**.
  **Final Release gate PASS**, `release-final.log`: the same **34/34 CTest / 964 Python**,
  **3 skips**, zero failures, All checks passed; CTest **48.35 s**, main Python group **128.880 s**.
  Final dedicated suite: **24 PASS**, `offline-ui-final.log`.

| Session | Backend result | Rendered / submitted | Matched / unmatched | UI result |
|---|---|---:|---:|---|
| sim-05, 4K + GUI Scaler + R | PASS | 5854 / 0 | 5854 / 0 | all except Resume |
| sim-06, reviewed H/L + R | PASS | 5557 / 0 | 5557 / 0 | all except Resume |
| sim-07, cursor instrumentation | PASS | 5782 / 0 | 5782 / 0 | all except Resume |
| sim-08, handoff experiment | PASS | 5852 / 0 | 5852 / 0 | all except Resume; experiment removed |
| **index-02**, 4K + GUI Scaler | **PASS** | **3000 / 3000** | **3000 / 0** | Resume and real keyboard unaccepted |

Simulated rows load no OpenVR and are rendered frames, not compositor submissions. All listed backend rows
have zero Submit errors and no Lua errors. Every full UI receipt stays failed when a required outcome fails;
see each `ui-acceptance.json` beside `summary.json`/`ui-records.json`. Raw failed records were not rewritten.

The fixture supplies scripted head/off-hand poses through the native timeline; the main hand's pose/actions
are adapted at the native-to-Lua test boundary to actual widget bounds. Production ray, hit, input and stock
callbacks are unchanged. The empty PoC has no saved spawnlists, so a fixture ContentContainer in the real
creation menu uses **stock spawnmenu.CreateContentIcon("model", ...)**. The laser invokes its untouched
action: **one new prop** appears. The fixed target is removed through the real property menu and network
action. Typed text becomes **barrel** in a real text field in simulation. A real slider changes snap angle
**30 to 47 degrees**; scroll changes **0 to 165 pixels**. All edited test values are restored after controls
are removed, including raw archived strings. The hand-ray receipt has origin **[821,-647,-56.000004]** and
direction **[-0.9892108,-0.0696630,0.1288761]**, distinct from the head at **[823,-657,-40]**.

Index counters: **90 Hz**, **2468 x 2740 per eye**, centre **3112 x 2752**, traced **1556 x 1376**,
desktop **3840 x 2160**, scale 1, queue mode 2. Steady sample **42.7900 accepted pairs/s**; **0 dropped**,
**54.5258% reprojected** in that window. GPU command/SDK intervals **15.0526 ms**, eye warp **1.0743 ms**,
render-thread CPU **4.6668 ms**, elapsed GPU span **22.8281 ms**, capture transfers **2.0537 ms**.
This is an interaction/capture run with shared-host context saved, not a performance comparison or tuning claim.

Index Exit: **0 owned roots, 0 VGUI differences, cursor [1920,1080] restored**, no client receiver, no timers,
no NLVR global; only `PopulateToolMenu:nativeloader_vr` remains. Both Start/Exit cycles clean. Compared game/VR
strings and live upscaler/FG selectors have **0 differences**. `openvr_api.dll` is absent after Exit. Server
inventories show **8 hooks active / 0 off**, with the permanent receiver; 4067 accepted / 55 rejected syncs
in the first cycle and 78 / 13 in the second (separate from compositor counters).

Every executed session restored cleanly: **2877 depot files verified**, zero missing/size/hash mismatches.
`restoration.json`, `snapshot/rollback.json`, `cleanup.json` and protected-before/after receipts retain the
checks. Protected PoC user.conf SHA-256 stayed
`743bd25806b9e2b2ebd82f7d39248f05af4ae20e8747d85a59f1a8c7718d4f56`.
The authorized main-checkout field-quit helper twice reported **no field game running**; M ended none.
SteamVR was already running, was never quit and its settings were not changed. Foreign locks were waited
out, never removed. `index-01` was cancelled before acquisition when N merged; `sim-02` timed out waiting
with no PoC changes. Later jittered exclusive-create polling retains owner-token release.

## Pictures reviewed

Index directory prefix: `out/vr/v2m/index-02/captures/`:

| Picture | Path below that prefix |
|---|---|
| Wrist, seven entries | ui-wrist/overlay_408021893133.png |
| Real spawn menu and stock barrel icon | ui-spawn/overlay_416611827725.png |
| Context icons/tool controls | ui-context/overlay_425201762317.png |
| Context property phase | ui-properties/overlay_425201762317.png |
| Flat, actual escape/console over black | ui-flat/overlay_433791696909.png |
| Settings | ui-settings/overlay_442381631501.png |

The property action is proved by the target removal; that particular Index image does not visibly retain
the transient property popup, so it is not offered as visual proof of its rows. `sim-05`, `sim-06` and `sim-07`
retain their own property-phase images/records. Simulated search typing: `sim-05/captures/ui-search/overlay_4.png`.
All captures also retain eyes, centre/depth, mirror and timings. The stock GUI Scaler styling inflates some
borrowed tab/navigation labels; fixed canvas geometry and actions pass, but worn readability needs review.
Owned settings combo wrapper clipping found in visual QA was corrected; the short settings-layout control
is **PASS**, `settings-01/summary.json` and `ui-acceptance.json`: **1272 matched rendered frames**, zero
unmatched/submissions/errors, clean rollback. The reviewed final image is
`out/vr/v2m/settings-01/captures/ui-settings-layout/overlay_4.png` (**1283 x 963**) with unclipped combo text.
This 15-second control used package v2m.11 and the same verified 4K GUI Scaler fixture.

## Required open items and concrete next interface

1. **MENU/HTML pointer input.** CLIENT's VGUI APIs work for painted panels but do not activate MENU's HTML
   Resume button. `flat-probe-03` and `flat-probe-04` assert menu visible before every press. At the correct
   **140 x 249** in a 4K window, both cursor getters agree, system focus and cursor visibility are true, yet
   all seven routes leave the menu visible: both setters, clicker off/on, reset, GMod code 107, native code 0,
   and double press. Earlier short-probe positives were **false positives** because a same-frame reset had
   hidden the menu; they are excluded and the attempted production reset was removed. Never count an
   automatic HideGameUI as a successful Resume. Native/runtime picture delivery itself is accepted.

   N/Q needs a bounded, active-VR-only **owned game-window/MENU input** primitive (position, button/release,
   wheel and text/Enter where needed), targeting this process's actual window/input context, not a global
   arbitrary HWND. Balance releases at Stop. M can route only the window source through it; painted VGUI
   keeps its working dispatcher. A verified MENU relay is another option, but its folder and native sources
   are outside M's assigned files. Read-only inspection found no exposed cross-realm input bridge in the
   current client/engine-guard APIs. No blocked console-command flag or loader path was bypassed.
2. **Real SteamVR keyboard UI.** The Index request returns exact detail
   **OpenVR overlay: VROverlayError_RequestFailed**, reproducing N's open platform finding. M shows the
   failure and ignores unowned completion events; scripted event delivery passes in simulation. The actual
   keyboard and Index text step remain unaccepted. No custom keyboard substituted for the binding decision.
3. R's runtime is a **laboratory overlay**, still requiring Q's normal final import/integration. Worn comfort,
   borrowed stock-font readability under GUI Scaler and the final whole-milestone review/approval remain open.

These boundaries are reported rather than editing unassigned native, MENU, loader or framework paths.

## Package and fixture provenance

Index package: `out/dist/gmod-rtx-remix-0.0.0-v2m.10.gma`, **1797 files / 2085555278 bytes**, SHA-256
`21de3bfb5b95751a12b2e4bd1b8ed4f6b6252ffeb03257d4f746511e5d3ba00d`, content digest
`4cdcd7aca72fbdaf662e1ffae486f2567a54df32b3b366ccbd326a65e8176387`.
R's tested `../v2r/out/vr/v2r/final/d3d9.dll` is **418372608 bytes**, SHA-256
`541d3caf77857b348be7d04661a5e1457cdb15872440cd414fc97b407305dfe0`. Supported `--built` overlay kept
**59 other native files packaged**. `runtime-package-source-10.json` and `package-10.log` record commands,
paths and hashes. No DLL was imported or committed by M.

GUI Scaler's installed GMA SHA-256 is
`8f3508fff080f1ba073f2a640c89cb8732c039fc87c1d292360b076bf79bf118`.
Its whole checksum is stale (stored e506e0fa / calculated f029242e). Stock unmodified gmad extracted it;
all **3 files** were proved byte-equal to archive payloads with matching per-file CRCs and SHA-256. The
verified folder/provenance under out was staged as a fresh PoC-only add-on and removed by normal rollback.
No download, Steam-cache edit or weakened repository extractor check. `sim-04` failed safely before game
launch on the strict whole-checksum check; its clean rollback and failure are retained.

`ui-driver-sources.json`, exact helper/fixture snapshots, standard `sources.json`, generated acknowledged
Lua stages and package JSON preserve each run. The initial `sim-01` is also excluded as a UI diagnostic:
three deferred DoClick errors prompted the queue fix; its blank spawn picture prompted explicit popup
painting. V1's one-megapixel wrist-only image check was adapted in M's test wrapper for large bounded RGBA
canvases while retaining the strict wrist glyph check. No production shared driver was changed.

## Text for Q's shared documents

- CHANGELOG: add controller-operated wrist/sandbox/settings panels, captured laser input, translated VR
  options, focus-scoped SteamVR text routing and real window-source display; keep MENU input/real keyboard
  acceptance visibly open until the native extensions/platform checks pass.
- COMPONENTS: M's cl_ui*.lua own lifecycle, borrowed/popup canvases, pointer/keyboard and overlay beam;
  companion owns reusable BuildOptions and the sole native event reader.
- ROADMAP: M's Lua scope implemented; **do not mark full M or V2 acceptance done** while the two required
  live items above remain open. Q owns final integration/review and the user's milestone approval.
- TESTING: dedicated vr_ui_test.py prefix alongside the full Release gate, native/simulated UI receipts,
  exact VGUI/cursor restoration and all panel captures. Renderer success is separate from UI acceptance.
- RESEARCH: `cl_ui_input.lua:21` scopes cursor dispatch; `cl_ui_panels.lua:108` borrows/restores native
  panels; queueing is required because native DoClick is deferred beyond module context. Official
  [PaintManual](https://wiki.facepunch.com/gmod/Panel:PaintManual) documents unclamped painting, and
  [DTextEntry](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/vgui/dtextentry.lua) documents
  IsMultiline and text-change/Enter behavior. Add the measured 4K/Index numbers and concrete MENU input gap.

## Follow-up — 2026-11-11

Scope was widened by the user after Claude's acceptance/merge `2347484`. `vr2` was first fast-forwarded
into M at `dd99a71`, then reviewed P and Q's brief were merged inbound in `cf7fdbe`.
No outbound merge/push/publication or loader edit. Implementation
started in `2021bf2`, with the usual configured identity and Codex trailer.

### Native window input

`vr/native/window_input.{h,cpp}` isolates platform calls behind `WindowCalls`; `Session` owns its
lifetime, and the thin Lua adapter exposes only `nlvr.WindowInput(kind,...)`. The module selects the
unique top-level `Valve001` in **its own process**, rechecks PID/class/ownership before every post
including cleanup, and refuses missing/ambiguous/recycled targets. Lua cannot supply an HWND, PID,
message number, executable, extra key or other-process target. Off/starting/stopping/failed and
pre-first-frame sessions refuse clearly. No SendInput, hooks, focus activation or cursor warp.

Kinds: integer client-pixel cursor; left/right/middle down/up; wheel -8..8 steps using screen-coordinate
WM_MOUSEWHEEL; printable Unicode scalar converted to one WM_CHAR or a UTF-16 surrogate pair; named
Enter/Backspace/Delete/Escape/Tab/arrows/Home/End down/up; release of this owner's held input. Scan,
extended and transition bits follow Win32's message contract. **64 normal messages per acquired VR
frame**, both surrogate slots reserved together; at most **14** owned safety releases bypass that
budget. Duplicate downs/unmatched ups post nothing. Validation, posting/budget failures, Exit,
renderer failure and unload release owned presses. Failed release posts retain bits for retry;
dead/foreign windows are cleared rather than sending elsewhere. Info exposes dimensions, client
pixels, ownership/foreground, held/message/failure counts, never the handle.

**Foreground finding:** the same actual HTML Resume target at 3840 x 2160 was tested both ways.
`out/vr/v2m/window-01/ui-acceptance.json`: foreground=false, menu visible immediately before press,
posted=true, menu still visible afterward; UI acceptance failed. `window-02/ui-acceptance.json`:
foreground=true, menu visible at native down (20.0069 s) and release (20.3505 s), closed at 22.0001 s;
acceptance passed. Native client pixels were **139,248** after floating-point ray-to-pixel mapping.
Both Lua cursor getters stayed **1920,1080**. The real click, not a cursor warp or HideGameUI, closed
Resume. Posting is queue delivery, not engine consumption. The game must own foreground input on
this build; the API deliberately does not activate it. Test setup used the computer-use skill's
window activation for **only M's own PoC** while holding M's lock, before the scripted input; no
desktop click/key/text action produced the acceptance outcome. No SteamVR/field window was activated.

Pictures: `window-02/captures/window-before/overlay_2.png` and
`window-02/captures/window-after/overlay_2.png`. Both sessions rolled back and verified **2877** stock
depot files with no missing/size/hash differences. `window-02` rendered **2293** matched pairs, zero
unmatched/submission errors, no compositor submission (simulation).

### Fallback and test method

SteamVR remains first choice. Only a failed/missing ShowKeyboard opens the 1039 x 391 owned US
keyboard under its target. It keeps the real field's focus, uses trigger press/release geometry,
and provides latched Shift, Space, Backspace, Enter, Close, navigation and Delete. Normal field
text-change/Enter callbacks and UTF-8 caret editing are shared with SteamVR results; numeric and
maximum-character rules are retained. Flat text drains at most eight Unicode characters per frame
through WindowInput; Enter/edit keys use balanced native keys. Text is bounded to 4096 queued
characters. Closing the target/Exit discards pending text/requests and destroys the overlay. A
deferred native keyboard close cannot cancel a newly requested keyboard. Aa on the separate flat
toolbar requests text, X closes. Twelve new labels are generated as escaped JSON/explicit UTF-8:
**52 M messages x 6 languages**, complete checked catalogs.

`vr_ui_followup.lua` drives actual stock model search and flat-window callbacks using adaptive
main-hand poses/native-boundary actions. It does not call DoClick or execute the acceptance command.
Simulation explicitly injects a ShowKeyboard failure **after recording the native simulated
success** to exercise the fallback; Index uses SteamVR's real result. Preliminary sessions supply
S's missing keyboard-size contract only in the test fixture and record `size_contract_fixture=true`;
final acceptance must use S's actual central reservations after the inbound merge.

The first fallback run (`followup-sim-01`) typed `barrel` and produced **34 stock model results**;
guarded Resume passed. Console acceptance failed because showconsole/hideconsole are blocked from
client Lua, giving two explicit Lua errors. This run is excluded as complete acceptance. The test
wrapper now prepares only those two fixed UI operations using the existing PoC launcher's own-window
console route, verifying M's lock, process path, target and per-run token. It never runs the tested
`echo nlvrmconsoleok` command: WindowInput and the laser keyboard must type and submit that. No blocked
flag or production security check was changed.

Offline evidence to date: `followup-native-03.log`: **29 native cases, zero failed**, including seven
M window-input cases and Session Exit/renderer-failure releases against stand-in Win32 calls.
`followup-ui-05.log`: **30 UI/preflight tests pass**, including actual laser-hit fallback typing,
shift/backspace/Enter callbacks, Unicode queueing, closure and delayed native close handling.
`followup-catalog-01.log` records the initial catalog attempt; the corrected catalog run passes
with translated Tab labels. Final Index, provenance and Release-gate results follow below.

`followup-sim-02` (package `0.0.0-v2m.14`, 3840 x 2160, 50 s) passed all its UI acceptance
checks: laser fallback search **barrel / 34** actual stock results, guarded Resume, visible real
console, and the bare console output **nlvrmconsoleok** after typing **19 characters** and Enter.
The native dispatcher reported foreground=true, zero failures and zero held input afterward.
The launcher preparation receipt names only hideconsole/showconsole and the owned PoC PID; it
never supplies echo. `summary.json` has zero Lua errors, normal quit and restored settings;
rollback verifies **2877** files, clean. It remains preliminary for the central size table.
Pictures reviewed: `followup-sim-02/captures/followup-search-results/overlay_2.png` (34 model
results), `followup-console-result/overlay_5.png` (real console with echo/output) and
`followup-typed-search/overlay_4.png` (readable keyboard layout). All paths are under
`out/vr/v2m/`; exact helper/fixture snapshots and source hashes are alongside each receipt.
The additional delayed-toolbar-close regression now brings the dedicated suite to **30 passing
tests** (`followup-ui-05.log`).

The preparatory full gate also passes: `followup-release-01.log`, **34/34 CTest** in **57.07 s**,
Python **29 + 26 + 909 = 964** cases, **7 reported skips**, zero failures, ending `All checks passed.`
The main Python group took **135.687 s**. Final inbound changes will receive a fresh gate below.

S landed as `13e8ced` and was merged inbound in **5d5349a**. All production UI canvas sizes now
read `ctx.Overlay.Sizes`, including settings, flat_close and keyboard. The temporary reservation
fixtures were removed; final runs assert the actual merged table. Additive sidecar conflicts were
kept, and both ASCII-escaped catalog generators were rerun to preserve M's 52 and S's 9 messages.
`followup-ui-central.log` passes **30** tests against this actual table. The provenance refresh
command was rerun (`followup-refresh-central.log`); it reports the module current, nothing to do.

The gate with the reviewed scaffold passes: **34/34 CTest** in **36.38 s**, Python
**29 + 26 + 1072 = 1127** cases, **10 reported skips**, zero failures, `All checks passed.`
`followup-release-central.log` prints **M 30, H 21, L 48, P 28, S 33** tests through S's feature
bridges, with explicit pending W/K/T skips; the main Python group took **150.754 s**.

### Final acceptance and pictures

Both final runs use package `0.0.0-v2m.15`, **3840 x 2160**, the verified GUI Scaler fixture and
S's actual reservations (`size_contract_fixture=false`). **All 14 UI checks and the standard
renderer/rollback receipt pass** in `followup-sim-final` and `followup-index-final`. Each active
UI sequence is 50 seconds; the Index run waited **270.3 s** for Q's PoC lock while holding the
normal VR lock, and simulation waited **204.3 s** for the PoC. No foreign lock was changed.

| Acceptance | Final simulation | Final Index |
|---|---|---|
| Real model search, laser keyboard then Enter | `barrel`, **34** results | `barrel`, **7** results while stock indexing was still progressing |
| Resume guard | Menu visible at down **16.0085 s** and release **16.2575 s**; closed **17.5072 s** | Visible at down **16.0165 s** and release **16.2721 s**; closed **17.5165 s** |
| Console opened, laser keyboard command run | Bare `nlvrmconsoleok` output | Same bare output from `echo nlvrmconsoleok`, **19** characters plus Enter |
| SteamVR keyboard first | Native simulated success recorded, then explicit test failure | Actual **RequestFailed twice**, at **4.1165 s** and **20.0054 s**, no injected failure |
| Fallback source and platform | Local simulated overlay, **1039 x 391** | SDK `visible=true`, **1039 x 391**, `texture_error=0`, `simulated=false`, **1.05 m** wide, for both search and console |
| Exit | **0** overlay objects, no keyboard overlay, normal quit, SDK DLL absent | Same; **0** native held inputs/failures before Exit, **0** Lua errors |

The Index SDK error is exactly `OpenVR overlay: VROverlayError_RequestFailed`. It is retained in
debug and the receipt; the successful fallback does not claim to repair SteamVR's keyboard. Its
actual compositor overlay state and transforms are in each `followup-capture.overlays.keyboard`.
The test never clicks/types through computer use: that tool activates only the owned PoC window
for the foreground control. The production API never activates a window. Echo is not sent by
the launcher's preparation worker; `console-preparations.json` contains only the two fixed UI
operations. Immediate menu visibility is sampled inside the wrapper around the actual native
button call; no HideGameUI/reset occurs between the guard and the click/result.

Raw pictures reviewed under `out/vr/v2m/followup-index-final/captures/`:

- `followup-keyboard-search/overlay_571230650383.png`: the actual fallback keyboard source, also
  verified visible/bound by SteamVR. `followup-typed-search/overlay_571230650383.png` retains the key hover.
- `followup-search-results/overlay_562640715789.png`: the real search field and **7 Results for barrel**.
  The visible indexing progress accounts for the smaller early count than simulation's 34; acceptance
  requires an actual changed query and positive stock results, not a fixed final index count.
- `followup-resume-before/overlay_575525617677.png` and
  `followup-resume-after/overlay_575525617677.png`: window-source before/after the native click.
  The first raw capture precedes the sidebar text paint, so it is **not** a Resume-label legibility
  proof. The same foreground target's fully painted menu is retained in
  `window-02/captures/window-before/overlay_2.png`; the final Index console picture below also shows
  Resume at that location. The immediate guard/click/result records provide the final click proof.
- `followup-keyboard-console/overlay_584115552272.png`: the second real SteamVR fallback overlay.
- `followup-console-result/overlay_575525617677.png`: actual MENU console with the command/output,
  alongside `followup-console-result/overlay_584115552272.png` for the keyboard.

Simulation's corresponding keyboard handles are **4** and **7**, spawn **2**, flat **5**, under
`followup-sim-final/captures/`. Both `ui-acceptance.json` files enumerate every actual PNG path;
all **11 panel images across 7 captures** exist. Eye/centre/mirror/depth pictures and timings are
retained beside the overlays. These are unmodified captured images, not illustrative replacements.

### Final numbers and restoration

Simulation rendered **3892** matched frames, zero submitted/unmatched/submit errors, steady
**77.9602 frames/s**. The Index rendered/submitted/matched **2186 stereo pairs**, **0 unmatched**,
**0 submit errors**, **0 dropped**; **90 Hz**, eyes **2468 x 2740**, centre **3112 x 2752**, traced
**1556 x 1376**. The measured steady interval has **43.9312 pairs/s**, **52.2094% reprojection**,
GPU command/SDK **15.1648 ms**, elapsed GPU **22.8172 ms**, eye warp **1.04193 ms**, render-thread
CPU **5.1120 ms**, capture transfers **1.96027 ms**, overlay-transfer span **0.92672 ms**. These
are a UI/capture exercise with the recorded runtime, not a performance or worn-comfort claim.

Both final snapshots restored cleanly: **2877** depot files, no missing/size/hash mismatch,
no watched settings/data differences, normal quit, settings restored, OpenVR DLL absent after
Exit, and zero owned overlays. Protected `user.conf` remains
`743bd25806b9e2b2ebd82f7d39248f05af4ae20e8747d85a59f1a8c7718d4f56` before and after.
SteamVR was already running; its server remains running (same start time), with no settings or
quit action. The explicitly authorised main-checkout field-quit utility reported **no field game
running**, including immediately before this Index launch (`followup-field-check.log`): M ended
no field game. Test helper/fixture snapshots, `sources.json`, `ui-driver-sources.json`, the fixed
console-preparation receipt, standard profiles, native SDK facts and rollback receipts are retained.

### Module provenance and remaining integration

The requested `python tools/ci/repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll` built/imported the
native change through the provenance tool (`followup-refresh-01.log`); the declared sources include
`window_input.h` and `window_input.cpp`. The command was repeated after integration and after the
Index run; it reports **current, nothing to do**. The final gate accepts the recorded source hashes.
Independently decompressing the package input verifies:

- **gmcl_nlvr_win64.dll: 510464 bytes**
- **SHA-256: `221c07fb268bc53bcd6281c668605c26695c9d75e0b5d42f31696a50faf576bd`**
- Stored only as `packages/vr/bin/gmcl_nlvr_win64.dll.xz`: **206384 bytes**, indexed in `files.json`,
  with the matching canonical source/build record in `tools/ci/pins.json`.

Both final runs loaded that packaged native. The local package has **1808 files**, **2085646546
GMA bytes**, SHA-256 `22f0e7f98667339f6526b5a96bcc88841e95c74121e974a9df3178d2062882ea`, digest
`0edc2b45088dd7d7f4249830046364a349bc18e3ebb92833be310409dee2ac6d`. `package-15.log`, the dist JSON
and `runtime-package-source-15.json` retain its provenance. R's original tested **418372608-byte**
runtime `541d3caf77857b348be7d04661a5e1457cdb15872440cd414fc97b407305dfe0` is a private `--built`
test overlay only; **M imported no runtime**. The other 59 native inputs were kept packaged.

The latest reviewed `vr2` at handover is S's **13e8ced**. R's follow-up/header/runtime import has
not landed there yet. The user's second-arrival rule remains: whichever task Claude merges second
must merge current `vr2` inbound and refresh this module again. Q owns that final integration and
the full milestone/worn checks. M's two requested functional follow-ups are closed by the above
evidence; the foreground limit and SDK RequestFailed are explicit platform findings, with the
fallback covering text entry. Existing GUI Scaler clipping of borrowed stock controls and worn
readability/comfort remain the original integration limits, not a claim of repaired game styling.

Text for Q's shared documents: replace the initial MENU/keyboard open-item text with the bounded
owned-window API and first-choice-SteamVR/fallback policy; add `cl_ui_keyboard.lua` and native
`window_input.{h,cpp}`, the foreground finding and the 14-check simulated/Index evidence. Keep
the SDK failure and measured timing limits visible. No shared document or `loader/` was edited by M.

**Final Release gate PASS on the committed handover:** `tools/test.ps1 -Config Release`,
`out/vr/v2m/followup-release-final.log`, ending **All checks passed**. **34/34 CTest** in **29.60 s**;
Python **29 + 26 + 1072 = 1127** cases, **10 reported skips**, **0 failures**. The main Python
group took **140.786 s**. No production code changed after this gate; only this receipt was added.
Repo conventions and provenance were rechecked before the final commit.

Principal follow-up commits: **2021bf2** (native input/fallback), **16ce035** (foreground/search/console
proof), **298a4a5** (cancellation), **af56af3** (SDK overlay assertions), **809583c** (real central
reservations), **6dda97f** (final simulated/Index handover). Inbound merges only: **cf7fdbe** (P)
and **5d5349a** (S). Nothing was pushed, merged out, published or released.
