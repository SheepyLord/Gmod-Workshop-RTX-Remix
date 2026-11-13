# cl_hands.lua

Session-owned client hands module (`name=hands`, order 20). Included by `nlvr/client.lua` only at
Start VR. `Start(ctx)` registers the priority-10 world resolver, a world draw hook and an
overlay-paint listener. `Stop()` removes two client models and ghost overlays; registry cleanup
covers partial startup and failed callbacks too. No autorun, files, timers, net or setting writes.

Uses `player_manager.TranslatePlayerHands` for model, skin and bodygroups, checked every 250 ms.
Unusable models/wrists fall back to citizen arms. Client creation and wrist discovery validate
them; util.IsValidModel would wrongly reject arms not precached by the server. Each opaque model keeps
one forearm/hand hierarchy. SetupBones initializes the name cache before discovery.
BuildBonePositions moves it to `NLVR.Hand[side].shown`; all other
valid bones collapse at its elbow. Scale follows session units/metre. No model is drawn through
HUD, a canvas or the view-model pass. The opaque models draw in PreDrawTranslucentRenderables
because the RTX path does not dispatch the ordinary opaque callback. The shared ValveBiped
wrist/finger-yaw basis and mirrored thumb opposition preserve anatomical handedness; physical left/right never
follow the dominant input role.

Finger input and `grip_curls` use [cl_hands_pose.lua](cl_hands_pose.lua.md). Ghosts are lazy,
reserved `ghost_left` (265x267) and `ghost_right` (269x271) overlays, painted once and placed at
the true target, facing the head. They show only for valid blocked hands with
`nl_vr_ghost_hands=1`, at 0.24 alpha / 0.16 metres.

`NLVR.Debug.hands.left/right`: model/fallback, retained bones, finger bones, applied curls/splay,
grip override, shown-target distance in game units, blocked/valid/ghost flags, paint/build/draw
counts. Engine errors reach the framework's isolated module-failure handler; no command/exit code.

Tests: `python -m unittest discover -s companion/tests -p vr_hands_test.py -v`.


## V4 controller frames

C adds uncurled model-local palm/finger/thumb calibration via `core/cl_hand_model.lua`; bones are placed by the inverse of that frame. `HandModelFrames` exposes the cached calibration to weapon placement and is removed at Stop. Debug hands include `palm_frame`.

C derives each joint's curl and spread axes from the anatomical hand frame and the uncurled model bone matrix. Calibrated fingers flex into the palm (mirrored by physical hand) instead of assuming shared bone-local yaw. The prior axis fallback remains for incomplete models.

C caches the closed-finger grasp centre alongside palm geometry. Reference posing occurs only during model creation, before the draw callback, and is fully restored.
Integration: nested Debug.hands/curls/splay tables are reused across frames; invalid shown poses are never drawn.

With a valid controller frame, current SDK WithController joints drive unarmed hands and GripLimit supplies the owned weapon grasp. The anatomical model and mesh tips are retargeted in the bone callback by cl_hand_model.lua; unavailable data returns to the measured rigid fit. A private diagnostic may supply labelled referenceSkeletons in its test frame. Debug retains skeletal_source and the model-centre correction. Stop removes models, callbacks and hand-frame references normally.

## Review correction (2026-11-12)

The production Skeleton reader is sampled at most 30 Hz with reusable compact input buffers and separate last-good samples. Missing GripLimit references retry at 0.5 seconds. Failed/busy reads retain the previous pose; identical payloads skip updates. Only a new hand model or changed usable controller geometry rebuilds its stable grasp frame, not live fingers or an otherwise identical property-event revision. Named reference and WithController buffers are separate. Model removal clears anatomy and every cached frame. Debug includes read/change/refit/failure counts and cumulative sampling/bone-build CPU milliseconds. The private diagnostic feeds the reader per frame, never replaces BeginFrame skeletal tables.

An optional session-owned HandDrawObserver receives the exact matrices submitted in the world draw and that target's device frame. It allocates no snapshot table when absent. The private probe asserts exclusive ownership and removes it at Exit; no engine hook is swapped. Bone-build CPU timing includes this observer when enabled, so diagnostic timing is an instrumented upper bound.

## Placement review (2026-11-12)

Sampling now follows each rendered frame (FrameNumber still prevents duplicate work), using the existing compact buffers and last-good policy. This supersedes the earlier 30 Hz cap: cheap sampled poses should not visibly step. Static grasp/model measurement remains unchanged. Native property refreshes use fixed reference landmarks rather than live curled landmarks.

When no usable hand component frame exists, full skeletal retarget reads are skipped; the raw fallback uses the ordinary render-rate curl input. It does not repeatedly fetch an unused reference.

Verification regressions exercise locomotion versus intentional gestures, held body wall/constraint safety, deferred window refusal, moving two-hand mesh-query rate, pending overlay cancellation, expected logical capture roles and ULib/unknown/reentrant view ownership. Tests retain failures from the prior source, use stand-ins without SDK, and remain in the normal gate.

Unwanted ghosts call Show(false) only while visible or wanted. Pending acquisition is canceled, and idle hidden handles make no repeated native transform/hide calls during the grace interval.
