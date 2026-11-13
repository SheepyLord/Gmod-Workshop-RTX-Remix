# VR V2 task H: hands

Implementation on `v2h`, from F's `vr2` framework at `1a11de5`. Task N was merged into this
branch from accepted `vr2` commit `366897d` (merge `6e18789`); subsequent feature runs use its
native simulated backend and skeletal timeline. No push, merge into main/vr2, publication,
GitHub workflow, loader change or native-binary import was made by H. Incoming N provenance
and package-input changes are its accepted merge, not H edits.

H is implemented and validated for integration/review. The renderer witness is implementation `f2c94de`, local package
`0.0.0-v2h.6`, with probe readiness correction `95d740f`. Final source also includes the
resolver-vector ownership guard `7defae5`: it copies the same coordinates instead of aliasing
controller/head vectors. Its in-place-edit regressions pass offline; it changes no pose values,
draws, SDK calls or image maths. The witness package is retained unchanged for provenance.

## What is built

- Two opaque client-side world models, selected through the local player's translated hands,
  with its registered skin/bodygroups. Changes are checked every 250 ms. Physical left/right
  never swap when dominant input roles change. A missing model/wrist falls back to citizen hands.
  SetupBones initializes the engine's bone-name cache before discovery; client creation and
  wrist discovery validate a model without requiring a server precache.
- Named ValveBiped/Bip01 wrists, forearms and fifteen finger joints, tolerating missing joints,
  case and name punctuation. Each copy retains one forearm/hand hierarchy; every other valid
  bone collapses at that forearm's elbow with finite zero scale. No upper arm or opposite arm
  remains. Invalid bone names are excluded. Bone matrices are read before any are replaced;
  the final shown wrist and the session's units/metre determine placement and scale.
- Five tracked curls and optional four-value splay, with a 35 ms exponential smoothing constant
  advanced once per engine frame. Grip curls override tracking and close spread. Thumb joints
  use pitch (40/50/55 degrees maximum), other fingers yaw (75/95/70); spread affects proximal
  joints. Finger yaw shares a basis; thumb opposition mirrors by hand, with a shared wrist basis.
- Opaque geometry drawn in `PreDrawTranslucentRenderables`, skipping depth/skybox calls, with
  normal world lighting, shadows and reflections. The usual opaque callback was not dispatched
  in this RTX path. No model draw uses a canvas, HUD, view-model pass, halo, nested RenderView
  or GetRenderMesh entity.
- Priority-10 brush collision fallback: a 3.5 cm palm hull from the head to a shoulder 18 cm
  down/to that side, then a conservative hand envelope to the controller. The envelope extends
  14.5 cm forward (18 cm including the palm), with 5 mm skin. A solid start tries a clear point
  25 cm back; unresolved solid starts hold at the head. Only shown position/blocked change.
  P's later resolver remains authoritative; controller targets and rays are untouched.
- Lazy ghost overlays: original static open-hand outlines, 265x267 left / 269x271 right,
  0.16 m wide, alpha 0.24, facing the head at the true target. Each canvas paints once. Ghosts
  show only for valid blocked hands with `nl_vr_ghost_hands=1`. Hiding ghosts keeps collision.
  Exit and isolated module failure destroy overlays and both models; H installs no timer/net.
- Plain `NLVR.Debug.hands.left/right`: model/fallback, retained/finger bones, applied curls/splay,
  grip override, shown-target distance, validity/block/ghost state, and paint/build/draw counts.

The design and measured implementation adjustments are in
[ADR 0164](../decisions/0164-vr-hands-fingers-and-ghosts.md). Only H's modules/helpers, H-prefixed
tests/fixtures, this report and its assigned decision/index line differ from the merged `vr2`.

## Offline tests and Release gate

Evidence root is this worktree's **`out/vr/v2h/`**, local and git-ignored.

