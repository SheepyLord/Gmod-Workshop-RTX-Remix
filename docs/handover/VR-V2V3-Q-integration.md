# VR-V2V3-Q: integration and acceptance of V2 and V3

Read [VR-V2V3-plan.md](VR-V2V3-plan.md) first, all of it, then every task's report in `docs/handover/`
(`VR-V2-F-report.md`, `VR-V2-N-report.md`, `VR-V2-R-report.md`, `VR-V2-H-report.md`, `VR-V2-L-report.md`,
`VR-V2-M-report.md`, `VR-V3-P-report.md`, with their "Follow-up" sections) and [VR-V4-plan.md](VR-V4-plan.md),
whose integration you will also do later (this thread continues as V4's task Q).

Your branch is `v2q`, worktree `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v2q`, from `vr2` after
Claude merged tasks F, N, H, L (with two follow-ups), M and P. Three pieces are still landing on `vr2` while you
start: R's follow-up (a per-frame near limit, the module's provenance, **the runtime import**), M's follow-up (a
native window-input function so the flat panel's escape menu works, a fallback keyboard) and V4's scaffold S
(module lists, protocol ranges, overlay sizes, settings, the gate's bridges for the feature suites, and two core
fixes: the head's roll out of the user command, movement rebased under `NLVR.Aim`). Check `git log vr2` from time
to time and merge `vr2` into `v2q` when one lands (that direction is allowed). Do the work below in an order that
does not wait on them: the combined scenarios and the review fixes first, the measurements and the Index acceptance
once R's runtime is on `vr2`.

## What to do

1. **Claude's review fixes** (each with a test):
   - H: when the shoulder or hand cast starts in solid, `Pose.Resolve` puts the shown hand at the head, so the
     model is drawn at the eye. Hide that hand for the frame (or keep its last good shown position).
   - H: `core.Debug.hands` and its tables are rebuilt every frame with no probe attached; build them only when
     read (or reuse the tables). Check the other modules' Debug values the same way.
   - P: a bare punch reaches 65 damage at 6.5 m/s (one punch kills a citizen). Bare hands cap at 25 (a crowbar's
     hit); held objects keep P's curve up to 65. Record the change in a decision record of yours.
   - P turns `ai_serverragdolls` on for the session (NPC death ragdolls grabbable) and restores it at Exit; L's
     calibration needs another Start (the module's scale is latched at Start). The page's VR help says both, and
     the wrist menu or the page shows the restart notice when `calibrated.restart` is true.
   - The session driver's overlay checks validate overlays by role (wrist, panel, window, keyboard, markers), not
     by size or by "the first big image is the wrist" (R's and M's runs both had to work around it).
   - Once M's and R's follow-ups are on `vr2`: switch the module from N's private declarations of R's exports to
     the shared header (`vr/native/include/rtxvr_api.h`), then refresh the module's provenance
     (`python tools/ci/repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll`).
2. **One combined acceptance** through the production driver (`tools/vr_session.py` with timelines and probe checks;
   the tasks' own fixtures show how): every point of "Done for V2" and "Done for V3" in the plan, each a scripted
   phase with measured numbers (distances in units and metres, angles, counts, velocities), captures of the eyes,
   centre, overlays and mirror, in a simulated session and on the Index (both locks). All modules together, not one
   task at a time: hands, movement, menus and physics in one session, so their claims, resolvers and movers meet.
   Include L's latency measurement (sideways head motion at 0.5 and 1.5 m/s, a 2 Hz sway: same-frame) and L's
   locomotion smoothness (stick, sprint, flight: step spread within 10 %), H's near-eye cases (hands at 0.2, 0.3 and
   0.5 m: whole in both eyes with R's runtime, crops beside H's V1-runtime crops), the wrist menu, a spawn by laser,
   a property by hand ray, the flat panel's Resume by click, typing, a grab, a two-hand hold, a throw, gloves, a
   ragdoll, a door, a kit, a ledge climb, a ladder, a punch, a death and respawn, Exit twice.
3. **Measurements**, on a quiet machine (end the field game with
   `python H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\vr\v2\quit_field_game.py` if it runs; say so): frame rate,
   reprojection and GPU time by pass with hands visible on gm_construct and Modern House at 90 Hz, with a 1280 x 720
   and a 3840 x 2160 window; the warp's cost with something at 0.2 m and with nothing near; the game thread's CPU
   time per frame of each add-on module with everything on (and with VR off: nothing); network messages per second
   between client and server in the combined session. Never change SteamVR's settings (refresh rate included).
4. **Flat parity of the whole package**: with VR off, 5 + 5 alternating launches of `main`'s published package and
   `v2q`'s, the same map, pose and settings: frame interval medians, start-to-map times, the screenshot difference,
   the hooks, timers and receivers present (only the stub's receiver and the page's tool menu are new).
5. **The package and the look command.** Build the package from `v2q`; the manual look command
   (`tools/vr_session.py --look`) tested with a Python without Pillow (a fresh `python -m venv`), as the user's
   terminal runs Miniconda's Python without it.
6. **Documents**: CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING and AGENTS from the tasks' "text for the shared
   documents" and your own results; the decision records' index; your decision records **0172-0174** (the combined
   acceptance and its driver, the review fixes, what else you decide); the report
   `docs/handover/VR-V2V3-Q-report.md` (every Done point with its number and picture path, the measurements, what is
   open, what a person in the headset should try first). `tools\test.ps1 -Config Release` passing.

## Files you may change

Anything the review fixes and the integration need, except: `loader/` (never), the files tasks S, W, K and T own
(VR-V4-plan.md section 1: `cl_weapons*`, `sv_weapons*`, `cl_reload*`, `sv_reload*`, `cl_tools*`, `sv_tools*`, the
scaffold's stubs, protocol ranges and settings) and, while their follow-ups run, M's `cl_ui*.lua` and R's runtime
fork (ask Claude if one of them needs a change). Commit only on `v2q`; never push, merge into `main` or `vr2`,
publish, or start a workflow.

## Rules

The plan's "Rules for every task" hold. SteamVR is running: never quit it or change its settings. The PoC and VR
locks are shared with the other tasks: keep sessions to what a point needs. Your final message: every Done point's
result with its number, the measurements, the commits, the gate's result, what is open.
