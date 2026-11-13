# VR V2/V3 task Q: integration and acceptance

**Current Q3c: verify6 passes combined, temporal retry and fresh CPU acceptance.**
See [classified-crash resumption](#q3c-classified-driver-crash-resumption-2026-11-12) and
[resume note](VR-V2V3-Q-resume.md). The retained startup dump identifies the known NVIDIA
nvoglv64.dll+0xe622f8 signature; the one authorized retry passes. Source c20df18d is unchanged.
The final Release/operational result is recorded at the end. C/Index remain open. Earlier
stopped/failed entries are historical, not failures reclassified as passes.

**Historical Q3:** the independent-review simulated result of 2026-11-12 is recorded in
[the follow-up section below](#q3-independent-review-2026-11-12). The original frozen artifact and
older measurements in the intervening sections remain their own historical evidence. C/Index
acceptance is still pending; no Q3 SDK session was run.

Branch `v2q`, 2026-11-11. The combined simulated and Index feature sessions pass, including all modules together and separate full-rate temporal checks. Controlled measurements, both flat batches and both fresh-venv looks are recorded below. Q's assigned implementation/evidence work is complete; this is not blanket milestone acceptance. This is branch-local evidence, not user approval or a release. Natural controller hand/aim alignment is also pending task C, whose brief landed after these scripted-pose tests. The old absolute left-eye ghost guard remains an explicit limitation, not a pass.

## Source and package

Reviewed `vr2` was merged inbound through S, M's follow-up and R's selected runtime import (`61237bfd`), then V4 W (`0e83c0e7`) and C's controller-frame brief (`467d1fc7`). The measured V2/V3 package is frozen before W; W's inbound source is for the later V4 integration, not a claim that this artifact contains or accepts W/K/T. Q never pushed, published, started a workflow or merged into `vr2`/`main`. No `loader/` or field-install file was edited. Own commits use the configured SheepyLord identity and the required Codex trailer.

Normal package: `out/dist/gmod-rtx-remix-0.0.0-v2q.7.gma`, 1,808 files, 2,085,688,063 GMA file bytes (2,085,133,476 payload bytes), GMA SHA-256 `f9b7f8edacba206c59876d3bbb6f8f326304d10deef7c27f965eb7e010d34421`. Manifest digest `01df5f893ed74ea4a456fdb1ccc73ffb06db628dfd7ae8bb45cab698cc01955a`. Built from `packages/`, without built-DLL overrides; receipt is the adjacent dist JSON and `out/vr/v2q/package-7.log`.

- Runtime: 418,403,840 bytes, SHA-256 `027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278`. R's one selected import was already on reviewed `vr2`; Q did not reimport it. `runtime/base.json` has no pending patches.
- Module: 510,464 bytes, SHA-256 `a1628079de069a7a747d506a23ee8f7c957f18f8f7e2283155fd896205fc13b7`. Q uses the shared window API types/flags, M's native input and the bounded 32-overlay cap. `repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll` records clean source `10c38c5cbd0922718f22eb6b2e5deaed340c0b64`. Evidence: `refresh-module-final.log`, `provenance-final-status.log`, `packages/vr/files.json`, `tools/ci/pins.json`.

A second normal source snapshot, `out/dist/gmod-rtx-remix-0.0.0-v2q.post-w.gma`, is built and nlctl-validated from clean commit `a364ec58af7eddbbe37aa78d235dfcb9bdde94b3`: 1810 files, 2085728617 file bytes, SHA-256 `dc99a8a88e8f3adb975e703cdfbe2e944c61fec106e284aedc3b5cff0dbba9af`. It includes inbound W and the legacy damage-API clarification. It is **build/validation only, not V4 headset acceptance**; none of the V2/V3 numbers is transferred to it. Evidence: `source-snapshot-build.json`, `package-post-w.log`, adjacent dist summary. C/K/T integration needs its own later package and acceptance.

Evidence paths below are relative to **this worktree's `out/vr/v2q/`**, unless another worktree is named. Raw images stay in `<run>/captures/<label>/`: centre/left/right PNGs, depth floats, semantic-role overlays and timing records. Desktop mirrors are under `poc/game/shot-*.png`. Labelled QA sheets resize/crop raw images; they never replace them.

## Corrections and evidence tooling

The review regressions cover unresolved solid-start hands hidden for the frame, reused Debug tables in hands/movement/network/interaction/UI, bare punches capped at 25 (held objects 65), session ai_serverragdolls/restoration and calibration's next-Start notice. Three added phrases are generated as UTF-8 for all six catalogs. The actual UI Debug producer is exercised for 100 frames.

Combined sessions exposed further interactions:

- Explicit movement/eye/teleport hull traces collided with the player's own non-colliding physical hands. P now owns client/server BodyTrace exclusions used by L. Own held/pulled/recently released bodies are excluded; unrelated props, world and living NPCs remain solid.
- Fifteen retained movement/physical overlays exhausted cap 16 when menus opened. Cap 32 covers the complete reserved roles plus seven arc dots (up to 26). Native tests cover 32, overflow, replacement and two sessions.
- P's changed-state packets share F's one-per-tick outbound slot with L's follow updates. L now learns a bounded motor-only buffer from recent source cadence/delivery age, resets on mode/generation, never extrapolates or moves its cursor backwards, and samples motor motion at each view lookup. Only room correction is cached. Physical head/room motion stays outside the delay.
- Climbing counted delayed common body translation as another pull. Per-grip hand-minus-head calibration cancels that feedback without an acquisition jump, retaining the server hull sweep. A 12-unit pull remains 12 across delayed updates.
- Both touching hands could toggle one object on then immediately off. They now share the existing 0.3-second per-player/object Use cooldown.

The driver checks declared overlay handle/role/source, including window aspect and extra arc dots, never size/order heuristics. Any isolated module/cleanup error fails acceptance. Private Lua is staged under the snapshotted PoC tree to avoid console limits. After game exit, a guarded same-volume rename retains captures without copying gigabytes while holding the lock. Development-only CPU clocks and net accounting never enter the package. Decisions: [0172](../decisions/0172-vr-combined-acceptance-and-evidence.md), [0173](../decisions/0173-vr-integration-review-fixes.md), [0174](../decisions/0174-vr-measurements-and-flat-controls.md).

## Accepted combined sessions

`combined-sim-08` and `combined-index-02` use the canonical package above. Their 129 active seconds comprise fourteen 4-second physical phases (56 s), H's unchanged 0.2/0.3/0.5 m wrist poses, a 2-second actual finger-bone witness, movement at 0.4 of L's fixture duration and UI at 2.75 times its fixture clock. Distances/turn expectations are explicitly scaled. Throw travel and duration scale together, retaining 120 units/s and 1.1636 rad/s. Full-rate head/motor timing is tested separately. All production modules are loaded together.

| Run | Complete feature result | Rendered / submitted / matched | Submit errors / unmatched / drops | Lua / module errors |
|---|---|---|---|---|
| `combined-sim-08` | PASS, all 14 combined checks | 9315 /0 /9315 | 0 /0 /0 | 0 /0 |
| `combined-index-02` | PASS, all 14 combined checks | 5467 /5467 /5467 | 0 /0 /0 | 0 /0 |
| `combined-sim-12` | PASS, all 15 including both-realm accounting | 9063 /0 /9063 | 0 /0 /0 | 0 /0 |
| `combined-index-07` | PASS, all 15 including both-realm accounting | 5486 /5486 /5486 | 0 /0 /0 | 0 /0 |

Index: 90 Hz, 2468x2740 per eye, centre 3112x2752, primary traced 1556x1376; 11,681 compositor presents and 6,399 reprojected presents over the whole captured session. That includes fixture/capture stalls and is not the quiet performance sample. Simulation loads no OpenVR and makes no SDK submission. Both runs complete two Start/Exit cycles, normal quit, exact compared setting/live-selector restoration and clean rollback. Receipts in each folder: `summary.json`, `combined-acceptance.json`, `movement-acceptance.json`, `interaction-checks.json`, `ui-acceptance.json`, `restoration.json`. Index `physics-qa.png`, `ui-qa.png`, `near-index-comparison.png` were visually inspected.

Final confirmation QA: `combined-index-07/final-qa.png` was inspected; it retains whole virtual fingers/palms at 0.2/0.3/0.5 m, visible background bands and the scripted-pose/C limitation in its label. Final 07 physics records include barrel 13.8407 units /.34602 m, throw vector error 5.15597%, spin 1.16355011 rad/s, plank dot .99827743, heavy lag 24.06176 units /.60154 m, held walking 1.54258 m, bones 5/7, both climbs 12 units and actual 160-units/s NPC hit 25 damage. The earlier 02 per-point figures below remain their own separate measurements.

### Every Done point

Numbers are from `combined-index-02` at 40 units/metre unless specified. All rows also pass combined simulation. Picture paths are under its `captures/`. Raw measurements are engine/probe observations, not assumed fixture outputs. All are scripted virtual-pose checks. C's natural-hold correction must be merged/retested before claiming real controller wrist/ray alignment; see the open issues below.

| Point | Result and measured witness | Picture path |
|---|---|---|
| V2.1 hands/fingers/dominance | Scripted PASS; natural-hold alignment OPEN for C. Citizen player hands, 15 finger bones per hand. Grip false: left curls 1/.8/.6/.4/.2 give actual proximal bends 40/60/45/30/15 degrees; right .2/.4/.6/.8/1 gives-8/30/45/60/75. Off-hand B/menu/laser and movement mirror with dominant 1. H's separate model-change/finger/splay suite remains covered by the gate. | `tracked-curls/{centre,left,right}.png`, `ui-left-wrist/`, `ui-left-spawn/` |
| V2.2 blocked/ghost hand | PASS. Wall shown-target separation 26.1798 units /0.65450 m; ghost remains at controller. Solid-start regression hides unresolved hands even with P's later resolver. | `interact-2/` and its ghost overlay |
| V2.3 movement/turn/room/walls | PASS. Room offset 40 units =1 m. Hand/head walks 161.8153/167.9064 units =4.0454/4.1977 m (160-unit ideal shortened interval). Snap-30 degrees, smooth-45.3149 (target-48 +/-5), mouse-2.2. Pivot error .0007324 units =.0183 mm (<1 cm). Room milestone horizontal head/hull error 0. Wall stop 23.9688 units /.59922 m, backlog 0. Temporal proof below. | `L-wall/`, `L-vignette/` |
| V2.4 comfort/teleport/height/flight | PASS, 36 movement checks. Blink/shift/mantle/zero-vignette blink errors .0270/.0200/.03066/.0270 units (max .767 mm); 20 intermediate shift records, forged slope refused server-side. Stand/duck/seated 64/28/82 units, combined duck 28. Calibration 1.6000000 m ->39.9999994 units/m; later changed calibration sets restart notice. Jump+19.5694 units /.4892 m. Flight 100.000006/300.000017 units/s =2.5/7.5 m/s. Vignette centre alpha 0/border 92, full blink black alpha 255; green/refused-red targets 22,178 coloured pixels each. | `L-arc-green/`, `L-arc-red/`, `L-blink-fade/`, `L-mantle/`, `L-crouch/`, `L-vignette/` |
| V2.5 wrist/spawn/property/window/typing | PASS, all 12 UI checks. Laser barrel-icon spawn; real hand-ray Remove property packet and target deletion after stock's one-game-second delay. Native posted down is guarded by menu-visible immediately beforehand; Resume closes it. Scripted search text through real laser fallback, drag/scroll/settings. Unworn SteamVR keyboard returns RequestFailed 23: no successful physical SDK keyboard claimed. Simulation explicitly emulates its success path then forces failure for fallback. | `ui-{wrist,spawn,context,properties,flat,search,settings}/`; role paths in `ui-acceptance.json`, `ui-qa.png` |
| V2.6 ghosts/near hands | Near hands PASS: measured wrist .2000006/.3000005/.5000001 m, valid world draws; whole palms/fingers in both eyes beside H's V1 crops. Ghost reduction improves matched control, but old absolute left guard OPEN; details below. | `near-{020,030,050}/{centre,left,right}.png`, `near-index-comparison.png` |
| V2.7 Exit/off parity | Two-cycle teardown PASS; fresh flat bounds PASS, earlier cold-start bound FAIL retained. Client global/receiver/timers absent, only pre-existing page ToolMenu hook; server dormant stub only, physics released, SDK unloaded, overlays/VR resources off; no setting/live-selector differences. Source named RT/font caches may live until process exit (M's limitation). Whole-package cost controls are separate below. | `poc/game/shot-flat-after.png`, off/done records, restoration |
| V3.1 physical push/world/NPC | PASS. Barrel moved 13.6636 units /.34159 m, hands stop at wall. Citizen stays ungrabbed, minimum 75 HP before deliberate fixture kill. Contact/haptic receipts retained. | `interact-0/`, `interact-2/`, `interact-10/` |
| V3.2 grab/two hands/heavy/throw | PASS. Four grab receipts; plank alignment dot .99826694. Heavy lag 24.1131 units /.60283 m; held-while-walking travel 1.55554 m. Throw target 120 units/s =3 m/s; native velocity[119.0979, 5.6321, 0], vector error 4.75324% (<20%); spin 1.16345077 rad/s. | `interact-{1,3,4,13}/` |
| V3.3 gloves | PASS. Real target marked, launched arc, grip-held catch all recorded; living NPC ungrabbed. | `gloves/`, `interact-8/`, glove-marker overlay |
| V3.4 ragdolls | PASS. Two distinct nearest physics bones 5/7 held; one NPC server death ragdoll subsequently grabbed. ai_serverragdolls restored at Exit. | `interact-5/`, `interact-10/` |
| V3.5 hand Use/kits | PASS. Button on, door states 0/1/2. Grabs grant native health 50->75, armour 10->25, pistol 20->44. Shared two-hand Use debounce prevents immediate retoggle. | `interact-7/`, `interact-9/`, `interact-11/` |
| V3.6 ledge/ladder | PASS. Each rise 12 units /.30 m; eight ladder-grip receipts, release-both falls. Delayed follow no longer multiplies pull. | `interact-6/`, `interact-11/` |
| V3.7 melee | PASS. Bare/held melons broken, seven held-hit receipts. Citizen remains 75 HP after capped bare hit before fixture kill. Offline actual-damage/cooldown/push tests retain bare 25/held 65 curves. | `interact-9/`, `interact-10/`, `interact-13/` |
| V3.8 haptics/death/Exit | PASS. Five pulse event kinds 1..5, including contact/grab/release. Player death releases objects/proxies with VR active; respawn stays in VR. Exit restores state; second Start/Exit clean. Pulse requests do not prove human actuator feel. | `interact-12/`, off/second-cycle receipts, flat mirror |

### Full-rate temporal proof

`allmotion-sim-04`: full 127 s movement/head/motor PASS, 36 movement checks, 9725 rendered/matched, 0 SDK submissions/errors/unmatched. `allmotion-index-01`: clean 5608 matched submitted pairs, movement/head pass, but <20 accepted samples in short sprint window: **complete acceptance FAIL**. It stays failed. A focused 47 s sequence extends sprint to 2 s, retaining the same >=20 samples and <=10% spread requirements.

`temporal-sim-01` and `temporal-index-01` PASS with every production module loaded. Index: 2089 matched submitted pairs; 0 errors/unmatched/drops, 4276 presents, 2196 reprojections; 0 Lua/module errors, normal quit/rollback. Head ramps .5/1.5 m/s, sway 2 Hz; input/view use the exact same frame sequence.

| Measurement | Full simulated allmotion | Focused Index temporal |
|---|---|---|
| Slow/fast/sway max camera-coordinate error, units | .000305/.000610/.000549 | .000183/.000305/.000244 |
| Head holds while tracking moves | 0/0/0 | 0/0/0 |
| Sway cross-correlation lag | 0 ms | 0 ms |
| Walk/sprint/flight normalized p95-p05 spread | .5768/.4661/1.5123% | .2512/.3343/6.5920% |
| Walk/sprint/flight samples | see motion-analysis.json | 72/72/72 |
| Walk/sprint/flight near-zero steps | 0/0/0 | 0/0/0 |
| Motor mean lag behind latest server origin | 60.98/61.17/58.54 ms | 70.46/70.45/72.29 ms |
| Head/camera roll; command/player/off roll | 25/25; 0/0/0 degrees | 25/25; 0/0/0 degrees |

Spread uses distance divided by that frame's elapsed time; raw displacement spread is retained too (Index 15.23/15.16/24.85%). Motor delay is explicit. Focused simulation has one isolated near-zero walking step despite passing 5.29% percentile spread; it is not described as zero. Same-frame software agreement is not optical tracking-to-display latency or a comfort judgment. Raw `latency-analysis.json`, `motion-analysis.json`, `*-acceptance.json` and full arrays remain in each folder.

### R's selected runtime and open absolute ghost guard

R's original controlled ring metric drops 713/878 extra left/right pixels to 165/187 (~77/79%). The selected per-frame-range runtime retains the far shader body and validated close tile path. Final physical matched merged-context selected early/steady counts 168/187 and 163/178 compare with unchanged fixed controls 170/188 and 172/195. It improves matched controls, but **163 exceeds the old absolute left-eye 153 guard by 10. V2.6 is not an unqualified numeric pass.**

R's physical prop sweep .15/.2/.3/.4 m is whole, width error at most .35/.55/.96/.82%. Preparation+warp 1.249/1.045/1.108/.909 ms, GPU command work 12.359/11.674/11.690/11.621 ms. Normal selected/control prep+warp .869/.853 ms, matched overhead .016 ms. These are R's scene-specific observations, separate from Q's matrix; 80 Hz throughput is unmeasured. See [R's report](VR-V2-R-report.md), `v2r/out/vr/v2r/followup/` and its linked main-checkout run folders.

Q's `near-index-comparison.png` places H's identical poses beside H's V1 `index-04` crops. Whole palms/fingers recover. Horizontal background disocclusion bands remain outside sleeves at .2 m, with fine depth/colour seams. True stereo/hidden surfaces remain V7.

## Quiet performance and CPU/network accounting

Five accepted actual Index runs on the RTX 5090, driver 617.42, with the existing 90 Hz setting. Pre-launch GPU inventory starts at 13%/4412 MiB for the first control, with no field game. Both hands are visible in every map/window image. These are 45-active-second runs, with 25 one-second samples spanning active+10..35 after neutral capture and before the HUD change. Covered profiles number 12..19 per sample; full raw counters are separate from these deltas. Callback profiling is off; a read-only cumulative game-thread clock remains sampled once a second. Each row has zero Submit errors, unmatched poses or drops, zero Lua/module errors and clean restoration.

| Scene / window | Submitted pairs/s | Reprojected presents | Covered command/SDK ms | GPU elapsed span ms | Render CPU ms | Game-thread CPU ms/pair | Samples/profiles |
|---|---:|---:|---:|---:|---:|---:|---:|
| construct-720-03 | 44.999 | 50.00% | 12.844 | 19.978 | 5.208 | 7.113 | 25/18 |
| construct-4k-03 | 45.007 | 50.00% | 12.594 | 19.979 | 1.645 | 7.157 | 25/19 |
| house-720-03 | 29.903 | 66.67% | 19.415 | 27.341 | 7.812 | 15.239 | 25/12 |
| house-4k-03 | 29.933 | 66.91% | 19.262 | 28.078 | 3.906 | 15.646 | 25/12 |
| construct-near-720-03 | 44.997 | 50.00% | 12.814 | 20.026 | 1.645 | 6.927 | 25/19 |

| Covered pass, ms | Construct 720 | Construct 4K | House 720 | House 4K | Construct near 720 |
|---|---:|---:|---:|---:|---:|
| scene_prepare_as | 0.3517 | 0.3508 | 0.5637 | 0.5624 | 0.3523 |
| path_volumetrics | 7.6822 | 7.4108 | 14.0956 | 14.0545 | 7.6091 |
| demodulation | 0.0781 | 0.0411 | 0.0992 | 0.0579 | 0.0854 |
| denoising | 0.0002 | 0.0002 | 0.0002 | 0.0002 | 0.0002 |
| composition | 0.5136 | 0.3879 | 0.3217 | 0.3655 | 0.4177 |
| upscaling | 2.7916 | 2.9542 | 2.5796 | 2.5926 | 2.7778 |
| post_tonemap | 0.3347 | 0.3716 | 0.4061 | 0.2797 | 0.2996 |
| depth_coverage | 0.0376 | 0.0375 | 0.0380 | 0.0377 | 0.0373 |
| eye_warp | 0.9432 | 0.9044 | 1.2419 | 1.1876 | 1.1342 |
| mirror | 0.0200 | 0.0525 | 0.0094 | 0.0230 | 0.0085 |
| capture_transfers | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| steamvr_submit_span | 0.0784 | 0.0471 | 0.0467 | 0.0651 | 0.0787 |
| late_raster | 0.0131 | 0.0364 | 0.0133 | 0.0358 | 0.0132 |
| overlay_transfer_span | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

All steady rows and neutral captures use 2468x2740 eyes,3112x2752 centre and 1556x1376 primary trace at 90 Hz, unchanged between 720p and 4K. Construct mirror+late-raster costs .0331/.0889 ms; House .0227/.0588 ms. Overall command sums differ by -.250/-.153 ms (4K minus 720p) in these one-run comparisons; that is scene/sample variation, not proof that 4K is faster. The expensive path remains headset-sized. At 90 Hz these 12.59..19.42 ms covered sums exceed the 11.11 ms native interval; measured cadence is 45 or 30 pairs/s with reprojection, not native 90 Hz.

The near control's visible cube front is 0.200000 m, centre 0.214766 m (actual mesh vertices, model scale .1); recorded neutral minimum depth is 0.199990845 m. The far minimum is 0.841825866 m. Depth coverage+eye warp means are 0.9808178 ms far and 1.1714728 ms near, delta+0.1906551 ms. This is that pass pair's observed difference, not the total frame-cost delta or a confidence interval. `warp-near-far-qa.png` verifies the small cube in centre/both eyes; `map-window-qa.png` verifies both hands and matched scenes. Four-decimal zeros above mean rounded below .00005 ms, not proven zero work.

Evidence: `performance-matrix-final.json`, `performance-tables-final.md`, each named run's original `measurements.json` and `measurements-reanalysis.json`, `summary.json`, GPU/process inventory, raw profile timestamps and captures. Elapsed GPU spans include queue/pacing gaps and are not added to covered pass sums. Render-thread CPU is the selected per-profile GetThreadTimes bracket; its coarse 15.625-ms quantum and only 12..19 profiles make these sample means noisy. Mean cumulative-context values are 4.223/4.430/9.043/9.611/4.283 ms, retained separately, not quiet-window samples. The original analysis averaged those cumulative means; corrected reanalysis keeps both without changing any raw data or GPU/rate result. cumulative game-thread CPU/pair includes engine/server/client work and is separate from exclusive callback attribution below. No SteamVR setting was changed and no 80 Hz throughput was measured.


The clock helper never ships. CPU attribution subtracts nested registry calls and includes clock/wrapper overhead; Windows GetThreadTimes is quantized. Cycles and SysTime elapsed remain separate. Direct receiver work and engine/unowned work outside the registry callbacks remain unattributed; engine work invoked inside a measured callback is included. This is neither whole-process CPU nor a wall-time estimate. Server callbacks retain their own ticks and elapsed interval.

Final accounting: `combined-index-07`, 5551 distinct game FrameNumber values and 5551 PostRender calls over 129.013118 s; 8430 server ticks over 129.016428 s. These differ from 5486 native rendered/submitted pairs. The simulated confirmation `combined-sim-12` has 9189 distinct/callback frames and 8429 ticks, with 9063 rendered/matched and no SDK submissions. Both complete all 15 combined checks.

| Module | Index client CPU ms/game frame | Index server CPU ms/tick |
|---|---:|---:|
| core | 0.759998 | 0.001853 |
| hud | 0.008444 | no module |
| hands | 0.740295 | no module |
| move | 0.287110 | 0.033363 |
| ui | 0.050667 | no module |
| interact | 0.050667 | 0.224273 |
| weapons | 0.000000 | 0.000000 |
| reload | 0.000000 | 0.000000 |
| tools | 0.000000 | 0.000000 |

Weapons/reload/tools here are the V2/V3 artifact's scaffold entries (zero active callbacks), not the newly inbound V4 implementations. With VR off, both registries/session callbacks are absent; module callback counts are exactly zero. Whole-game flat costs are tested separately, not inferred from that absence. The client wrapper spans the active sequence through its Exit edge (the STOP packet is counted); START precedes the measurement. CPU accounting is quantized and includes observer/clock overhead. The server receiver work outside registry callbacks remains unattributed.

| Direction / type | Count | Engine buffer bytes | Messages/s | Engine bytes/s |
|---|---:|---:|---:|---:|
| client->server 2 | 1 | 4 | 0.007751 | 0.031 |
| client->server 3 | 8430 | 1576410 | 65.342192 | 12218.990 |
| client->server 24 | 8388 | 167760 | 65.016644 | 1300.333 |
| client->server 25 | 5 | 74 | 0.038756 | 0.574 |
| client->server 40 | 8 | 40 | 0.062009 | 0.310 |
| server->client 26 | 5 | 96 | 0.038755 | 0.744 |
| server->client 27 | 492 | 29028 | 3.813471 | 224.995 |
| server->client 41 | 3389 | 195026 | 26.267993 | 1511.638 |

The client interval is 129.013118 s; the server network interval 129.016330 s. Types:3 pose sync,24 movement controls,25 teleport requests,40 interaction options,2 STOP;41 interaction state,27 follow,26 teleport replies. Other observed Lua channels: one 12-byte properties send client->server and one 53-byte Undo_AddUndo send server->client. These are actual observed Lua net sends and net.BytesWritten values in single player, not NIC packets, UDP traffic or total engine user-command/snapshot traffic.

Evidence: cpu-network.json and accounting-acceptance.json in both final confirmation folders, with raw Q-profile/Q-server-profile/Q-server-network/off records in summary.json. The helper SHA-256 and staged client/server paths are retained in inspection-helper.json; no helper is packaged.

## Flat whole-package parity

The first completed ten-game comparison, `flat-parity-02/parity-recovered.json`, **FAILS the total cold-start bound**. Published/candidate median Think frame intervals 8.2668/8.1224 ms (delta -.1444 ms, limit+.41334 ms), screenshots and every strict inventory control pass. Median launch-to-map 23.9/27.3 s gives+3.4 s versus the predeclared+2.39 s limit. Do not call this full flat parity a pass.

The last candidate's original preparation failed installation on the full disk before the game command; its folder/result remain failed. `attempt-selection.json` selects `candidate-5-retry-1`, preserving the exact five published/five candidate actual-game alternation. No launched failed game was replaced. All ten selected games restore cleanly. The only new off-state item is the server's dormant nlvr receiver; the page ToolMenu hook already exists in V1. Hooks/receivers match otherwise. Exact CL timers differ only by the mwbase one-shot retry, which is both present and absent in the published controls; no unexplained timer is accepted.

`startup-stage-analysis.json` records median deployment 16.4878/17.8530 s, activation 97.5364/96.5773 ms, and elapsed after the synchronous bootstrap 7.4521/7.9980 s (derived from rounded launch-to-map, not a warm-start measurement). Deployment has 1569/1602 changed files and 40285/40431 operations. These separate stage medians do not add to the median total. This locates cost; it does not waive the failed total-startup threshold. A fresh unchanged-limit `flat-parity-03` repetition runs after space recovery, with free-space receipts. The fresh `flat-parity-03/parity-final.json` **PASSES every unchanged declared check**: median Think intervals 8.2870/8.2290 ms (delta -.0580 ms, tolerance+.41435 ms), cold start 25.2/24.4 s (delta -.8 s, tolerance+2.52 s). All 5 paired RGB means .483..714 DN are below 1.78709 DN (0..255 channel scale); complete hooks/receivers/exact timer controls pass. The sole new off receiver is the dormant server stub; the variable mwbase retry is observed in published controls too.

| Pair | Published Think ms | Candidate Think ms | Published start s | Candidate start s | RGB mean DN |
|---|---:|---:|---:|---:|---:|
| 1 | 8.8285 | 8.7808 | 24.2 | 33.4 | 0.6162 |
| 2 | 8.3319 | 8.2290 | 45.9 | 25.2 | 0.6974 |
| 3 | 8.1014 | 8.2104 | 24.9 | 24.4 | 0.7136 |
| 4 | 8.2660 | 8.1877 | 30.8 | 23.9 | 0.6536 |
| 5 | 8.2870 | 8.3423 | 25.2 | 23.3 | 0.4830 |

The first full batch remains a failed startup observation, not relabelled by this pass. Cold starts range 23.3..45.9 s in the replication; these are fresh journal/deployment starts, not persistent installed warm launches. No uniform cold-start advantage or exact zero overhead is claimed. Both batches meet the steady frame/image/inventory bounds; cold-start variability remains a review limit. Waiting-only rescheduling of the final pair is recorded in flat-last-pair-reschedule.json; neither game had begun, the original incomplete aggregate/wait log remain, and all 10 actual launched games pass with exact rollback.

## Manual look without Pillow

PASS: `no-pillow-look-01`, a fresh `python -m venv --without-pip` at `no-pillow-look-01-venv`. The child verifies both Pillow and pip absent before running the actual `vr_session.main --look` path; it uses the ordinary `nl_vr_start`. The proof snapshot after five active seconds records 205 rendered/submitted/matched pairs, zero Submit errors/unmatched/drops,444 compositor presents,212 reprojected presents and 90 Hz. Those are that snapshot's counters, not an asserted whole-session total or throughput interval. Native capture retains centre/depth/both eyes/mirror/wrist PNGs without Pillow.

The private fixture issues `nl_vr_demo_done` after seven active seconds, then the ordinary normal quit and verified rollback run. Summary: zero Lua/module/capture problems, exact settings restoration, SDK unloaded. Evidence: `no-pillow-look.json`, `summary.json`, `restoration.json`, `captures/no-pillow-look/` and the retained venv's `pyvenv.cfg`. This proves the real manual command can start/capture/end in the user's package-free Python environment, not that a person wore the headset.

The guard-enabled repeat `no-pillow-look-02` also passes in a second fresh no-pip/no-Pillow venv: its proof snapshot has 193 rendered/submitted/matched pairs, zero errors/unmatched/drops, 445 presents and 200 reprojections at 90 Hz. It completes native capture, normal demo_done/quit, exact restoration and SDK unload under the new transaction marker. These remain snapshot counts, not whole-session totals.

## Failed runs, gate and operational record

No failed receipt is overwritten as success. Historical checkpoint: `report-checkpoint-pre-final.md`. Every run retains raw records/captures, identity, restoration and relevant review notes.

| Evidence | Result and cause |
|---|---|
| `combined-sim-01` | FAIL: V1 runtime, own-body traces, cap 16 stopped UI; P29/30, L26/36. Renderer 12830 frames/0 SDK submits is only a renderer pass. |
| `allmotion-sim-01` | FAIL: 7206 clean rendered frames/36 movement checks, sway 7 rows (<50) during stall. Native gpuMsTotal 480.97 ms differs from sampled ~12 ms covered sum; cause unestablished. |
| `combined-sim-02/03/04/05` | FAIL: compressed capture/UI timing; heavy-grip mode/early Remove witness; two-hand Use retoggle; remaining fixture witness timing. Raw checks retained. |
| `allmotion-sim-02/03` | FAIL: initial motor 215-276% spread/holds; first buffer fix removed holds but view cache left 24-31% spread. Production fixes follow these witnesses. |
| `allmotion-index-01` | FAIL whole acceptance: renderer/movement/head clean, insufficient short sprint sample count; separately accepted focused run above. |
| construct-720 | FAIL whole measurement: 2033 clean pairs but one Lua error from empty server include. Its 45pairs/s/12.831 ms sum is not an accepted matrix result. |
| `flat-parity-01/published-1` | FAIL whole launch: timer.GetTable absent in this build. Now uses real lua_dumptimers_cl/sv after timed sample, retaining raw dumps/exact names/sources and published-control variation. |
| build-after-m.log | One exit_observer_integration failure before the successful isolated Release gate; log retained. No loader source was changed; the intermittent cause is unestablished. |
| Cancelled queue entries | `combined-index-01`, `combined-sim-07`, construct-720-02 cancelled before preparation to reload corrected fixtures/collection. Cancellation receipts identify ownership; no foreign lock removed. |

Superseded local GMAs alone were removed after every referring game restored cleanly; hash/build receipts remain. `superseded-package-cleanup.json`: 12,513,929,357 bytes reclaimed. Final `v2q.7` and main's published control remain. Raw captures are retained once; older duplicate copies were removed only after exact path/size/SHA verification. No Workshop item/user data removed.

The final full `tools/test.ps1 -Config Release` PASSES at source commit b6195e4e:34/34 CTests, Python groups 29+26+1143=1198 tests, with 1/1/7 skips (9 total). W's46-case offline suite is included; K/T remain explicit pending-suite skips. Evidence: release-final.log and release-final-exit.json (exit 0). Earlier release-checkpoint.log is a separate successful older-source gate. release-after-w-failed.log retains the first post-W gate's W melee 32-vs 25 failure; Q restored the helper's legacy two-argument 65-cap curve while actual bare calls still pass false for 25. W's owned files/tests were unchanged. This compatibility adjustment does not alter any measured V2/V3 call, all of which supply the boolean explicitly.

Major Q commits:4937cad (review),4583497 (body traces/overlay budget),56e1df1b and 8ff50edb (motor/climb/view-time sampling),b0349c28 (shared Use cooldown),10c38c5c/d62f3e16 (shared API/module provenance),d67f34f0 (space/transaction/preparation recovery),fffa 40c3 (ragdoll fixture broadphase),b6195e4e (legacy damage API). All own commit identities/trailers are audited in final-audit.json.

Late failures are retained separately: `combined-index-03` renders/matches/submits 5467 pairs with no native/Lua/module errors and passes menus/movement/accounting, but complete acceptance FAILS because the NPC punch was not observed (100 HP). `combined-sim-10` records the longer actual 160-units/s punch for 25 damage (75 HP) and passes its five accounting checks, but FAILS complete acceptance because the later death-ragdoll grab was not observed. After entity/bodies were translated together and woken, both `combined-sim-12` and `combined-index-07` pass the real grab; neither partial result is a whole combined pass. `combined-sim-11` is a disk-reserve refusal before locks/preparation, not a headset/game run.

`combined-index-04` and `flat-parity-02/candidate-5` fail when the evidence disk fills. The latter never launches the game. Incomplete raw files and original logs remain failed; recovered restoration does not make either run pass. Under both shared locks, Q restores the original 04 transaction: all 2877 depot files pass, protected user.conf hashes match, original trees/registry/data/settings are clean. `poc-disk-recovery.json`, protected-recovery-after.json and the failure logs retain this recovery.

A broad cache-removal command was blocked before execution by automatic policy review; no such cache deletion occurred. The safe alternative transparently NTFS-compresses completed capture files with full size/SHA-256 checks before/after:24 folders,7890 files,55,622,167,190 logical bytes, unchanged paths/content. `disk-space-recovery-summary.json` and every ntfs-compression-*.json record this. Standard post-rollback cleanup removes only verified generated copies; every unique failed raw file remains. Free space is checked again after queue waits; an fsynced unfinished marker now prevents a dirty baseline being reused. The persistent marker is removed only after matching verified restoration.

All PoC games take the shared lock and production snapshot/normal console quit/rollback. Physical Index sessions take both locks; simulation never initializes the SDK. Accepted completed runs verify 2877 depot files, unchanged protected user.conf, restored original trees, clean data/settings/registry and no missing/hash-mismatched Steam files. Foreign locks are waited for, never removed. SteamVR was already running and was never quit/reconfigured. No real field game appeared in Q's launch inventories, so the authorized quit_field_game.py did not end one; a mock gate message about PID 7 is a test double, not an actual field action. No gVRMod source/data copied.

The reviewed controller-frame brief [C](VR-V4-C-frames.md) documents why raw-pose tests do not prove natural holds: Index/Touch tip pitch is about 40 degrees from raw forward; wrist/palm location/orientation differ from the raw origin. C will compose SteamVR tip/hand components in the core and correct H/W. It is not implemented or accepted by this V2/V3 artifact; hand/laser/arc/gun alignment and the affected cases must be rerun after C. Do not treat old identity-pose captures as a physical alignment pass.

## Open and first worn checks

Follow-up review work is now in progress in a fresh Q thread. Evidence for this follow-up is under
`out/vr/v2q-review/`; it does not inherit the frozen package's acceptance numbers above.
Decision [0183](../decisions/0183-vr-review-resource-and-physics-corrections.md) supersedes the earlier
overlay retention and `ai_serverragdolls` policy. C is not yet in `vr2` at this checkpoint, so no new
Index run has begun. The final item-by-item follow-up results will be appended here.

The user subsequently requested a stop. The unaccepted implementation and exact continuation
procedure are preserved in [Q's WIP resume note](VR-V2V3-Q-resume.md). Package `v2q.review6` is
build-validated only; this follow-up has no final combined acceptance or passing final Release gate.

Open: natural controller wrist/palm/aim alignment (C), the absolute left-eye ghost guard, the failed first cold-start bound, disocclusion/depth-colour seams, worn comfort/actuator feel, physical SteamVR keyboard success (fallback works), other devices. Named RT/font engine caches can persist until process exit although session hooks/SDK/VR resources are off. No 80/90-native-Hz throughput, multiplayer or true-stereo claim. V4 W is now merged inbound, K/T continue separately, and their combined V4 package acceptance is still open. Q has not edited their implementations/scaffold/settings/protocol ranges; the V2/V3 artifact here predates W.

First wearing the Index, compare the natural controller hold to the virtual wrist/palm and level ray; this is C's pending correction. Then inspect thumbs/fingertips/forearms at .2/.3/.5 m and background edges outside them; walk/turn past a still edge, including a held heavy prop; try ledge/ladder release, ragdoll grab and two-hand Use; wrist/spawn/property panels, native Resume while foreground, fallback typing, calibration/restart, Exit/Start/Exit. Judge comfort/readability/haptic feel. Keep the unworn SDK RequestFailed result distinct from worn testing. Approval/outward-facing actions remain with user/reviewer.

## Q3 independent review (2026-11-12)

The review's simulated work passes on branch `v2q`. This is branch review evidence, not natural
controller-frame, Index, V4 or milestone acceptance. As Claude directed, Q did not merge `vr2`
(`adb14468`, no new VR source) or start an SDK session. C's follow-up remains separate.

### Exact artifact and accepted runs

Package **`out/dist/gmod-rtx-remix-0.0.0-v2q.review7.gma`**: 1,810 files, **2,085,742,149 bytes**,
SHA-256 **`0673c7512dedfa362af9e7cf02a4e8d033ba4f9ab76f4c01d9fef7adf6d835c7`**,
manifest digest `0508fb9e333744d8429cd493696e42be9289e8ef538f4723075b71086e48d041`.
Normal build and `nlctl` validation: `out/vr/v2q-review/package-review7.log` and adjacent dist JSON.
Product source is `06605f3c`; later stationary-control tooling does not enter the package. Native
module/runtime bytes remain those reported above: no runtime patch, cap increase or native import.

All following paths are relative to this worktree's **`out/vr/v2q-review/`**.

| Run | Complete result | Renderer / matched / SDK submitted | Errors and restoration |
|---|---|---|---|
| `combined-sim-07` | **16/16 aggregate, 21/21 independent-review checks PASS** | 11,501 / 11,501 / 0 | 0 Lua/module/Submit/unmatched/drop errors; no missing capture image; clean rollback |
| `temporal-sim-01` | **5/5 PASS**, including both-realm accounting | 3,384 rendered; no SDK submission | clean rollback |
| `cachecpu-sim-02` | **5/5 stationary-control checks PASS** | real renderer/counter/capture gate; no SDK submission | clean rollback; both realms and off state observed |

These are simulated sessions with real GMod physics and the production driver, recorded Index eye
description (90 Hz, 2468x2740), 3112x2752 centre and 1556x1376 traced input. They initialize no SDK;
90 Hz here is the recorded description, not measured compositor throughput. Every run uses the
shared PoC lock, normal console quit, protected-file comparison and rollback. Source/probe/staged
Lua hashes and all native capture timings remain in each evidence directory.

### Each independent-review item

The retained baseline tests in `baseline-reproductions.json` reproduce 15 failures across the review
at `7e6700e1`; delayed climbing already passes there. Later focused reproductions are retained too.
The named offline cases run in the normal repository gate. Values below are **simulated mechanical
results**, with the latest artifact's controller-frame mapping still awaiting C.

| # | State, retained regression and combined witness |
|---|---|
| 1 | **PASS simulated.** `f_review_overlay_budget`, `f_review_overlay_repaint`: native handles exist only while visible/recently hidden; 2 s retirement, LRU eviction and all-visible refusal without module stop. Three reserved arc dots + target. All **21** roles, including V4 placeholders/settings/keyboard/panels/close button, are shown together: native peak **21 <=32**, source-request peak **16**. The runtime counts pending source/window/removal requests between drains, not live images. The native cap stays 32. `review-overlays/`, `Q-review-overlays`, `Q-review-retired`; every visible image exists. Late/recreated static bindings now repaint immediately and in the following frame. |
| 2 | **PASS simulated; natural mapping deferred.** `f_world_velocity`, `review_proxy_walk`, `review_render_hands_current_motor`: authoritative player velocity enters proxy/hold/throw; drawing predicts current tracking with obstruction correction. PostRender compares the shown point to the controller relative to the actual same-sequence camera. Walk/sprint **94/88 samples**, max **0 / 0.00000763 units**, no ghost. Client held bounding-surface maxima **1.0283 / 2.6841 units** (2.57 / 6.71 cm), 73/68 samples; not exact grip-point distance. Server grip-goal transient maximum **10.2946 units / .25737 m** includes acquisition/speed changes. Release hand/player velocity both **399.9998 units/s**; first observed prop **399.7974** (0.051% loss). `review-acceptance.json`, `interaction.json`, `review-walk/`, original held-walk `interact-4/`. |
| 3 | **PASS simulated.** `review_room_pause`, `review_paused_room_client`: oversized cumulative ROOM rebaselines instead of poisoning later messages. Paused 3 m room displacement is discarded; held controllers translate with the HMD in the fixture. Subsequent 1 cm room step moves hull **0.4001 units**; fresh sync and valid hand physics persist. `Q-review-pause`, pause samples, checks `3_*`. |
| 4 | **PASS simulated.** `review_spring_masses`, `review_critical_spring`: mass-normalised backward-Euler critical gains include `kd+kp*dt`. Native GetMass readback equals **.5/1/10/250 kg**. Settling **.285/.285/.405/1.170 s**; peak speed **234.30/234.36/151.55/42.28 units/s**, no growth. Lightest ragdoll bone **7, 1.018656 kg**, settles **.225 s**, peak **11.35 units/s**. Native mass records in `review-acceptance.json`; offline response is also required monotone. |
| 5 | **PASS simulated proxy/interaction safety.** `review_safe_proxy`, `review_teleport_wall`: eye-side spawn and destination sweep. A real **1-unit / 2.5 cm** native collision box proves the entire sweep blocks; a behind-wall candidate otherwise within grab reach is refused. Start, tracking recovery, actual death/respawn and synthetic destination discontinuity all remain on the near side; the discontinuity first puts the proxy beyond the future plane. `review-wall-guard` (4 cases), `review-wall-discontinuity`, `review-wall/`. Real blink/shift wiring is independently exercised in item 7. This does not accept the blocked model's natural wrist/finger appearance; C must retest it. |
| 6 | **PASS simulated.** `review_melee_impulse`, `review_melee_damage_force`: bounded momentum from an 8 kg hand, scaled by recipient mass, applied once; damage does not add a second native-body kick. A **2 m/s** impact gives observed **39.779 units/s** for 1 kg and **1.408** for 250 kg, below the 160-unit bound and far below the former thousands. `review-sample` melee native bodies. |
| 7 | **PASS simulated.** `review_teleport_carry`: held bodies/proxies move with each validated displacement. Real blink travels **120.4848 units**, one displacement, same held entity and zero release. Shift travels the same distance in **10 steps**, max **803.234 units/s >480**, same held entity throughout and zero release; new teleport IDs required. `review-carry-step`, `review-carry-release`, `review-held-blink/`, `review-held-shift/`. |
| 8 | **Already fixed, PASS.** `review_climb_delays` and original `climb_delayed_body`: `56e1df1b`'s hand-minus-head correction retains a **12-unit** pull with **0..3 tick** common-body delay, no acquisition jump/growth. Ordinary combined ledge/ladder checks pass. No replacement fix was needed. |
| 9 | **PASS simulated.** `review_restore_throw`: borrowed spawn/context menus detach before protected close callbacks. The native combined fixture counts one throwing spawn close hook, then reopens the surviving real menu under the world panel after Exit. `Q-review-menu-after-exit`, `expected_caught_errors`; no unrelated UI error is accepted. |
| 10 | **PASS simulated.** `review_follow_stale`: after .3 s the view uses engine position; a fresh receipt resets the stale buffer. The combined fixture intentionally stops the server move module and observes continued camera travel with engine movement. It restores the module and saved cumulative room baseline before CPU control; this is a private fixture action, not a module reload feature. `Q-review-stale`, `review-cpu-health`. |
| 11 | **PASS simulated.** `review_glove_mesh`, `review_glove_two_hands`: cheap filters precede the final mesh query; separate left/right hints avoid cache thrashing; exact grabs still query geometry. Full `A.Target` for **two hands**, controlled **2,000-triangle** native body/hit, 100 iterations: **4.168744 -> .031149 ms/tick** with cache bypassed/enabled. `review-mesh-cost`. This isolates targeting cost, not a shipped model's triangle count or total server time. |
| 12 | **PASS.** `review_ragdoll_setting`: zero writes at Start/Exit for both original values; no archived-player setting change. Help in all six catalogs directs the player to Keep corpses. Dedicated test NPC alone requests a server ragdoll; its body is actually grabbed in full combined acceptance. `review-corpse-setting`, original NPC/ragdoll checks. [0183](../decisions/0183-vr-review-resource-and-physics-corrections.md) supersedes accepted 0173's old policy without rewriting it. |
| 13 | **PASS simulated.** `review_wrist_exit`: UI frame returns after the deferred wrist action synchronously stops the core, avoiding access to cleared Debug.ui. The real wrist button completes first Exit with the deliberately throwing close hook and surviving menu; second Start/Exit and off inventory also pass. |
| 14 | **PASS simulated.** `f_review_refresh_cache`, same-frame motor regression: unchanged calls share resolution; changed FOLLOW/input/late motor feet invalidate. Camera/head/hands share the view-boundary transform. Combined has **6,790 actual passes / 20,897 Refresh calls**, including changing inputs and an intentionally uncached control. The stronger stationary result below uses complete same-block game frames. C's future composition belongs inside this cached pass. |
| 15 | **OPEN for C.** No controller-frame implementation was merged here. Every Index/SDK run and natural hand/aim/laser/teleport/grab acceptance waits until Claude confirms accepted C on `vr2`. These raw virtual-pose results must be repeated with natural holds after that merge. |

### Temporal, CPU and network measurements

`temporal-sim-01`: slow/fast/sway head max error **.0001221/.0003052/.0003663 units**; no frozen
tracking steps. Walk/sprint/flight normalized camera-step spread **3.97439/6.56066/4.11348%**, below
10%; sprint stop overshoot **0**. Camera roll remains >20 degrees while command/player roll is zero.

Use **`cachecpu-sim-02/cachecpu-acceptance.json`** for the before/after CPU comparison. Two six-second
blocks per mode, balanced order, discard 250 ms edges. Adjacent PostRender intervals must stay in
one block, so early CreateMove work is not assigned to the opposite mode. All modules/physical
hands are healthy, weapon is Hands, and both worlds' callbacks/sync/off witnesses pass.

| Control | Whole game frames | Game-thread CPU ms/frame | Cycles/frame | Actual resolver passes/calls |
|---|---:|---:|---:|---:|
| Repeated resolution (cache bypass) | 699 | **7.667203** | 32,843,972.6 | 4,973 / 4,973 |
| Production cache | 708 | **7.437323** | 29,799,925.8 | 710 / 5,016 |

This is about **3.0% less whole-thread CPU** and **7.11 -> 1.00 resolver passes per frame** in this
stationary scene. Windows CPU accounting is quantized; these are package-local measurements, not
a universal FPS improvement. The older alternating-frame estimates are retained but mix work near
PreRender boundaries; they are not used for the comparison. Stationary changed-only server state can
legitimately send zero messages; full combined acceptance separately requires and observes traffic.

Combined callback attribution uses **11,608 distinct game frames / 171.0481 s**, not eye pairs or
raw PostRender count. Client exclusive CPU ms/frame: core **.71745**, hands **.41728**, move **.15883**,
weapons **.09422**, interact **.04442**, UI **.03904**, HUD **.00808**, reload/tools stubs **0**. Core
includes its shared services/painting; these are callback-owner costs, not isolated feature totals.
Raw server clocks retain their own tick/time denominators in `cpu-network.json`.

Observed Lua client sends include sync **65.1279/s**, ROOM **64.8765/s**. The server observes 5,323
physical-state sends, 832 FOLLOW, 7 teleport replies and 6 weapon messages over 171.2042 s. Bytes
are `net.BytesWritten` engine bytes, not NIC traffic, total Source packets or all user commands.
Off-state callbacks/registry are absent; no profiler or private fixture enters the package.

### Failures kept, fixes made and limits

All failed evidence remains failed. `combined-sim-05` exposes first-use/static missing overlay
images, the insufficient BSP witness and the intentionally caught close hook being treated as an
unexpected UI error. `combined-sim-06` confirms the thin wall but attempts its start grab before the
new proxy is in reach; it also misses the NPC death-ragdoll grab in that run and still lacks static
native images. None was relabelled. The completed `07` runs the real death-ragdoll grab successfully.

The static-image failure is a product bug: a logical canvas was painted before a later native bind.
`reproduce-lazy-overlay-image.log` fails at **1 vs 2** callbacks; the retained regression now requires
paint after binding and the next frame. [0184](../decisions/0184-vr-capture-lifetimes-and-review-witnesses.md)
records that correction and evidence controls. The queue waits for painted targets and never treats
a missing visible image as success. Hidden images may disappear during retirement.

`cachecpu-sim-01` completes its game and restores cleanly, then its analysis crashes because an empty
Lua message table is JSON `[]`. The parser now fails the dynamic-message witness safely; stationary
control scopes it explicitly, while the combined check stays strict. Its failed log/exit are retained;
`02` is the fresh complete control pass. No failed receipt was overwritten as success.

Visually inspected `07` left near-.2 m and wall images retain the raw-frame limitations: palms up,
wall occlusion of fingers and visible warp/disocclusion seams. They do not establish C's natural
frame or blocked-hand appearance. Overlay budget/repaint acceptance uses the native visible state
and all role images; simulation does not show SteamVR's physical compositor layers. The older absolute
left-eye ghost guard, cold-start variability, worn comfort, physical keyboard/haptics, other devices
and all V4 integration remain open. No old GPU matrix, flat parity or no-Pillow result is transferred
to review7. No claim of true stereo or native 90-Hz throughput is made.

Q never pushed, published, started a workflow, merged outward or edited `loader/`. All current sessions
are simulated, and none ended a real field game (no field-quit receipt). The final Release gate and
operational handover are recorded with the final commit below.

Final **`tools/test.ps1 -Config Release` PASSES**: 34/34 CTests; Python groups 29 + 26 + 1,171 =
**1,226 cases, 9 skips**. Evidence: `release-final-20261112.log` / exit 0. The earlier resumed gate
also passes separately; later code/tool changes are covered by this final gate. No loader source
was edited. The stationary CPU helper and its empty-table regression are included.

Own superseded GMAs `.7`, `review3`, `review4`, `review5`, `review6` were removed only after all three
review7 runs passed/restored, with actual size/SHA-256 compared to their build sidecars first.
**10,428,652,211 bytes** reclaimed; all build identities, failed logs and raw images remain.
`superseded-packages-final.json` records exact own-worktree paths; review7 and every foreign package
were left intact. This is in addition to the earlier 6,257,208,889-byte cleanup audit.

At final audit no Q driver/game/prepared transaction remains. The shared PoC lock/pending marker
belong to **C, PID 76404**, and were left untouched; VR lock was absent. Ownership can change after
that observation. Q waits for Claude's accepted C handover, not for an SDK run in this round.
The updated [resume note](VR-V2V3-Q-resume.md) leads with the current result and ordered C/V4 work.


## Q3b verification follow-up (2026-11-12)

This section supersedes the Q3 completion claims above for the verification findings. Product
and regression corrections started at `aa7c2d25`, checkpointed at `036d5104`; this round stays
on v2q without C's still-unaccepted controller frames. No Index/SDK acceptance is claimed.
Evidence for this round lives only under `out/vr/v2q-verify/`; earlier review7 measurements
are not transferred to the new artifact.

### Corrections and retained regression evidence

| Finding | Fix and retained test |
|---|---|
| 1. Walking punches / glove flicks | `pose.vel` remains tracking-relative in world axes and game units/s. New `pose.wvel` adds player velocity only for proxy, hold and throw; proxy collision punches subtract body velocity. `test_f_world_velocity`, `verify_walk_not_punch` (still hand versus citizen, then real punch), `verify_walk_not_glove_flick` use actual validated core sync. Core sidecar records the contract. Failures retained in `reproduce-motion-transport.log`. |
| 2. Teleport crosses walls / stretches constraints | `P.Transport` checks held world bounds against the entire path, releases blocked entities on the original side, and releases constrained entities before transport. Free entities/all bones and proxies still carry. `verify_carry_wall`, `verify_carry_constraints`, existing positive carry cases; the combined native guards require real public Grab, obstacle/constraint precondition, Release and zero body displacement. |
| 3. Refused window looks ready and pauses | Window request has pending/ready/refused states; ready requires accepted binding and native visibility. Refusal creates the translated package-update canvas once. GameUI activates only for a visible accepted window. `test_verify_window_refusal`; failure in `reproduce-window.log`. |
| 4. Moving glove mesh cost | Reuse is bounded to 100 ms per hand, with a cached local point following the body's transform, independent of hand displacement. `verify_glove_moving_cost`; failure in `reproduce-glove-walk.log`. Combined comparison runs two walking query points at 200 u/s over a controlled 2,000-triangle native body on real server ticks. |
| 5. Pending overlay appears after cancellation | Hands/interaction hide unwanted objects even before native visibility; Paint retries therefore cannot resurrect them. `verify_pending_marker`, `verify_pending_ghost`; failures in `reproduce-pending-overlays.log`. |
| CalcView / ULib | Core's new `cl_view_hooks.lua` owns ULib's authoritative priority registry and stock dispatch, protects re-entry, preserves late registrations/removals at Exit, and safely refuses unknown detached registries. W's `c99003f5` was read without editing its files. `f_view_ulib`, `f_view_ulib_copy`, `f_view_unknown`, `f_view_reentry`; failures in `reproduce-view.log`. |

### Acceptance criteria

- Heavy lag is again finite and **>3 units**, not merely nonzero. The 250 kg spring is stable
  and slower; the current mass curve uses omega 2.5/s at 250 kg, 24/s at 10 kg and a 40/s
  upper bound. `verify_heavy_moving_lag` reproduces the actual (40,0,16) u/s ramp: former
  gains produce 3.016 units and fail the regression's 3.3-unit margin. Both that ramp and
  the original step/mass-settling regressions remain. Failure: `reproduce-heavy-moving.log`.
- Captures require configured/wanted **logical overlay roles even with no native handle**.
  A configured wrist HUD without a handle fails. Required descriptors remain in inventory;
  images must exist for each expected role. Intentional empty/HUD-off expectations are explicit.
  Test `test_expected_wrist_without_a_handle_cannot_pass_capture`;
  `reproduce-expected-roles.log`. The resource/role requirement is not bypassed by renderer checks.
- Arc paint requires **all four roles and >=256 ring draws**: three dots plus target, each
  64 polygons. The former >500 assumed nine rings before the overlay-budget correction;
  >0 proves too little. The accepted UI window-call count remains one, as Claude allowed.

### combined-sim-02 failures and corrections

The verify1 run exited normally, with zero Lua/module failures and verified clean restoration;
its false receipt remains false. Physical failed only because native heavy lag was **2.94031**
units. The moving-ramp regression and slower mass curve correct that real product behavior.

Movement witnesses were invalidated by synchronous capture I/O consuming the wall-clock script
while Source physics stopped: physical-hold, physical-up and toggle-down all read native time
**76.7530463** after the preceding frame at **74.208996**. The toggle stayed on, reducing review
walking to **60 u/s**, moving the teleport ray origin down and reducing shift speed to
**432.726 u/s**, below the mandatory >480 witness. Hand walk also lost its input window around
its vignette readback (62.91 units instead of 160). The resulting ledge/slope and combined-crouch
failures are fixture timing, not velocity-contract, transport-sweep or overlay cancellation defects.

The simulated functional replay after 64 seconds now follows Source game time for poses/actions
and the Exit deadline. Raw native wall time remains in every TestState receipt, and excluded
capture wall time is recorded. Deliberate menu pauses still advance tracking on wall time, retaining
the three-metre pause/resume test. Full-rate temporal acceptance keeps the unwrapped native clock.
`vr_combined_clock_cases.lua` reproduces the 2.54-second stall without skipping a toggle, checks
analogue schema/interpolation, intentional paused tracking and exact API restoration.

The independent held-walk phase also had **no successful grab**: it spawned a can before delivered
grip/proxy readiness, then measured the can being pushed. Setup now waits for delivered grip and
a fresh proxy within one unit, invokes the public Grab immediately, and requires a successful
`review-carry-setup` receipt for hold, blink and shift. Existing minimum sample, world release,
shift-speed, obstacle and constraint checks all remain; one explicit setup check was added.
The new negative-carry guards and moving mesh benchmark had already passed in failed 02.

### Fresh verification results

verify2 combined-sim-03/04 both restore cleanly and pass all physical, movement and 24 independent-review checks. They remain failed because the real slider drag does not change its cvar. In 04 the stock Think witness reports dragging=true, mouse-down=true, a moving controller UV, but desktop/gui=(0,0) and local cursor=(-530,-324). This is a real background painted-control cursor defect, separate from the three original failures.

A retained offline regression (`verify_background_drag_cursor`, failure in `reproduce-background-drag.log`) now covers desktop polling resetting to zero between controller injection and drag Think. Painted panels route CursorPos only for the active hovered control/ancestor chain through their controller canvas point; they restore prior instance methods and preserve later replacements at Close. No global cursor API or native window route is overridden. This implements the existing VR pointer contract for ordinary Derma controls without relying on desktop foreground focus. The stock slider witness remains observational, and its value-change check remains mandatory.

verify3 combined-sim-05 also exits normally with clean rollback, zero Lua/module errors and no capture problems, but remains failed. The control cursor is now correct (229,19 while desktop/gui remain 0,0), yet stock `DSlider:Think` only checks convars: its value changes in `OnCursorMoved`, and the unfocused native capture was omitting that callback. The router now observes native move delivery on the actual pressed widget and supplies its original callback only for absent moves and changed controller pixels. It never sets the value; an observed native callback is not duplicated. `verify_background_drag_events` fails before and passes after; `reproduce-background-events.log` also retains the added skeleton replay contract failure.

05 also exposes two fixture failures: neutral/snap inherited an initial engine yaw of -1.111880 degrees (snap -31.111880), so first installation now normalizes recorded Space yaw through the public Turn API. Its physical death-ragdoll grip window was skipped by the same capture-clock drift before the former 64-second clock boundary (buttons=0, body surface 27.60 units away). The entire simulated functional timeline now uses Source time, preserving raw native time, analogue/skeleton descriptors, 120 u/s throw translation and 1.16 rad/s angular velocity. The native-wall-clock temporal case is unchanged. Neither failure was bypassed or reclassified as a pass.

Current product artifact is **verify4**, source `5ecca776`: `out/dist/gmod-rtx-remix-0.0.0-v2q.verify4.gma`, 1,811 files, **2,085,751,252 GMA bytes**, SHA-256 `6c2f468fd2a6d9cb2ef622f91747635df2048ad4a87eac44d38371838c9f6412`, digest `98dadae487b0f65f56934f6eec4c4c30c4e499815091c8ca4af6ed4e84ba8376`. Normal package build/nlctl validation passes (`package-verify4.log`); 239 focused offline tests pass (`offline-verify4.log`). This is **not an accepted artifact**.

**Stopped on a new game crash, as instructed; no retry.** After waiting for a foreign PoC lock, `combined-sim-06` launched PID **22984** at 2026-11-12T10:06:38Z and exited with **3221225477 / 0xC0000005 (access violation)** at 10:08:50Z (about 03:08:49 local). The last mark is physical-down / L-crouch, functional time **74.2030948**, native time **74.1636974**. No UI drag phase was reached. No cause or faulting module has been established; do not attribute this to a fixture or product change without crash evidence.

The receipt is failed and incomplete: physical **29/31**, movement **14/20**, aggregate **5/16** before truncation. The server death ragdoll was now grabbed, but **heavy lag is only 2.31079 units**, failing the retained >3 criterion even with the slower gains. Its native response still needs correction/verification once runtime work is explicitly resumed. The offline moving-ramp margin and earlier verify2 native 4.88399 observation do not override this failure. `exit_restored` cannot be observed without a normal VR Exit. Later movement/UI/review/accounting phases and captures are absent, not passing. Earlier 03/04 checks are historical evidence on verify2 and are not transferred to verify4.

Crash evidence is retained in `combined-sim-06/game.log` (structured exit/pid/time), `gameprocess_log.txt`, `poc/game/console.log`, `poc/game/remix-dxvk.log`, `poc/game/modules.json`, the partial captures and all failed acceptance receipts. The driver verified **clean rollback** in `restoration.json`, despite `normal_quit=false`. Its last requested L-crouch native image set is incomplete; nothing was deleted to make a receipt pass.

**Still open:** native heavy-lag criterion; verification of the new background drag callback route; a complete combined pass; fresh native-clock temporal and balanced CPU measurements on the same accepted new artifact; final `tools\test.ps1 -Config Release`; C integration and all Index/SDK acceptance. The last full Release pass is the older `release-checkpoint.log` for aa7c2d25, not this source. No final gate was started after the crash-stop instruction applied. No new native session may be launched until the user/Claude explicitly resumes runtime testing after this crash.

Operational stop audit: no Q driver or game remains; main PoC lock, pending marker and VR lock are absent at the stop check. A foreign Python unittest process was left untouched. SteamVR remains running and unchanged. No field game was present or ended, no loader/native/runtime fork files were changed in this follow-up, and nothing was pushed/merged outward/published or started on GitHub. Superseded verify builds and all failed evidence remain: the newer package has not passed full acceptance, so cleanup is deferred. The concise [resume note](VR-V2V3-Q-resume.md) names the exact commands and the crash-stop gate.


## Q3b resumed verification (2026-11-12)

Claude explicitly resumed runtime testing after the crash. The following supersedes the stopped
status and open heavy-lag/drag/combined items above; older receipts remain failed and unchanged.

### Crash verdict

The one authorized **identical verify4** rerun, `combined-sim-07`, passed L-crouch, exited normally
and restored cleanly. `crash-repeat-check.json` records its identity and result. Application event
1000 for 06 was read with the requested Get-WinEvent filter and retained as `event1000.txt` and
`event1000-fields.json`: record **39159**, **03:08:41.4927268 -07:00**, PID **0x59c8/22984**,
`client.dll` **2026.9.16.0**, exception **c0000005**, offset **0x5744c**. The Remix log has no error;
no dump exists under ADR 0142. The crash **did not reproduce**; its call/cause remains unknown.
No crash-specific fix or exoneration of a suspect change is claimed. The conditional scratch
bisect was not needed. Later 08/09 also exit normally, including the same capture. Any future
same-case repeat still warrants scratch-only isolation; a different crash still stops runtime work.

### Artifact, heavy response and fixture corrections

Current package: `out/dist/gmod-rtx-remix-0.0.0-v2q.verify5.gma`, **1811 files**,
**2,085,751,255 GMA bytes**, SHA-256 `c4edc750996ab47140fc2000f2fd42cb0b155872cea64350d1ac9528e1f2d400`, digest `4dbb56800722ffc1ddef78d665aaceb1bf02750398614e1fc95e72cc28a1a4a0`.
Normal build/nlctl validation: `package-verify5.log`. Product source **2eefde96**; private typing
fixture **46dd2103** adds no package file. No native/runtime rebuild/import, loader change or
incoming merge. All new acceptance uses this artifact; no older-package measurement transfers.

The 250 kg hold now uses **omega 2.5/s**, 10 kg remains 24/s, light bodies cap at 40/s; world
feed-forward and mass-normalized backward-Euler critical damping remain. The stronger offline
ramp requires >3 units for >=.36 s, failing the former response at .303 s. `reproduce-heavy-duration.log`
retains that failure. The old no-clip arena floated 24 units above BSP: its walking-heavy case
now starts one unit above traced flat ground, avoiding a fall during pickup. Every one of the
**36** measured heavy-hold samples is grounded. Native lag is **14.70221 units (~36.76 cm)**;
it remains above the >3-unit bound for at least **1.26 s**. This 14.7-unit measurement is not
directly comparable with the earlier 2.94: phase-4 sampling changed from .25 s to .03 s and
the walking fixture was re-grounded. The newer analyser also requires >=1.0 continuous second
above3 while held, so a one-sample spike cannot pass. The 250 kg static step
settles in **2.295 s**, final error .01235 units, peak speed 18.0623 u/s; all light/mid/heavy and
lightest ragdoll-bone stability checks pass. `captures/interact-4/left.png` was inspected: the
large crate visibly trails the rising hand. Natural grip appearance still waits for C/Index.

07 also exposed delayed room-baseline sampling, a consumed dummy mouse command and a missed
punch window. The functional sampler now follows **simulation ticks** (engine.TickCount times
TickInterval), avoiding predictive client CurTime jumps across capture I/O. The mouse injection
waits for CommandNumber()>0; the original -2.2-degree test remains. 08 then passes physical,
movement and review, but its timed fallback typing produces `brel`; it remains failed. The final
private typing helper holds each key's ray through one press/release and advances only after
the actual field prefix is observed. No retries, SetText, health assignment or relaxed criterion.
The final native field is **barrel**, and slider drag changes **30 -> 47** even with desktop/gui
cursor (0,0). The observer reports a valid controller-local cursor and the original stock callback.

### Complete combined acceptance

`combined-sim-09`: **16/16 aggregate**, physical **31/31**, movement **36/36**, UI **12/12**,
independent review **24/24**. **13,845 rendered/matched**, zero SDK submits, unmatched/dropped
frames, Lua/module failures or capture errors. Normal Exit, menu survival under the deliberate
close-hook exception and clean PoC restoration are verified. New offline cases total **240/240**
in `offline-final.log`; the final Release suite below remains the authoritative full gate.

The 21-role worst case peaks at **21 native handles / 16 pending source requests**, within the
existing 32/16 limits, with every module active. Empty shown-hand error is 0 while walking and
<=.000001 units sprinting, with no ghost outlines. Held-body peak lag is 9.8263 units (a transient,
reported rather than hidden); walking release retains world motion. Shift carry reaches **803.234
u/s**, ten steps and zero drops. Both native obstacle and weld guards establish their precondition,
release, and leave the held body displaced **0 units**. Moving 2,000-triangle targeting at 200 u/s,
two hands and 100 real server ticks measures **2.953568 -> .425757 ms/tick**, with the mesh only
for the filtered candidate and the per-hand 100 ms cache retained. Logical missing-handle role
capture tests, four arc roles / >=256 draws, ULib dispatch/re-entry/restore and pending overlay
cancellation regressions remain unchanged.

### Temporal, CPU, gate and operational completion

`temporal-sim-01` is retained as a failed measurement fixture: the old probes rawset-wrapped
`nlvr.core` in CalcView, which no longer exists under exclusive/ULib ownership, yielding no
rendered-frame rows. The new failing/passing `vr_temporal_probe_cases.lua` uses an opaque
registry, requires actual scene records, no camera registry mutation, one row per frame and
clean observer removal. Both probes now observe engine RenderScene origin/angles; no camera
hook is replaced and numerical thresholds are unchanged. Product/package code is unaffected.

Fresh **temporal-sim-02 passes 5/5**, **3,834 rendered/matched**, normal quit and clean restore.
Head max errors slow/fast/sway are **.0003662 / .0005493 / .0006104 units**; head/camera roll
**25/25 degrees**, command/player roll **0/0**. Camera normalized motor spreads walk/sprint/flight
are **7.60700 / 8.68956 / 7.29902%**, with zero sprint-stop camera overshoot. This control keeps
the native wall-clock timeline and is independent of the functional replay clock.

The latest focused offline run is **241/241**, `offline-final.log`.

Fresh **cachecpu-sim-01 passes 5/5**, normal quit/clean restore, both realms healthy and actual
cache control verified. Balanced whole game-thread intervals (two blocks per mode, edge exclusion)
measure **6.106110 -> 5.884982 CPU ms/frame** uncached/cached, **847 / 839 frames**. Resolver
passes/frame are **6.74262 -> 1.00238** (5,711/847 versus 841/839); cycles/frame
26,571,225.91 -> 24,595,587.37. These are the valid comparison, not the combined fixture's
alternating-frame estimate. Server callbacks, client sync and absent off-state registry are observed.

The final Release gate, verified superseded-build cleanup and operational audit are recorded below.
No Index/SDK run is authorized by this completion.


Final **tools/test.ps1 -Config Release passes**, exit0 (`out/vr/v2q-verify/release-final.log`
and `.exit`): **34/34 CTests**, Python **29 + 26 + 1191**, **9 skips** total; repository checks
and documentation conventions pass. Only report/audit prose changed afterward. No native/source
fix remains outside the accepted artifact and committed source.

After verify5's complete runtime acceptance, four own superseded verify1-4 GMA hashes were
checked against their JSON identities and the files removed: **8,342,996,546 bytes**. Evidence
is `superseded-builds-verify5.json`; raw failed receipts/captures and identities remain. verify5
remains available. No other task's build or failed evidence was removed.

Final audit: all Q sessions/drivers have exited and their rollback receipts are clean; no Q
pending transaction remains. The current main PoC lock and pending marker belong to **C PID49892**,
`v4c/review2/sim-left-02`, with its game running; they were left untouched. VR lock is free at
that check. SteamVR's vrserver/vrcompositor remain running and unchanged. No real field game
was present or ended (PID7/forced messages in the Release log are unit-test doubles). No push,
publication, workflow, outward merge or loader edit occurred. C/Index/natural-hold acceptance
and the previously documented hardware/absolute-ghost limits remain open; the one-off native
crash's call/cause remains unexplained, with its exact client.dll offset retained.


## Q3c second verification follow-up (2026-11-12)

Claude's review of ad7ef35a..92854bd6 accepted the prior item fixes and requested the following
additional corrections. Product/tests are checkpointed as **c20df18d**, with **273 focused offline
tests passing** in `out/vr/v2q-verify/q3c-offline.log`. Fail-before evidence is retained in
`reproduce-q3c.log`; previous pass claims do not transfer to the new package.

| Item | Correction and retained test |
|---|---|
| 1: ULib Exit lifecycle | Restore the held plain CalcView table unconditionally, including empty tables, preserving ULib's Hooks/BackwardsHooks invariant. The faithful library removes before Add, indexes BackwardsHooks unguarded in Remove and ignores monitor returns. `f_view_ulib_lifecycle` and `f_view_stock_lifecycle` cover Start/Exit/second Start plus post-Exit Add/Remove; deferred/monitor tests remain. |
| 2: held walking melee | Held-body PhysicsCollide now subtracts the player's velocity and derives speed from the relative vector. `verify_held_contact_world_velocity` preserves a 40 HP citizen and zero shove under walking, then verifies a genuine relative strike. |
| 3: dispatch integrity/capability | Check validates the private dispatch entry, ULib level-table references and entry function/type. Both library paths receive an authoritative-dispatch/short-circuit probe. `f_view_removed_stock/ulib`, `f_view_ulib_detached_dispatch` and `f_view_ulib_no_shortcircuit` detect removed dispatch, misleading table shape and gamemode leakage. |
| 4: idle native overlay calls | Hide only when visible or wanted, so pending acquisition is canceled once. Pending ghost/marker tests count one hide and no calls in five following idle frames, eliminating repeated native transform/hide work during the grace interval. |
| 5: motion and duration coverage | `verify_bare_contact_world_velocity` exercises the actual collision callback; `review_proxy_walk` now has tracking vel0/world wvel200/400 and checks zero-error feed-forward. Automatic scratch-source mutations separately revert bare subtraction, world Follow and held conversion and require each regression to fail. Heavy analysis now requires >=1.0 continuous actual second above3 while held, with sample gaps <=.30 s; spikes, unobserved gaps and disjoint bursts fail. The prior1.26 s observation motivates a full-second persistence bound with sampling margin. |
| 6: documentation | Current acceptance/physics sidecar specify omega2.5/s at250kg, formula clamp(24/(max(m,1)/10)^.75,2.5,40). The14.7 measurement is explicitly not directly comparable to2.94: phase4 cadence changed .25 -> .03 s on a re-grounded fixture. No accepted decision record was rewritten. |

The new normal/nlctl-validated artifact is **v2q.verify6**, source **c20df18d**, 1,811 files,
**2,085,752,193 GMA bytes**, `out/dist/gmod-rtx-remix-0.0.0-v2q.verify6.gma`
(`package-verify6.log`), SHA-256 `29b362d563202f7d9e054e1e598501987308c21ca5a447334c9428480c166a81`, digest `b58822fc9a354a74c2d08224c20f87edf8f25f6e71b4c72e2bb6d46201ef9244`.

Fresh **combined-sim-10 passes 16/16 aggregate**, physical **32/32** (including duration),
movement **36/36**, UI **12/12**, independent review **24/24**. Native heavy lag is
**14.701903 units**, continuously above3 for **1.21499997 actual seconds**, meeting the new
>=1.0 s bound. **13,799 rendered/matched**, zero SDK submits/unmatched/dropped/Lua/module/
capture errors. Normal quit and clean PoC restoration are verified. These are new-package
measurements, not transferred figures.

**Stopped on a different startup crash, without retry, under the standing crash rule.**
Fresh `temporal-sim-03` starts game PID **11460** at **2026-11-12T11:59:27Z** and exits
**3221225477 / 0xC0000005** at **11:59:50Z** (04:59:50 local), before map load, console
control or probe Lua. `map_loaded=false`, `console_window=false`, `quiet_before_lua=null`,
`early_exit=true`; there are **zero probe records**. This is not the former L-crouch case.
No temporal acceptance is claimed and there was no retry or conditional scratch bisect.

The requested Application/event1000/Get-WinEvent filter was run immediately and again after
collection; **no matching gmod.exe event was available**, so this crash's module/offset are
**unknown**. `temporal-sim-03/event1000.txt` records that negative query rather than borrowing
the previous client.dll offset. Preserve `game.log`, `gameprocess_log.txt`, `poc/game/console.log`,
`poc/game/loader.log`, `poc/game/remix-dxvk.log`, session/modules data and failed reducers.
The driver verified **clean restoration** despite the early process exit. No Lua or module
failure was logged; this does not establish a crash cause or exonerate the package.

The current six fixes pass offline and the new combined acceptance; **temporal and final
Release gate remain open**. No new Release gate was started after the crash-stop instruction
applied. The last complete Release pass remains the prior verify5 source (`release-final.log`,
34/34 CTests, Python29+26+1191), not this c20df18d follow-up. No verify5 CPU result is claimed
for verify6; the second review did not change the resolver-cache algorithm. The omega2.5 and
cadence/re-grounding clarification is documented above and in the physics sidecar.

Stop audit: no Q driver/game or pending transaction remains; both locks and pending marker
were absent at the check. SteamVR vrserver/vrcompositor remain running unchanged. No field game
was ended. No failed evidence or build was deleted in this round; verify5/verify6 are retained
until a newer complete acceptance warrants superseded-build cleanup. No loader edit, native/
runtime rebuild/import, push, publication, workflow or outward merge occurred. Further runtime
tests need explicit post-crash resumption. C/Index acceptance remains gated and open.

The later final stop-audit receipt observes a new **foreign T PID49332** PoC lock/pending marker (`v4t/review-features-04`), with the VR lock free. That session was untouched; no Q transaction remains. See `q3c-stop-audit.json`.


## Q3c classified-driver-crash resumption (2026-11-12)

Claude subsequently classified temporal-sim-03's startup failure from its retained Remix dump:
`out/vr/v2q-verify/temporal-sim-03/poc/game/crash-reports/reports-e946500f-f8a3-4b01-4cd9-5129d81218ab.dmp`.
Q verified it using the installed py -3 minidump parser: **0xC0000005**, fault address
**0x7ffd3d8422f8**, module **nvoglv64.dll+0xe622f8**, reading **0x300060059**.
`exception-signature.json` retains the dump hash, module range/offset, exception and thread ID.
Claude identifies a Remix d3d9.dll startup thread and the exact known intermittent NVIDIA driver
signature, also seen with the published runtime (approximately one launch in13 when another
program uses the GPU). That frequency and classification are Claude's prior evidence, not a new
Q measurement. This is classified as external driver startup failure, not a Q code regression.

Remix's own exception handler retained the dump and handled the exception, explaining the absent
Windows event1000. WER snapshot suppression under ADR0142 does not mean Remix cannot write its
own minidump. The earlier negative event queries and stopped receipt remain unchanged.

New rule/authorization: only a startup dump naming **nvoglv64.dll+0xe622f8** permits **one**
fresh-folder retry; any other crash stops. Claude explicitly requested temporal and CPU checks
on the same verify6 package, then the Release gate. temporal-sim-04 is that one retry for03;
no source/package change or Index/SDK run. Fresh current-artifact CPU control is cachecpu-sim-02.
Results and gate will be recorded below; no verify5 measurement transfers to verify6.


The authorized same-package retry **temporal-sim-04 passes5/5**, normal quit and clean PoC
restoration. **3,916 rendered/matched**; maximum head-position error **.0006103516 units**;
head/camera roll25/25 degrees and command/player0/0. Camera motor normalized spreads
walk/sprint/flight **4.42891 / 6.57953 / 8.82669%**, zero camera sprint-stop overshoot.
The native-wall temporal timeline is unchanged; no source fix/rebuild was needed for this retry.
Fresh verify6 CPU02 and the final Release gate remain pending at this checkpoint.


Fresh verify6 **cachecpu-sim-02 passes5/5**, normal quit and clean restore, healthy modules and
actual cache control. Balanced whole-thread intervals measure **6.253756 -> 5.438021 CPU
ms/frame** uncached/cached, **832 / 839 frames**, **5636 / 841 resolver passes** (6.77404 ->
1.00238 passes/frame). Cycles/frame **26,539,779.05 -> 23,934,274.14**. This is a new measurement
on verify6, not a verify5 transfer. Both realms' callbacks, sync and off-state absence are checked.
The final Release gate and operational audit follow below.


**Current final Release gate passes**, `tools/test.ps1 -Config Release`, exit0:
`out/vr/v2q-verify/q3c-release-final.log` and `.exit`, **34/34 CTests**, Python **29 + 26 + 1201**,
**9 skips** total. Repository conventions and all required checks pass. No code/source/package
changed after c20df18d; only this reporting prose changed after the gate.

Own superseded verify5 GMA was SHA-256 checked against its retained JSON identity, then removed
after verify6 complete runtime acceptance: **2,085,751,255 bytes**. `superseded-build-verify5.json`
retains proof. verify6, all failed receipts and the classified Remix minidump remain. No other
worker's build or failed evidence was touched.

Final audit: Q's combined10/temporal04/CPU02 drivers and games exited normally, all restoration
receipts clean, no Q prep remains. The current foreign **T PID36008** owns the PoC lock/pending
marker (`v4t/review-features-05`) and its game is active; untouched. VR lock is free at this
check. SteamVR vrserver/vrcompositor remain running unchanged. No field game was present/ended;
any PID7/forced text in the gate log is a unit-test double. No push/publication/workflow/outward
merge, native rebuild/import or loader edit occurred. Q3c's requested simulated verification is
complete. C integration, natural-hold/Index/SDK and previously documented hardware limits remain
open; future crashes follow the exact-signature one-retry rule above.
