# vr_frames_poc.lua

Test-only client fixture appended to the production VR session probe by vr_frames_poc.py. The generated local diagnostic addon supplies SteamVR's OBJ geometry; neither is included in production inputs. Drives weapon/handedness phases, raw controller mesh diagnostics and normal captures at natural-hold poses. Records native component/skeleton transforms, rays, actual c_arms bone matrices, weapon grip/attachment, curls and UI/movement debug in bounded console chunks. Creates owned Mesh resources via the registry and destroys them at Exit; restores changed dominant/trim settings. No filesystem writes or process control; runtime Capture writes only under the launcher's out/ root. Lua errors fail the production driver.

Review diagnostics draw SDK wrist, thumb, metacarpal, proximal, middle and tip markers with the controller: cyan WithController, magenta grip-limit, amber fist. Receipts retain every source and mesh-derived fingertip, so original pose and depth cannot substitute for handle/joint metrology.

The fixture registers an owned first-priority mover that zeros CUserCmd mouse deltas, keeping unrelated desktop movement from turning the scripted play space. A command counter proves that fixture ran; registry Exit removes the mover. It changes no sensitivity/SteamVR setting or production mouse-turn path. [CUserCmd:SetMouseX](https://wiki.facepunch.com/gmod/CUserCmd:SetMouseX) is the documented test-input operation. A rejected attempt to change m_yaw via Lua was discarded because GMod blocks that command.

## Review correction (2026-11-12)

Records actual bone forward/up vectors and per-render curl-sweep aggregates. Roll compares transverse axes after shortest-swing transport, not Euler roll wrapping. The wrist and mean knuckle palm are compared in controller coordinates, and the actual weapon anchor against its holding palm. Positive finger travel/read changes prove animation was exercised. Raw live SDK availability remains separate from recorded markers. All meshes, callbacks and test API wrappers are owned and cleaned up.

Draw observers snapshot the matrices actually submitted and their matching controller frame; later PostRender bone-cache reads are not used. Articulation aggregation covers phase seconds 1..19.5, after camera settling and before the last .2-second view transition. All four endpoint poses and interpolation are included; camera-transition failures are retained as rejected witnesses. Stable-interval tracking motion is independently recorded. Closed-axis/joint checks remain secondary consistency measurements.

## Placement review (2026-11-12)

WeaponDrawObserver reads the actual model mount bone and transforms independently recorded mesh-grip coordinates. It compares this with the centre computed from the drawn hand middle-finger bones in every gun frame; missing grip evidence fails. The old synthetic anchor remains only a debug field. Empty sweeps have no gun-grip result (not zero). Rendered palm-up is captured for uncalibrated cases.

Q4: the geometry matrix includes all W classes and independently checks the physgun first attachment. `--export-meshes` exports ten further posed model meshes via the private observer to `models.json`; no acceptance is claimed by an export.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.


Physgun witness combines the asset semantic core attachment with the observed beam origin. Neither W nor T numeric fallback can certify the other; a shared wrong origin fails against the independent asset metadata.


Non-shaft captures declare authored_holding_bone_to_rendered_hand_bone. The beam is explicitly the add-on cl_tools draw; only the asset attachment named core is an independent physgun emitter reference.

Live evidence uses the full raw mesh centreline and actual drawn finger circle, plus the observed asset bone/semantic-handle envelope. It records grasp and rig residuals separately; no authored bone is a precise product grip target.
