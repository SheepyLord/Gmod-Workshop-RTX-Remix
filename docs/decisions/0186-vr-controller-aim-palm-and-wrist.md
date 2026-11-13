# 0186: SteamVR defines the controller's aim, palm and wrist

Date: 2026-11-11. Task C of V4, directed by the frame brief.

The device origin is neither the pointing tip nor the hand. Using it for both leaves Index/Touch rays roughly forty degrees above a natural hold and draws the wrist in front of the real hand.

Read `Prop_RenderModelName_String` and `IVRRenderModels::GetComponentStateForDevicePath` for `tip` and `openxr_handmodel`, once per connection. Read `mTrackingToComponentLocal`, not the render mesh's transform. Activation, deactivation, update and role-change events invalidate the cache. The interface is optional. Invalid or missing components retain the raw pose, with one log per hand/controller revision. All transforms are checked finite, rigid and within one metre; no controller-model paths or files are read in production.

The aim is the tip. Both aim and anatomical hand use its orientation: fingers forward, thumb up. The palm centre is halfway between the WithController skeleton's wrist (bone 1) and mean proximal knuckles (7/12/17/22) in model space; bones already include their root. This uses a stable anatomical point for P's proxies, grabs, sync and weapons, rather than a skin surface or one moving fingertip. If the standard 31-bone skeleton is unavailable, the wrist is openxr_handmodel and the palm is six centimetres toward the knuckles along aim. This bounded anatomical fallback is explicit in diagnostics; unsupported controllers fall back to raw.

BeginFrame keeps its existing predicted raw poses and adds local frame data. Lua composes those data after play-space transformation, once in the core, so prediction remains unchanged. `Pose[hand]` becomes the palm, `.raw` remains the native tracking pose, `.device` is the raw world pose, and `.aim`/`.wrist` are world transforms. `C.Ray` uses the tip. Rotating offsets add omega cross r to hand velocity. No protocol change is needed: the server already consumes hand poses. Wrist HUD/menu overlays already attach to the raw controller natively, so their attachment parameters stay unchanged.

Simulation records the Index's local components in its launcher-selected device description. Offline tests copy named Index/Touch/Vive data and never read SteamVR. A test-only capture probe reads the installation's low-resolution OBJ files at run time; it never ships with the package.

2026-11-12 review correction: for recognized Index models, the shared hand origin is the measured central handle reference, with the existing tip orientation. The old anatomical-palm/wrist fallback did not locate the closed grasp correctly. The measured handle constants are derived once from the installed render-model body sections and copied into the profile; production still reads no model files. `.handle` records the reference, while raw/device/aim/wrist remain distinct. Other controller profiles keep the bounded anatomical fallback. ADR 0187 records retargeting around this handle and the stronger acceptance checks.

## Review correction (2026-11-12)

A model name does not imply a valid component frame. Index handle constants require usable components/SDK hand data; otherwise hand position is raw. Each independently available tip/wrist survives, and any valid tip still defines pointing (including tip-only Pico/Knuckles/Vive variants). Incomplete native reads retry with bounded backoff; PropertyChanged invalidates them. Unknown controllers get their SDK/component hand frame if available, otherwise raw, with zero Index-specific correction.

## Placement review (2026-11-12)

An unchanged property notification cannot redefine a hand from live curl. Native cache refresh compares render-model/component geometry and retains identical reference landmarks/revision. Changed geometry derives landmarks from GripLimit. Live fingers follow render-rate reads with reused buffers. A raw or tip-only hand remains anatomically thumb-up; missing calibration does not authorize a mirrored weapon-wrist basis.