- **21 LuaJIT hands scenarios pass**, `offline-hands-5.log`: skeleton discovery/aliases,
  missing/invalid/index-zero bones, curls/axes/splay, time-step-independent smoothing, grip
  override and scalar bounds, wall/finger-envelope/shoulder/solid casts, ghost visibility and
  one-time painting, model/skin/body replacement including unprecached client models, fallback,
  world/depth/skybox behavior, wrist/scaling/collapsed/stable matrices, dominant roles, tracking
  loss, isolated draw-failure cleanup and Exit. Stand-ins use F's independent Euler maths and
  actual resource registry, with H's skeleton, matrix and analytic trace stand-ins.
- The original **80 VR page/framework scenarios pass** on final source, `offline-framework-final.log`.
- The first Release gate passed before N's merge, `release-1.log`: **34 CTests**, Python groups
  **29 + 26 + 902 = 957 cases**, zero failures, five existing skips.
- Post-N Release gate passes in `release-2.log`: **34 CTests**, Python groups
  **29 + 26 + 909 = 964 cases**, zero failures and five existing skips. The final thumb
  correction passes all 21 hands cases in `offline-hands-final.log`.
- **Final `tools/test.ps1 -Config Release` passes**, `release-final-current.log`: **34/34 CTests**,
  **964 Python cases**, zero failures and five existing skips. The 21 H cases and 80 framework
  cases also pass explicitly after the independent-vector guard. Earlier complete passes remain in
  `release-final.log` and `release-handover.log` (34/34 CTests, 964 Python cases, five existing skips).

The H cases run explicitly because the task's allowed test filenames have the `vr_hands` prefix;
the tools-only gate does not discover that pattern. Neither suite is presented as a substitute
for the real renderer/SDK receipts below.

## PoC evidence and rejected runs

Every game used the standard driver snapshot/install/normal-quit/rollback path and the shared
PoC lock; only Index acceptance also takes the VR lock. Each scripted active interval is 85 s.
Game startup, bounded console transport, captures, flat phases and rollback are additional.
No foreign lock was removed. SteamVR was already running and is left running; its settings
and processes were never changed. **H ended no field game and did not use the authorised
`quit_field_game.py` helper.** Only H's own PoC games were quit. No user.conf was written.

`companion/tests/vr_hands_poc.py` adds H's native timeline/fixture and bounded capture/debug
receipts to the production driver. Its acceptance requires actual model/finger draws, individual
curls, measured near distances, a stopped hand plus ghost, ghost-off behavior, mirrored input,
a changed model and zero live hand models after Exit. Native image existence/pixels, settings,
SDK state, pose matching and counters remain the production driver's checks. Scripted hands
are tilted up 35 degrees so fingers remain visible above the forearms in the acceptance view.

| Run | Result and reason |
|---|---|
| `index-01-driver.log` | Cancelled while waiting for the VR lock, before any PoC preparation, when N reached vr2. It is not headset evidence. |
| `sim-01` | Rejected. Zero hand bones/draws; initial discovery preceded the engine's name cache. A live supplementary probe records citizen count 43 / left wrist 4 after SetupBones (`NL_HAND_BONES`). 6450 rendered/matched frames, zero submissions/errors/unmatched, normal quit and clean rollback; one near capture was overwritten by V1's simultaneous turn capture. |
| `sim-02` | Rejected. Models now have 19 retained / 15 finger bones, but the opaque callback gives zero draws. A labelled supplementary world-stage probe produces 74 draws/builds in one second and `world-diagnostic` images. It is diagnostic evidence only. H's checker rejects the incomplete ordinary run. |
| `sim-03` | Renderer acceptance passes, H acceptance rejects the unchanged hands after a real player-model change. Client IsValidModel had returned false for unprecached Combine arms. All fifteen capture sets exist; fingers move, ghost toggles and mapping mirrors. The palm-only cast allows the middle fingertip joint 4.41 units / 11 cm into the wall; the final envelope fixes this. |
| `sim-04` | All scripted H/renderer checks pass, 6106 matched/rendered frames, but image review catches outward right-thumb opposition. It is a complete renderer/reference witness; the final candidate corrects that thumb. |
| `index-02-driver.log` | Cancelled while still waiting for the VR lock to avoid accepting the pre-correction thumb. No PoC preparation. |
| `sim-05` | Final candidate passes both production and H acceptance: 6195 rendered/matched frames, zero submissions/errors/unmatched, SDK absent; fifteen complete capture sets, correct actual thumb opposition, model replacement and zero live models after Exit. Normal quit/rollback, 176 s launch-to-exit. |
| `index-03` | 3781 matched/rendered/submitted pairs, zero Submit errors/unmatched/dropped; all H feature checks and fifteen captures pass. Overall acceptance rejects two fixture-only nil TestState accesses during asynchronous SDK Start, one per cycle. The fixture now waits for readiness; production hands/GMA are unchanged. |
| `index-04` | Final clean Index acceptance: 3708 rendered/submitted/matched pairs; zero Submit errors, unmatched poses, dropped frames or Lua errors. All H checks and fifteen capture sets pass; both Exit cycles clean, normal quit and verified rollback. |

