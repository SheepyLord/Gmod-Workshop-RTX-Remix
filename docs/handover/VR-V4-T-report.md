# VR V4 task T: tools and weapon wheel

Branch v4t, updated **2026-11-12**. The verification review's four items and Hands-icon
follow-up are addressed. **109 offline tests and 82/82 final simulated review/features
checks pass**, with reviewed W/K and the real server damping factor **0.8**. **Release
gate PASS: 35/35 native, 1538 Python tests, 3 reported skips, zero failures.** C's
integration and final Index proof wait for Claude's explicit go-ahead; no controller-frame
adaptation or Index run was performed this round. This is branch work, not milestone approval.

## Verification review of 81ae9750: current fixes and evidence

Evidence paths here are under **out/vr/v4t/**. Production **3aa19b1b**, then **eafd3747**;
failing Hands-texture regression committed separately as **e38592bb**. All source changes
remain within T's assigned paths. W/K, loader, native binaries and framework are unchanged.

| Finding | Fix | Failing-first and passing proof |
|---|---|---|
| 1: empty ULib event fails Start | Register the ordinary ctx.hook before registry inspection so ULib creates its priority lists. Unknown/detached/unsupported registries retain that ordinary hook without raising. Recognised registries retain post-dispatch replay. | verify2-before.log reproduces ULib-empty and unknown-library failure. Faithful ULib has distinct ordinary/priority tables; empty/populated events exercise Start, exact table identity/content restoration, Stop and second Start. Ordinary fallback obeys an unknown library's normal ordering. |
| 2: wrong damping name | Read **physgun_DampingFactor**. The private native observer and independent checker compare the actual factor as well as force/damping/arrival values; missing factor evidence fails. | verify2-before.log fails the corrected-name and wrong-native-factor counterexamples. Final **183 observations** match **0.8000000119**, with no production convar write. The newly exposed physical residual and its fix are documented below. |
| 3: cache misses moving hands | Coalesce world placements within **1 mm / wrapped Euler norm 0.1 degree**, always against the last submitted transform. Width/visibility changes apply immediately. | verify2-before.log fails moving-hand and tolerance tests. Passing tests move all 100 frames, require 3..20 native placements, bound accumulated positional lag by 1 mm, and exercise angle wrap, larger rotation and width changes. |
| 4: identity used as origin evidence | Remove draw-start/attachment equality from acceptance. Fit actual luminous capture pixels, measure fitted-line alignment at the projected attachment, and measure actual visible beam start against captured model depth. | verify2-before.log rejects the previous false positive: reported draw/attachment remain identical while actual image pixels move 3 pixels. New acceptance rejects it. No zero-unit three-dimensional origin is claimed. Final nonzero image errors are below. |
| Hands inherits base icon | Exclude both weapon_base's inherited DrawWeaponSelection and its separate inherited WepSelectIcon texture; retain genuine overrides and their bounded drawing. | verify2-before.log; then verify2-inherited-texture-before.log fails after modelling the stock texture inheritance too. Final tools-wheel/overlay_4.png visibly shows **[ ]**, not generic paper. Stock weapon_base/cl_init.lua:18 defines the inherited texture. |

The exact offline suite is **companion/tests/vr_tools_test.py**, **109 passing cases**
(**92 LuaJIT + 17 independent Python**), verify2-offline-109-final.log. Nine failures were
recorded before the initial production fixes. The later native-residual regression also
fails before its correction (verify2-residual-before.log). No foreign test/implementation
was changed. The existing gate bridge discovers the expanded suite.

## Damping residual: retained native failure and bounded correction

**verify2-features-01 / v4t.11 FAILED 80/82**, driver/restoration clean. Reading the real
factor gives **0.8**, rather than the former fallback 1. Yaw remains within **0.1582 degrees**,
but pitch/roll settle **15.8748/15.0001 degrees** from the independent hand goal. The native
factor check itself passes all **183 observations**. This run also preserves the unwanted
inherited Hands paper icon. It is not final acceptance.

T now adds a bounded integral **orientation goal trim** using the actual-to-desired world
axis-angle error: gain **8/s**, at most **2 degrees per physics callback**, at most **30 degrees
total**. It ignores travel errors above 30 degrees and resets on a target jump above
5 degrees or disabled angular control. It does not require an artificially motionless hand.
Server angular force/damping/arrival/factor values, zero linear contribution, native hold
and permissions remain unchanged. Only the requested angle is trimmed; receipt/debug and
independent acceptance still compare against the **untrimmed desired hand orientation**.
The [shadow parameter contract](https://wiki.facepunch.com/gmod/Structures/ShadowControlParams)
and the observed native result inform this choice; no force parameter is raised to hide it.

A labelled independent toy plant models the measured 90-to-75-degree equilibrium and
tests convergence, reset and bounded trim. It does not simulate Source physics. The full
fresh native case below is the decisive proof, with the unchanged **5-degree error,
0.5-degree settled range and 1-degree/s spin limits**. The failed run is retained intact.

## Final verification package and simulated case

Normal package **out/dist/gmod-rtx-remix-0.0.0-v4t.12.gma**, production **eafd3747**:
**2,085,960,145 archive bytes**, **1819 archive entries** (1818 indexed payload files), SHA-256
**ef8f13a98f3a9d4baed93a160e5fb1c0292d48ed10b9a3b2b1e9f347d55eedbe**.
package-source-12.json/package-12.log/package-12-byte-proof.json record the source/build and
byte equality of **8 T + 5 W/K Lua sources**, with all **5 reviewed native hashes unchanged**.
Reviewed base remains **a35897ce**, merged as **e4769052**. Later Q head **59792b60** was
observed, not merged into the frozen measured source; no C adaptation or Index run.

Command: python companion/tests/vr_tools_poc.py --tools-case review --seconds 160 --simulate
--evidence out/vr/v4t/verify2-features-02 --package out/dist/gmod-rtx-remix-0.0.0-v4t.12.gma.
It waited for C's PoC lock, then normal-quit/restored itself. Driver/checker exit **0**,
**82/82 PASS**, including all three real K B checks, native forced-drop paths, held-stick
handoffs, no held-trigger Use, real tool actions and refused-switch feedback. Evidence:
verify2-features-02/tools-acceptance.json, tools-provenance.json, summary.json and
restoration.json; independent output verify2-features-02-check.log.

| Measurement | Final actual result |
|---|---|
| Yaw/pitch/roll error | **0.001903 / 0.061300 / 0.001140 degrees**, independent matrices |
| Settled orientation range | **0.002902 / 0.117800 / 0.001749 degrees** |
| Maximum settled spin | **0.16626 / 0.27946 / 0.12031 degrees/s** |
| Maximum linear speed | **0 / 0.091424 / 0 Source units/s**; pitch is about **2.286 mm/s**, not zero |
| Contact-to-gun-ray error | **2.254 / 0.492 / 2.264 mm**, real offset-COM gravity barrel |
| Push/pull | **+4.971812 / -4.971812 m**, actual transforms/contact, not T distance debug |
| Native limits | **183 matching observations**, angular **5000**, angular damping **10000**, arrival **0.05 s**, factor **0.8** |
| Image beam alignment | **0.223957 / 1.207852 internal render pixels** from fitted captured beam centreline to projected attachment; **143/126** fitted rows |
| Visible beam boundary | **0.488283 / 1.495685 output pixels** from measured gun boundary; captured model occlusion **87/90 output pixels** |
| Forced drops | **1 call per tracking/hand/controller/creation/Stop path**, true before, false after and **15 sustained non-held rows each**; death also passes |
| Rendering | **12,887 rendered/matched**, zero unmatched/submit/Lua/module failures, **0 submitted** in simulation; exactly two required injected fault messages |
| Hook cooperation | **3734 observed beam draws** with both existing peer counters equal and positive |
| Restoration | Normal quit, two cycles, all originals/settings/registry restored; **2877 depot files** verified, no missing/size/hash mismatch |

The fitted pixel line and first visible root come from the actual PNG. The production
DrawBeam start argument is unused by acceptance. Internal dimensions **1556x1376** differ
from upscaled colour **3112x2752**: the new alignment bound is **2 internal render pixels**,
not the former tautological 2-output-pixel diagnostic. An initial read-only development
fit using output pixels rejected the old pull image at **2.299 output pixels**; that
receipt remains verify2-image-development.json. Pixel-resolution normalization is explicit
in verify2-image-resolution.json and the checker. The visible-boundary bound remains
**12 output pixels**. Opaque gun geometry prevents direct recovery of the hidden 3D or
longitudinal root; the proof measures lateral alignment and the visible model boundary.

Visually reviewed final tools-wheel/overlay_4.png (Hands glyph), tools-roll/centre.png,
tools-info/overlay_8.png and tools-refused/overlay_4.png under verify2-features-02/captures. All source snapshots,
SDK images/depth/timings, settings and protected hashes remain. Instrumented simulation
rate **82.216 frames/s** is not Index performance. Protected user.conf is unchanged.
No field game was running or ended. SteamVR remained running and unchanged.

## Current verification gate and remaining work

**tools/test.ps1 -Config Release PASS at fcb7c6a4**, clean source at invocation, exit 0.
Receipt/log: **verify2-release.json/log**. Native **35/35 CTest in 43.61 s**; Python
**29 + 26 + 1483 = 1538**, **3 reported skips**, zero failures, main group **128.313 s**.
The gate explicitly discovers **VR T tools: 109 tests**. Only documentation receipts
changed afterward; no production, probe or test change followed the gate. The scope audit
verify2-scope-audit.json confirms **41 owned paths, zero foreign paths** against a35897ce.
Documentation conventions pass (verify2-doc-check.log). No T driver/game/prepared state
remains; PoC lock, pending marker and VR lock were all absent at the final check
(verify2-leftovers.json). No foreign session/lock was changed.
C's accepted frames/explicit go-ahead, any required private-pose adaptation and fresh
package simulation, final Index proof, Claude's review and Q/user combined acceptance remain
open. W's **10.9 cm nominal-muzzle discrepancy** is still foreign; T's visual beam uses the
rendered attachment. Proposed shared-doc text should now name **8 T modules / 109 tests**,
ULib-safe fallback, real damping/trim, bounded placement and image-derived evidence.
The earlier sections below are **historical frozen-source receipts**, not proof of this
package; their zero-unit beam identity, exact-transform cache and factor-1 assumptions
are explicitly superseded above.

## Earlier review receipts (historical)

## Independent review of 889b5406: fixes and failing-first tests

All evidence paths in this section are relative to **out/vr/v4t/**. The offline suite is
companion/tests/vr_tools_test.py: **83 LuaJIT scenarios + 15 independent Python cases**.
It uses its own W stand-in offline; every game run uses the actual packaged W and K.
review-offline-final.log records 98 passing cases. The existing gate bridge discovers them.

| Item | Correction | Failing-before evidence and verification |
|---|---|---|
| 1: stick handoff | Physical-hand stick claims latch until radial neutral, through drop, freeze, pose loss and hand swap. Untracked/dropped holds emit no native distance keys. | review12-before.log; ownership/locomotion command regressions. Native freeze-up/release-down/release-diagonal: **19/27/28 rows**, zero arc/crouch edge and **0 degree** yaw range. |
| 2: wheel trigger handoff | Retain the physical trigger claim and command suppression until release, including close/cancel/mirroring. | review12-before.log, owner asserted on the frame after close. Native eligible nearby Use entity: held trigger **0 calls**, fresh press **1**. |
| 3: forced drop | Entity:ForcePlayerDrop; retain failed creation until Tick after native attachment. Server blocks consumed primary fire until valid release sync plus attack-free command; client waits for the authoritative empty receipt and retains rearm claims. | review34-before.log, review3-rearm-before.log, review3-creation-before.log. Native tracking loss, hand change, controller fault, creation failure and Stop each drop a genuinely held prop and remain released. Death also releases it. |
| 4: server limits | Read live physgun angular/damping/arrival/ragdoll/dampFactor values. T supplies **zero linear force/damping**. | review34-before.log, review8-linear-before.log; offline changed-CVar and zero-limit cases. **183 native parameter observations** equal server **5000 / 10000 / 0.05 s** in the final run. |
| 5: beam hook cooperation | Replay the existing stock/ULib registry before local suppression, including engine-cached dispatch; restore only owned registrations on Stop. | review57-before.log and review5-cached-before.log. Both native peer handlers run with equal positive counters in **3878 observed draw calls**. Material/Color/debug are cached. |
| 6: selection/info/snap | One networked SelectWeapon attempt, wait at most 1 s, then a passive 2 s refusal notice. Use SWEP DrawWeaponSelection inside a clipped icon area. Exclude unsupported Use-modifier tool hints. IN_SPEED snaps the angular goal using gm_snapangles without consuming L's bit. | review6-before.log, review6-icon-clip-before.log. Native refused switch **1 call + visible notice**; hand yaw 37 degrees yields **44.9645** snapped and **37.0447** after release. Custom icon/mapping and error cleanup checked offline. |
| 7: frame cost | Reuse debug/entry objects; cache material, Color and bone/attachment ids. Tool text changes immediately on semantic changes, otherwise polls at most 4 Hz. Inventory polls only while open at most 4 Hz, sorting/describing only on membership changes. Exact unchanged Show/Place skip native calls. | review57-before.log; cache/call-count regressions for closed/open wheel, phrases, tool native calls and repeated beam draws. No whole-frame performance claim is inferred from mocks. |
| 8: independent proof | Ownership tests assert absent IN_USE/FORWARD/BACK; partial-stick rate integrates actual command duty. Distances use recorded body/contact/muzzle transforms. Beam proof uses intercepted DrawBeam, separately queried model attachment and exact-pose raw colour/depth captures. Real offset-COM barrel has gravity enabled; drops include pushed sticks. | review8-before.log rejects the former false positives. review8-chunk-before.log, review8-attachment-before.log and review8-occlusion-before.log expose evidence defects before their corrections. Final native measurements below. |

**Shared hook notice:** T now has a nil-returning StartCommand hook under its own module
id solely to suppress reacquisition from a consumed trigger. K retains its separate
reload/clip hook. Neither replaces the other's result. Pickup, permissions, prop protection,
tool actions and freeze/unfreeze remain native. Message 97 is still one hand boolean;
96 remains server-to-client hold state. No foreign implementation or loader file was edited.

Native API diagnostic **review-api-before-01** disproved the stronger initial mock assumption:
on this build **both** Player:DropObject and Entity:ForcePlayerDrop immediately release a
physgun prop, but held attack reacquires it about 0.3 s later without a rearm guard. The
mock was corrected; API spelling alone is not the fix. That run's provenance-note.json
distinguishes staged bytes from a later observer snapshot. Subsequent runs freeze private
source bytes at invocation. Failed creation additionally occurs before the native held flag
becomes true; the final deferred drop proves before=true, immediate=false after attachment.

## Final packaged simulated review/features case

Reviewed **vr2 a35897ce -> v4t merge e4769052**, including W 16a27dd1 and reviewed K.
T production is **47c95bc3**, package **out/dist/gmod-rtx-remix-0.0.0-v4t.10.gma**,
**2,085,956,822 archive bytes**, **1819 archive entries** (1818 indexed payload files), SHA-256
**b7e5181bf7d62771aa0bfd1ed2aadaa36d89bb5562c8b3663a6dae389a45d755**.
package-source-10.json/package-10.log record the normal build. package-10-byte-proof.json
matches **all 8 T + 5 W/K Lua sources** byte-for-byte and the **5 reviewed native payloads**
to their prior hashes. No native override/import. review-scope-audit.json finds **41 owned
changed files, 0 foreign files** against the reviewed base. Later vr2 Q merge 59792b60 was
observed, not merged into this frozen measured source; C remains gated by Claude.

Command: python companion/tests/vr_tools_poc.py --tools-case review --seconds 160 --simulate
--evidence out/vr/v4t/review-features-06 --package out/dist/gmod-rtx-remix-0.0.0-v4t.10.gma.
This includes the full 60-second features sequence plus the review scenarios. The independent
reader returns **exit 0, 82/82 PASS** in review-features-06/tools-acceptance.json and
review-features-06-check.log; driver exit 0 is in its tools-provenance.json.

| Measurement | Actual final result |
|---|---|
| Prop | HL2 props_c17/oildrum001, gravity enabled, local mass centre **[0,0,22.5] units**; only initial pre-pickup placement frozen |
| Yaw/pitch/roll settled error | **0.03720 / 0.04606 / 0.03066 degrees**, independent pickup/hand/body matrices |
| Settled position/orientation | **0 units/s** linear speed, **0 degrees/s** spin, **0 degree** orientation range in all three fixed-input windows |
| Contact-to-gun-ray error | **2.255 / 0.430 / 2.270 mm** |
| Actual push/pull distance change | **+4.971812 / -5.009742 m**, body transform/local contact/server muzzle, not T debug distance |
| Five forced paths | **1 real ForcePlayerDrop call per path**, held before=true, immediate/0.15 s confirmation=false; **15/14/15/14/15** sustained non-held rows for tracking/hand/controller/creation/Stop |
| B checks | **OnPhysgunReload, unfreeze, tool B white reset all PASS** with actual K |
| Tool actions | Real remover; colour **RGBA 32/140/220/255**; A samples **RGB 32/140/220**; B resets **255/255/255/255** |
| Visual beam | Two exact-pose draw/capture pairs: **0 units / 0 pixels** draw-to-model origin difference; raw luminous start gaps **0.283 / 0.868 pixels** after measured model occlusion **87/88 pixels** |
| Rendering | **13,373 rendered**, **13,374 matched poses**, **0 unmatched**, **0 submitted** (simulation), **0 submit/Lua/module failures**; separate counters differ by one |
| Fault policy | Exactly the two deliberately injected controller/creation errors are required; no unrelated error is ignored |
| Restoration | Normal quit, two cycles; originals/settings/registry restored, **2877 depot files** verified with no missing/size/hash mismatch |

The beam checker retains its **0.4-unit / 2-pixel origin and 12-pixel visible-gap limits**.
Captured signed axial depth independently locates the first unoccluded beam point; it
does not excuse an unexplained gap. Fixture tests distinguish real occlusion from a missing
visible segment. The corrected origin is the rendered model attachment: **W's nominal muzzle
was 4.369035 units (10.9 cm) away**, reported to Claude as a foreign W issue. T uses the
attachment for its visual beam, with W fallback; W's aiming geometry was not changed.

Visually inspected final pictures: review-features-06/captures/tools-roll/centre.png,
tools-wheel/overlay_4.png, tools-refused/overlay_4.png and tools-info/overlay_8.png.
Raw eyes/centre/depth, timings, console, snapshots, package/settings/rollback receipts remain
in that run. **84.836 frames/s** is an instrumented simulated result, not Index performance.
Protected user.conf SHA remains **743bd25806b9e2b2ebd82f7d39248f05af4ae20e8747d85a59f1a8c7718d4f56**.
No field game was running or ended. SteamVR remained running and unchanged.

## Review-round failures retained

- review-features-01 (v4t.6): global hook.Call/Run wrapping did not reach the engine-cached
  beam dispatcher; instance-level native observer also missed metatable calls, and raw
  CurTime phase boundaries drifted during capture stalls. Live-registry replay, scoped
  metatable observers and command-clock correlation fix those defects.
- review-linear-trial-01 (labelled private experiment, not production acceptance): native
  origin target and zero linear contribution each keep ray error **0.002253 m**; a COM target
  causes **0.567748 m** error. T now leaves native linear positioning alone.
- review-features-02 (v4t.7): beam capture metadata missing; failed-creation drop called
  before native attachment. The other review cases pass. Retain the failed acceptance.
- review-features-03 (v4t.8): long native capture JSON exceeded GMod's console print limit;
  partial diagnostics remain explicitly non-acceptance. Bounded per-realm chunked transport
  validates completeness, counts and duplicate pieces; no truncated record is accepted.
- review-features-04 (v4t.8): **81/82**, actual nominal-W/rendered-muzzle discrepancy.
- review-features-05 (v4t.9): initial checker **81/82** because it ignored model occlusion.
  The original failed output is retained; read-only corrected-check output is **82/82**.
  Its wheel picture then exposed custom icon overflow. A failing clip test preceded the
  final packaged correction; **review-features-06 is the fresh final 82/82 proof**.

No failed run/evidence was deleted or silently relabelled as a final pass. Only T files
changed. All commits use the configured SheepyLord identity and required Codex trailer.

## Current Release gate and open work

**tools/test.ps1 -Config Release PASS at f26577e3**, clean source at invocation, exit 0.
Evidence: **release-review.log/json**. Native **35/35 CTest, 56.09 s**; Python groups
**29 + 26 + 1472 = 1527**, **3 reported skips**, zero failures. Main group **145.410 s**,
including T's **98** cases and throwing-icon cleanup. Only documentation receipts changed
afterward; no production/probe/test change followed the gate. Documentation conventions
also pass (review-doc-check.log). No T driver/game/prepared transaction remains; the final
shared lock/pending marker belongs to C's live review3/sim-cal-01, left untouched
(review-leftovers.json). C's reviewed merge, T private-pose adaptation
against C's documented frames, a new simulated package proof if inputs change, and final
Index proof on that same package remain open. **Do not run Index until Claude says C landed.**
Q's later combined acceptance/user milestone approval remains external. Shared-doc proposal:
list T's **8 Lua modules and 98-case suite**, the rearm/selection/cache changes and the
independent offset-mass/drop/beam measurements. The earlier nominal-muzzle self-comparison
and debug-derived distance numbers below are historical and superseded by this review.

## Earlier integration and prototype receipts (historical)

## 2026-11-12 reviewed W/K integration

Merged reviewed **vr2 a35897ce** into T as **e4769052**. This brings main's reviewed
unsubscribe/RTX-client/colour-cap inputs, reviewed W **16a27dd1** and reviewed K. The only
merge conflict was the decision index; both K's 0179/0180 and T's 0181/0182 rows remain
in order. Incoming loader/client changes are from that expressly requested merge; T
authored no loader edit, foreign implementation change or native import.

Input audit: W claims armed trigger/grip and permits A when unclaimed. K claims A for
physical clip guns, leaving physgun/toolgun A to W; K retains tapped B until native
readiness and a networked command. T now respects an earlier B owner before opening a
hold, and cancels if it loses B while open. Without this correction a pending K tap could
be consumed by an unowned wheel. **claims-before.log** retains two failing regressions;
**claims-after.log** passes all **68** offline cases (59 LuaJIT, 9 independent Python).
The other new tests preserve physgun/toolgun attack/A/reload and K's clip-gun A claim.
Production fix **f263643a**; only T's wheel and its tests/docs changed.

New normal package **out/dist/gmod-rtx-remix-0.0.0-v4t.5.gma**: **1815 files**,
**2085942377 GMA bytes**, SHA-256
**d2720c7c13e99b57457cf6d4565c4cf0bb20dd6246ea8533567cef472e81d914**.
Built at f263643a from normal inputs, no override/import. package-source-5.json,
package-5.log, package-5-byte-proof.json retain source and native fingerprints; all five
T sources match byte-for-byte. integration-source-proof-5.json also independently
matches all five W/K entry/helper Lua sources to the reviewed worktree.

First run **features-integrated-01** failed and restored cleanly: initial play-space yaw
was **-11.4114 degrees**, rather than the declared zero. This invalidated pitch/roll axes
and the level-target guard, although real menu choices, native reload hook and unfreeze
worked. The private fixture had removed the inactive fixed-heading guard. **4da168db**
retains that guard before/after VR while returning immediately during active W/K input,
saves/temporarily zeroes m_yaw before Start, then restores and compares its exact string.
The shared cleanup also restores it on early failure. No core/pose/controller code changed.
The failed run, summary and check output stay failed.

Retry **features-integrated-02**, same packaged production code, **60 active seconds**:

| Check | Result |
|---|---|
| Complete receipt | **PASS, 50/50**, zero failed checks |
| Rendered/matched/SDK submitted | **4611/4611/0**, zero unmatched/submit/Lua/module errors |
| Yaw/pitch/roll maximum settled error | **0.03000/0.02533/0.03378 degrees** |
| Push/pull delta | **+4.97000/-4.93213 m** |
| Beam | **26** fresh settled samples, **0 units** origin error |
| Native B | **OnPhysgunReload, unfreeze and tool white reset all pass** |
| Tool trigger/A/B | Actual **RGBA 32/140/220/255**, A sample **RGB 32/140/220**, B reset **255/255/255/255** |
| Wheel/claims | Actual Hands and crowbar selections, tap-no-wheel and ordinary W/K actions pass |
| Restoration | Normal quit, two cycles, all originals/depot/settings restored; m_yaw **0.022 -> 0.022** |

Steady simulated rate **76.431 frames/s** is this instrumented fixture, not headset
performance. Current simulated source pictures were inspected at
features-integrated-02/captures/tools-info/overlay_7.png and tools-wheel/overlay_4.png.
No field game was running; the normal-quit helper was not invoked. SteamVR was left
running and unchanged. **Complete Release gate PASS** at **90faa472**:
tools/test.ps1 -Config Release, **35/35 CTest in 55.16 s**, Python **29+26+1442=1497**,
**3 reported skips**, no failures; main group **146.937 s**, T **68** cases.
Evidence: **release-integrated.log/json**, exit 0. Only this receipt/resume text changed
afterward. All earlier sections/receipts below remain historical evidence and are not
reattributed to this package. The final PoC lock belonged to C, left untouched; no T
driver/game/prepared transaction remains from these completed runs.

## Implementation and interfaces

- cl_tools.lua: W's held-distance convergence, claimed main-stick distance controls, tool
  information beside the model's grip bone and the local physgun beam from W's actual muzzle.
- sv_tools.lua/sv_tools_rotation.lua: observe confirmed native pickup, attach an angular
  controller to that same physics body, publish held state and release safely. Engine pickup,
  position, collision, freeze/unfreeze and permission hooks remain authoritative.
- sh_tools_math.lua: rigid orientation, native distance-key duty, stable inventory order,
  paged layout/picking and stage/operation-aware translated tool information.
- cl_tools_wheel.lua: B hold 0.3 s, a 42 cm ring, Hands first then HUD slot/position order,
  SWEP icons/HL2 glyphs and names. At most 12 entries/page. Beyond 24 cm up/down within 10 cm
  horizontally pages once; returning inside 18 cm rearms. Picking dead zone 3 cm. Release
  selects in CUserCmd, skips prediction command zero and retries up to one second for engine
  acknowledgement. Tracking loss/death/Exit/mirroring cancel.

W's public section-3 interface is unchanged. Optional NLVR.Tools.WheelOpen exposes wheel
state. W owns armed trigger/grip and A; K owns B taps. T claims B holds and consumes attack/
reload while open, preserving W's trigger claim. A held trigger stays consumed until release
after closing. Without W's service, T owns no resources/input. Stop is idempotent.

Tool info reads the real tool and Information entries, showing its translated name and
Trigger/A/B actions in the reserved **643 x 133** source. It follows Active.model's grip
bone, with shown-hand fallback, and paints only on content/mode changes. The wheel is
**1035 x 1037**. Tool application and menu callbacks are never reimplemented/called directly.
Repeated pickup detaches the previous helper without dropping the native hold. Stopped
callbacks are inert. A solver failure logs once, then owned Tick releases outside physics.
Decisions: [0181](../decisions/0181-the-physgun-in-vr.md),
[0182](../decisions/0182-the-vr-tool-info-and-weapon-wheel.md).

## Physgun choice by measurement

Native baseline native-02: settled yaw/pitch/roll errors **0.8873/95.3241/90 degrees** for
90-degree hand turns. Command mouse wheel gives **0 m** distance change. engine-01 measures
Use+mouse X/Y and movement keys: X adds yaw, Y rotates about the other view axis, strafe-left
spins yaw, turn-left does nothing. Commands, sensitivities, angles and SaveTable fields remain.
No exposed held-angle field was found; static strings alone were not treated as writable data.
This does not claim that every possible native-input feedback controller is impossible.

Choose the measured angular shadow controller: invisible, non-solid/non-transmitting
base_anim on the **existing native-held PhysObj**, following pickup-relative orientation
from validated server hands. Its linear goal continues current velocity for 50 ms; no
teleport or mass/gravity/drag/collision/ownership change. Native holding/position remains.
Private motion-01 trial errors **0.0405/0.0407/0.0332 degrees**, native spin **0**, range at
most **0.0000013 degrees**. Production native-03 and features-03/04/05 confirm settling
without the private prototype. Native **Use+forward/back** gives push/pull. Partial stick
uses elapsed-time duty after a 0.2 dead zone; mouse deltas are consumed after L reads them.
Changed-only reliable hold state has no silence timeout; local tracking loss suspends control
until recovery or authoritative drop. The existing physgun_drawbeams preference is respected.

## Historical sources and pre-K package

Reviewed inbound only: M 46cd0e4; R ddd6737 (vr2 61237bf); W 9d50355b (vr2 0e83c0e7),
then W's report/C brief; Q 65ff5178 (vr2 6117fa27). No loader/framework/W/K/M/P implementation
edit, native import, push, outward merge, publication, tag or workflow by T.

Normal package out/dist/gmod-rtx-remix-0.0.0-v4t.4.gma, built at **43ac9002**:
**1813 files / 2085757997 GMA bytes**, SHA-256
8c51b146cf30ca6b75b602a889ef384f61e81ad811a253f1b32915cdc8f25612;
manifest digest 9947c908a60ed807c946219e8e3202ae06c2fdfebcfbb26bfe983a23c4d558c7.
All five T Lua files independently read from it were byte-equal to that checkpoint's source
(package-4-byte-proof.json). Later changes affect only the private checker/fixture.
R runtime **418403840 bytes**, SHA-256
027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278;
Q/M module **510464 bytes**, SHA-256
a1628079de069a7a747d506a23ee8f7c957f18f8f7e2283155fd896205fc13b7.
No built-DLL overrides. package-source-4.json, package-4.log and dist summary retain provenance.
All evidence paths below are relative to **this worktree's out/vr/v4t/**.

## Historical pre-K simulated proof: features-05

Production driver --simulate, actual packaged W/T and K's empty slot; no game-time W stand-in.
**60 active seconds**, gm_construct, baseline camera **(0,0,512), angles (0,0,0)**. Tracking
head (0,0,1.6) m, main hand (0.3,-0.25,1.2) m, off hand (0,0.6,1.2) m; **40 units/m**.
Fixture selects right dominance/standing/zero trim and restores every original raw string.
Native pickup, separate 90-degree axes, push/pull, A freeze, B tap, Hands wheel/tap, real
spawn-list laser clicks for remover/colour, trigger/A/B, then crowbar selection.

| Witness | Result |
|---|---|
| Rendered/matched/SDK submitted | **4836/4836/0**; zero unmatched, submit errors or Lua/module errors |
| Maximum settled yaw/pitch/roll error | **0.0375/0.03343/0.04105 degrees**, 11/10/10 server samples |
| Declared 90-degree hand deltas | **0 degrees error** for all axes |
| Settled range/native spin | **0 degrees / 0 degrees/s**, within recording precision |
| Distance | **2.35156 -> 7.32157 -> 2.35156 m**, push **+4.97000 m**, pull **-4.97000 m** |
| Freeze/unfreeze | A freezes; B unfreeze **pending K** |
| Native hooks | Pickup, successful pickup, drop, freeze observed; reload **pending K** |
| Beam | **26 fresh settled samples**, actual draw origin vs separately sampled W muzzle **0 units error** |
| Wheel/tap | Actual nlvr_hands then weapon_crowbar; tap closed, unchanged paint count |
| Actual tool choices | remover, colour; authoritative active class gmod_tool |
| Remover | Identified target's non-fixture native removal inside action interval |
| Colour/A sample | Actual target **RGBA 32/140/220/255**; A copies RGB **32/140/220** after 7/9/11 preparation |
| Tool B reset | Still coloured: **pending K**, not passed |
| Tool canvas | **2 paints**, one per tool; reserved extents/error-free simulated binding |

The checker independently composes **current_hand * transpose(pickup_hand) * pickup_body**
from separately observed native body/hand angles, never production's target/difference.
Both native spin and range must settle. Earlier independent reanalysis is retained as
orientation-independent.json in native-02, motion-01, native-03, features-03/04. Missing
target/fixture cleanup cannot certify remover; colour/reset require identified server
before/after changes. A simulated overlay cannot certify an actual Index source.

The receipt stays **false for three K-dependent checks**: native reload hook, unfreeze,
tool reload. Renderer success never waives them. Steady simulated rate **80.39 frames/s**,
covered GPU/SDK sum **14.240 ms**, elapsed GPU **14.269 ms**; capture/measurement exercise,
not headset throughput or quiet performance. Raw records, source/staging/provenance snapshots,
captures, timings, summary and tools-acceptance.json remain.

Visually inspected: features-05/captures/tools-coloured/centre.png (clear blue cube);
features-03/captures/tools-info/overlay_6.png (readable name/Trigger/A/B);
features-03/captures/tools-wheel-weapon/overlay_3.png (readable 12 cards, crowbar highlighted);
native-02/captures/tools-roll/centre.png (beam from gun front). Existing raw-pose hand
pictures do not accept natural alignment before C.

## Index component proof: index-01

Same actual v4t.4 package, **60 active seconds**, both standard locks, no simulated SDK.
All T-owned checks pass; the same three K-dependent checks remain red. **2667 rendered /
submitted / matched stereo pairs**, **0 unmatched / submit errors / drops**, **5464 presents /
2817 reprojected**, 90 Hz. Eyes **2468 x 2740**, centre **3112 x 2752**, primary traced
**1556 x 1376**. No Lua/module errors; normal quit, two cycles and clean restoration.

Maximum settled yaw/pitch/roll errors **0.0369 / 0.03407 / 0.03395 degrees**; native spin
and angular range **0**; declared hand delta errors **0**. Distance **2.35156 -> 7.32157 ->
2.35156 m**. Beam **26** fresh samples, **0 units** origin error. Remover/colour/A, Hands/
crowbar selection, tap and both sources pass. Actual SDK source receipts: **simulated=false,
visible=true, texture_error=0, transform_error=0**, tool **643 x 133 / 0.30 m**, wheel
**1035 x 1037 / 0.42 m**, with their OpenVR transforms retained.

Actual source/scene images visually reviewed:

- index-01/captures/tools-info/overlay_1348619730961.png
- index-01/captures/tools-wheel-weapon/overlay_1335734829070.png
- index-01/captures/tools-roll/centre.png (beam from the gun to the held cube)
- index-01/captures/tools-coloured/centre.png (blue cube)

The unmodified original pitch window retains **69.92185 units/s** maximum linear speed in
one boundary sample. At server **8.775 s** its command aim starts the next phase before
the synced hand changes; no raw row/window is removed. Supplemental fixed-input intervals
in position-settling-diagnostic.json show position range **0 units** for yaw **5.6..6.3 s**
(11 rows), pitch **7.9..8.7 s** (13), roll **10.7..11.3 s** (10); maximum linear speeds
**0.000825 / 0 / 0.000825 units/s**. These independently demonstrate stationary settling
without relabelling the original boundary maximum.

Measured steady interval: **44.2329 pairs/s**, **52.0169%** reprojected presents; covered
GPU/SDK sum **16.1275 ms**, elapsed GPU **22.4712 ms**, eye warp **1.65368 ms**, render CPU
**4.96469 ms**, capture transfers **3.30691 ms**. This includes instrumentation/capture,
not quiet performance or worn comfort. No field game was running, so no field quit. SteamVR
stayed running and unchanged. Source snapshots, SDK manifests, counters, timings, raw PNGs,
protected hashes and rollback receipts stay under index-01. K/C combined acceptance remains open.

## Offline and Release gates

**64 passing cases**, **55 LuaJIT + 9 independent Python**, exact suite
companion/tests/vr_tools_test.py through S's existing gate bridge. Independent W stand-in,
real T/input; 200 rigid round trips, wrapped/singular angles, stick at 30/66/90/120 Hz,
inventories to 155/all pages/readable non-overlap, prediction retry/expiry, tap/hold/claims,
mirroring, tracking/death/weapon/entity loss, tool stage/operation/content/paint/bone anchor,
hold receipts, repeated pickup, deferred failure and stopped callbacks. Stand-ins do not
simulate competing native controllers; real settling is from the game measurements.

| Gate | Actual result |
|---|---|
| release-tools-current (5ad6ce0c, pre-Q) | **PASS**, 34/34 CTest, Python 29+26+1175=1230, 4 skips, no failures |
| release-q-integrated | **FAIL**, 34/34 native; one parity fixture reserve error: 15 GiB free versus 20 kept spare |
| release-space-recovered (43ac9002) | **FAIL**, 33/34 native: telemetry interval **25.359 s** versus unchanged 25 s upper bound; Python **29+26+1204=1259** pass, 4 skips |
| telemetry-isolated | Unchanged test **PASS in 10.41 s**; timing cause unestablished, no loader edit or limit relaxation |
| release-quiet | **Cancelled before execution**, owned waiting process only, no child/gate started; foreign lock owner unchanged (release-quiet-cancelled.json) |
| release-final-source (581133d1) | **PASS**, full unchanged tools/test.ps1 -Config Release: **34/34 CTest in 36.66 s**, **29+26+1206=1261 Python cases**, 4 reported skips, 0 failures; main group **131.437 s**, T **64** cases |

The waiting-only quiet gate was cancelled after disk recovery and prolonged shared-queue
waiting. The successful complete ordinary gate above changes no test or limit. Its log and
zero-exit/source receipt are release-final-source.log/json. Only this documentation receipt
changed afterward; T production/private test source remains the tested version.

## Retained failures and operations

native-01: rejected target spawn before W geometry acknowledgement; bounded retry fixes
fixture. native-02/engine-01: baseline/diagnostic, not whole feature acceptance. motion-01:
labelled private trial. native-03: first production package (2283 clean frames). features-01:
wrong numeric stock tool tab id. features-02: stock Think undid one-off filtering; actual
search-field set/restore fixes it. features-03/04: real tools succeed (4902/4793 clean frames)
but the coloured-target picture is insufficient (spawn along upward menu ray). features-05
waits for fresh level authoritative geometry and fixes that picture. Partial receipts remain partial.

Every completed run normal-quits, completes two Start/Exit cycles and restores cleanly.
Latest: **2877 depot files**, no missing/size/hash mismatch; all original trees, data/settings/
registry restored. Protected user.conf before/after SHA-256 remains
743bd25806b9e2b2ebd82f7d39248f05af4ae20e8747d85a59f1a8c7718d4f56.
SteamVR was already running and never quit/reconfigured. No real field game appeared in T's
launches so far; authorised helper ended none. Gate PID 7 messages are mocks, not field actions.

All scratch/build/evidence stays in out. Q's duplicate cleanup verifies path/size/full SHA
before removing copies: **12652934904 logical duplicate bytes**, eight restored runs, every
raw file retained once. Lossless compression verifies full bytes: **2999 files/20415953154
bytes**, then **1479/26679433212**, latest **170/4550406727**; hashes unchanged. Global free
space also includes other workers and is not wholly attributed to T. Superseded generated
GMAs v4t.1/2/3 were removed after hash/completed-rollback checks; dist summaries, header
metadata, committed sources and raw evidence remain (superseded-gma-preflight/cleanup.json).
Current v4t.4 remains. Automatic approval review previously blocked deleting the unused old
runtime and never-launched pre-W GMA: **blocked by policy**. Those exact files remain; no
alternate deletion was attempted, only byte-preserving compression.

Static native research: server.dll **15567184 bytes**, SHA-256
ffff73124bf46add691459a030c3426b940787229d1f3ef9640ce7dfe9bb1f96.
Bounded REA Ghidra launch failed. Ordinary PE/string observations are separately labelled,
not decompilation or proof of writable fields (physgun-research-ledger.json, static fields,
REA logs). No gVRMod code/data copied.

## Open and proposed shared text

Reviewed K is now inbound and B/unfreeze/reload pass in features-integrated-02. The old
Index/component gate records above apply only to their stated sources. C's natural
wrist/palm/tip correction, affected retests and final Index proof wait for Claude's go-ahead;
no Index or C pose adaptation was done this round. Independent production-review findings
are also pending from Claude. Combined/worn acceptance and approval belong to Q/user.

For Q's shared files: add T's five Lua modules and 68-case suite to COMPONENTS/TESTING;
record native input experiments, angular settling and native Use+forward/back in RESEARCH;
add native physgun controls, translated stage-aware hints and paged B-hold wheel to the
branch CHANGELOG/ROADMAP. Preserve K/C/Index/gate limits until actual receipts close them.
T changes no shared document beyond its reserved decision-index rows. K's old pending-B
limitation can now be replaced by the real 50-check integrated simulation result above.
