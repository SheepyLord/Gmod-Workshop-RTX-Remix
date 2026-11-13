# vr_frames_poc.py

C's natural-hold feature/Index driver built on tools/vr_session.py. Example:

`python companion/tests/vr_frames_poc.py --package out/dist/package.gma --evidence out/vr/v4c/sim --seconds 88 --simulate --render-scale 0.55`

Omit --simulate for the Index (both shared locks). `--frames-short` selects empty/pistol/SMG/crowbar/physgun on the right for 38 seconds; the full 88-second run includes left-handed repeats, laser and teleport. Raw poses invert the recorded Index tip transform so pointing is level; palms are at chest height, not identity device poses. Existing driver flags pass through.

Reads SteamVR's installed left/right Index low-resolution OBJ files without modifying them. Generates a diagnostic addon and declared combined development package only in the chosen evidence sibling `*-fixture/` under this worktree's out/. The production package remains unchanged; no diagnostic asset or probe ships. Files have hashes/count receipts. Probe source is staged with the production acknowledged console transport. The native module uses simulation or real SDK components as selected; the diagnostic meshes are drawn separately from ordinary hand captures.

The driver waits for shared locks, snapshots/installs/runs/quits/restores through the production driver. It may end a field GMod game only through the user's authorised normal-console-quit helper, with a receipt. SteamVR stays running and its settings are never written. Source game inventory changes are test-console actions in the PoC. The probe restores dominant hand/trim. Outputs frames.json, frames-checks.json, hand crops, production eye/overlay/mirror/timing/rollback evidence. Does not print whole receipts. Exit 0 passes both production and C checks; 1 feature/driver failure; 2 argument errors. Needs Pillow as the unattended production driver does.

`--reuse-fixture --package out/.../fixture/package` reuses C's immutable diagnostic development folder for an Index comparison after simulation. It rechecks the original SteamVR OBJ hashes, records the manifest hash in frames-fixture.json, and avoids another multi-gigabyte copy.

`--recorded-controllers` is an explicit live-headset rendering diagnostic when controller devices are absent. The test-only BeginFrame probe supplies the already-tested Index component profiles only for unavailable hands, preserving `controllers_live` unchanged. Source is recorded_index_controllers_absent, skeleton=false; it is never reported as a live controller measurement. The production module and its raw fallback remain unchanged. One brief SDK haptic per hand attempts to wake a standby controller; the true return codes and availability are recorded. The ordinary probe restores all native function wrappers. This flag is incompatible with --simulate and does not satisfy the live controller/skeleton acceptance item.

--orthogonal selects separate left/right side and top camera views for empty hands, pistol, SMG main/forehand and unprofiled SWEP with the same SMG model. --skeleton-reference JSON adds an SDK model-space snapshot to the private diagnostic addon for simulation; live SDK queries remain preferred and source/error/recorded flags are retained.

`--sdk-pose` asks the real SDK for its GripLimit reference during the headset run and caches a valid result in the private diagnostic wrapper. It does not replay recorded joint coordinates. It can combine with explicitly labelled recorded controller components when device roles are unavailable. The probe draws raw WithController (cyan), GripLimit (magenta) and Fist (amber) markers, while the hands follow the closed GripLimit reference. All wrappers and private resources are restored on Exit. The production addon has no diagnostic cameras, model meshes or reference files.

## Review correction (2026-11-12)

--review-left selects both-hand empty/pistol/SMG main/support side/top views plus unknown classes with actual crossbow/pistol/shotgun/AR2/Annabelle models (147 seconds; use --seconds 152). --curl-sweep selects four 20-second side/top sweeps (use --seconds 85). --review-index combines those sweeps with the left empty/pistol/SMG/support set (136 seconds; use --seconds 141).

--skeleton-reference now installs a Skeleton-compatible recorded reader. GripLimit is a separate cached reference; WithController changes through Open -> GripLimit -> Fist -> WithController per read and per physical hand. Caller arrays are reused, timestamps/call kinds/changes are recorded, and the original API is restored at Exit. No BeginFrame referenceSkeletons injection remains. --sdk-pose merely selects normal real-SDK reads. The private capture fixture aggregates actual rendered bone roll, wrist/palm displacement, finger motion, own-palm gun anchor, sampling/bone CPU cost and geometry measurements. Simulation must pass before one Index reference run.

## Placement review (2026-11-12)

--raw-hands explicitly removes component frames and uses identity raw pointing poses, exercising the uncalibrated path. Use it with the same right/left, sweep and generic modes. Calibrated placement compares the rendered palm with the independent body.obj axis; raw models have no known physical controller placement to assert. Grip validation reads the drawn model bone and independent bone-local mesh-region data, never geometry.gripPos or Model.Pose target. Actual model axes come from posed mesh geometry expectations, not W.ModelData.

--review-final combines four 20-second sweeps with right/left pistol/SMG main/support side/top views (164 seconds; use --seconds 169). The raw --review-left set additionally covers the generic models. This permits both simulations to validate one frozen package before a single matching Index reference run.

--merge-check selects one mixed calibrated/raw set: right/left pistol and SMG foregrip, side/top views, 112 seconds (use --seconds 117). Each raw phase uses raw poses and explicitly failed components; calibrated phases use the ordinary recorded Index profile. The receipt records mixed_raw so each phase is checked against its own mode. No Index run is needed for this integration witness.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