All rejected runs retain their logs, summaries, images, protected hashes and verified restoration.
The added bone/world probes are under `out/vr/v2h/inspect_bones.py` and `inspect_world.py`, with
their console witnesses inside those rejected runs. No diagnostic hook or function wrapper is
part of the shipped module. The final runs use the production module without those probes.

## Final captures, counters and measured limits

Final simulated evidence: `sim-05/summary.json`, `hands-acceptance.json`, `sources.json`,
`restoration.json`, `protected-before.json`, `protected-after.json` and `poc/game/console.log`.
`final-receipt.json` collects the final runs' measurements and file/hash checks without replacing
those original receipts. No legacy input shim is used: N's native timeline supplies all poses,
curls and splay. Both thumbs are checked on the actual manipulated proximal bone (+40/-40 degrees)
and visually inspected (`sim-05-thumb-qa.png`).

Each final run's `captures/` retains these fifteen sets, each with centre/depth/left/right/mirror,
overlay PNGs and timings: `neutral`, `thumb`, `index`, `middle`, `ring`, `pinky`, `fist`,
`near-020`, `near-030`, `near-050`, `hud-changed`, `wall`, `ghost-disabled`, `dominant-left`,
`model-changed`. Key evidence:

| Item | Paths below the final run's captures/ |
|---|---|
| World hands and model/material change | `neutral/centre.png`, `neutral/centre_depth.png`, `model-changed/centre.png` (citizen blue sleeves become Combine armour/gloves) |
| Individual fingers and fist | `{thumb,index,middle,ring,pinky,fist}/centre.png`, with both eye PNGs beside each |
| Wall stop and controller outline | `wall/centre.png`, `wall/left.png`, `wall/right.png`, and the 269x271 ghost `wall/overlay_*.png` |
| Ghost switch | `ghost-disabled/centre.png` plus the hand/overlay visibility receipt; the retained static canvas is deliberately unchanged |
| Dominant roles | `dominant-left/centre.png` and the record's `dominant=left`, physical left/right shown positions |
| Near-eye limits | `{near-020,near-030,near-050}/{centre,left,right}.png` |
| Desktop 2D separation | `neutral/mirror.png` versus `neutral/left.png`; the desktop marker is outside the eye, and the models are already in the traced centre/depth |

Simulated checks measure each wrist at 0.200/0.300/0.500 m, within 0.005 m tolerance, with
zero shown-target displacement when unobstructed. Both model variants retain **19 bones / 15
finger joints per hand**. At the wall the right shown-target displacement is **24.6853 units /
0.6171 m**; the sampled finger joints remain **at least 2.5739 units / 6.43 cm outside** the
plane, against 11 cm inside in the rejected palm-only test. The right ghost paints **once**;
its PNG has **2861 visible / 349 bright pixels**, and it hides when the setting is off.
The ordinary wrist canvas stays 769x257 with **6962 bright glyph pixels** at the wall capture.
The left unblocked hand allocates no ghost.

The final simulated run creates **six models** (two citizen, two replacement Combine, two in
the second VR cycle), and leaves **zero live**. Both Exit cycles leave no NLVR global, session
hook/timer or client receiver; only `PopulateToolMenu:nativeloader_vr` remains. All **30**
compared variable strings and live selectors restore with **zero differences**. Original
protected user.conf hashes match; rollback verifies **2877 depot files**, zero missing/size/hash
mismatches, and zero data/settings/registry differences.

Simulation renders at the recorded Index's **2468x2740 per eye**, centre **3072x2752**, traced
**1536x1376**, 1280x720 desktop, 40 units/metre, mat_queue_mode 2. Steady rendered throughput is
**72.7711 FPS**, GPU command work **14.8295 ms**, render-thread CPU **3.6993 ms**. This is a
short feature/capture receipt, with shared-host work, rather than a controlled performance
benchmark; no compositor exists in this mode. GPU/process inventories are saved with each run.

The package still carries the V1 runtime's near warp limit. The traced centre has whole hands
at all three wrist distances. At **0.2 m**, both eyes have conspicuous missing finger/forearm
strips and repeated edges; at **0.3 m** the palms/fingers remain recognizable but inner forearm
edges have gaps; at **0.5 m** the hand silhouettes are whole in the saved eyes. The final Index
comparison in `index-04-near-eyes-qa.png` records this explicitly; the final simulated run's
raw near images retain the same test. These are R/Q's runtime
limits, not a claim that the 0.2 m stereo acceptance is complete. The UI outline remains a
separate overlay, absent from the traced world and desktop 2D.

The Index is a real **90 Hz** SDK session: **3708 / 3708 / 3708 rendered/submitted/matched pairs**,
**0 Submit errors / 0 unmatched poses / 0 dropped frames**, **0 Lua errors**. Steady accepted
throughput is **43.5175 pairs/s**, **53.0108% reprojected** over the sampled presents. GPU command
and SDK work averages **16.3479 ms**, measured GPU elapsed span **21.9568 ms**, eye warp
**0.9263 ms**, render-thread CPU **4.7010 ms**. Capture transfers average **1.9839 ms** in the
sampled profiles, so this is feature evidence rather than a tuning result. Per eye is **2468x2740**,
centre **3080x2752**, traced **1540x1376**, desktop 1280x720. The one in-run flat phase averages
**10.6329 ms before / 8.6727 ms after**; caching, the deliberate model change and shared load
prevent a controlled parity/speedup claim. H's off-state inventory is empty as described above.

The real SDK reports the ghost visible, texture/transform errors **0**, **269x271**, width
**0.160 m**, alpha **0.240**. Its canvas is byte-identical to simulation (SHA-256
`7ef79198649fa26ef3b69555f4e67a4faeb3641f8cdfd67417c230ace3adf6bf`), painted once, separate from
the traced eyes/mirror. Six models are created/zero remain; all 30 variables and live selectors
restore. Index rollback again verifies all 2877 depot files with zero differences and unchanged
protected hashes. Both SteamVR processes remain running with their original PIDs.

`index-04-qa.png` collects the inspected open hands, opposing thumbs, fist, wall stop, Combine
replacement and desktop mirror; raw images remain under `index-04/captures/`. QA sheets are
labelled crops/resizes, not substituted raw evidence. The probe controller lasts **106.0242 s**
including the 85 s active interval, flat phases and two native Start/Exit cycles. The recorded
launch-to-driver-finish span is **181 s**, including map startup and shutdown/settings work;
simulation's corresponding span is **176 s**. No manual/extended headset look was run.

After all rollbacks verified clean, `owned-cleanup.json` records removal of **21334546360 bytes**
of H-owned bulk copies: native capture duplicates only after every file's size/SHA-256 matched
the retained `captures/` collection, and superseded GMAs v2h.1 through v2h.5 after hash checks.
All original receipts/logs, images, timelines, package JSON inventories and witness v2h.6 remain.

## Reproduction and candidate identity

```powershell
python -m unittest discover -s companion/tests -p vr_hands_test.py -v
python -m unittest discover -s companion/tests -p test_vr.py -q
python tools/build_package.py --version 0.0.0-v2h.review --require-nlctl --json
py -3 companion/tests/vr_hands_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v2h.review.gma --evidence out/vr/v2h/next-sim --simulate
py -3 companion/tests/vr_hands_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v2h.review.gma --evidence out/vr/v2h/next-index
tools\test.ps1 -Config Release
```

The unattended driver uses the installed Python 3.12 (`py -3`) with Pillow. Miniconda's `python`
runs builds and offline/Release checks. No Python package was installed. Archived witness v2h.6 has
**1792 files / 2085449434 bytes**, SHA-256
**`1d214ff297b32c8786faa149cbbe46d619fe54818f99f4ccc14b3325bb9fae4f`**.
Its JSON/log remain in `out/dist/` and `out/vr/v2h/package-6.log`. The accepted N module is
the merged, recorded **499712-byte** DLL, SHA-256
`980ba98f80e371ff04c2f63af121f0e28d5462e0f1905f1baf5e7d10d5d7d8eb`.
No new runtime was imported by H; Q owns that single import at integration.
The runtime carried by this package is **418358272 bytes**, SHA-256
`e43aef99a74d333fa75cbb27f8848ae7ba25ce4e8e200f5c7d0f936a69382046`.
The commands use a new review version so rebuilding final source does not overwrite that witness.

## Open work for integration

- R's near-depth/warp changes need acceptance with Q's imported runtime. H records the package's
  current eyes at all three requested distances; a lit centre hand alone does not establish
  whole near hands in both warped eyes. True stereo remains V7.
- Combine H with P's later server-proxy resolver and held-object grip poses. H verifies the grip
  override offline; actual grabs and authoritative contacts are P's task. Preserve the target
  ray and let the later resolver set final shown/blocked state before overlay painting. Preserve
  adequate finger reach in the physical proxy/world stop so a palm-only proxy does not reintroduce
  the measured penetration. No F core change is needed by H.
- The unresolved-start-in-solid fallback is conservative; L owns keeping the head outside walls.
  Non-ValveBiped rigs fall back if no wrist is discoverable, and missing phalanges stay unposed.
- Tests use the unworn Index and scripted controllers. A person's comfort/alignment judgment
  and the milestone's independent review/approval remain outside unattended acceptance.

## Additive text for Q's shared documents

- CHANGELOG: VR hands use the player model's c_arms as lit world geometry, with smoothed tracked
  fingers, held grip poses, client wall stops and faint ghost overlays at blocked controllers.
  Dominant-hand mapping leaves physical left/right models intact; Exit removes session resources.
- COMPONENTS: `modules/cl_hands.lua` owns client models, draw/cleanup and ghost overlays;
  `cl_hands_pose.lua` owns discovery, finger maths and the world collision fallback. H-prefixed
  companion tests provide 21 offline cases and a production-driver PoC fixture.
- ROADMAP: H is implemented and tested on v2h for V2/V3 integration; user approval/main merge
  and integration with authoritative P hands remain separate.
- TESTING: run the H-prefixed suite explicitly; require real model/finger draw receipts, all near
  and wall captures, ghost setting/mirroring/model change, clean Exit, a simulated run and an
  Index run. Retain rejected witnesses and record the runtime binary used for near-eye claims.
- RESEARCH: initialize SetupBones before c_arms name lookup; citizen has 43 bones and a
  discoverable left wrist at index 4, 19 retained / 15 finger joints per H copy. This RTX path's
  world hand draws reach tracing through PreDrawTranslucentRenderables. Client IsValidModel can
  be false solely because the server did not precache a local model; use client creation/wrists.
  A palm-only hull let an open finger joint 11 cm into a brush; include forward finger reach.
  Source pointers: `vr/addon/lua/nlvr/modules/cl_hands.lua:12` (client model validation), `:59`
  (bone initialization), `:142` (world draw); `cl_hands_pose.lua:42` (smoothing), `:54` (finger
  axes), `:70` (swept fallback). Retain the near-eye comparisons and the runtime SHA-256.
