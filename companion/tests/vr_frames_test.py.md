# vr_frames_test.py

Each case owns a unique recorded-pose Lua fixture under out/tmp; concurrent direct/bridge suites cannot truncate one another's input. The temporary fixture is removed after its subprocess exits.

Model-space regressions include SDK wrist/joint/mesh-endpoint retargeting, millimetre-scale finger circumcircles, handle centring, finite-span lateral/tilt rejection, handle sections excluding the ring, and an eight-joint cylinder with a known centre/radius. These require no controller, renderer or SteamVR process.

Runs C's LuaJIT cases with the repository's independent Euler stand-ins, without SteamVR or GMod. Run `python -m unittest discover -s companion/tests -p vr_frames_test.py`. Covers the copied Index left/right, Quest 2, Rift S, CV1 and Vive component data through the actual core's `C.Ray`, natural holds, raw/invalid fallbacks, offset velocity, and mirrored anatomical calibration. No SteamVR-install reads or writes. Exit 0 passes; 1 test failure. The repository gate imports this suite through `tools/tests/test_companion_vr_frames.py`.

The arbitrary-bone-orientation curl case checks both hands flex toward their palm after anatomical calibration.

## Review correction (2026-11-12)

Recorded JSON fixtures drive Open/GripLimit/Fist/WithController. Regressions cover bounded reference grasp, constant calibration, wrist/palm and roll continuity, partial-component raw/aim behavior, stable storage and changing recorded reader buffers. No SteamVR install is read.

## Placement review (2026-11-12)

draw_target_pool fails without persistent target storage; the palm-axis regression rejects an independently shifted rendered palm. Stability checks remain explicitly distinct from placement.

Q4 metrology regression accepts a different-rig 18.62 cm authored mount while requiring the physical handle/grasp registration, and rejects displaced or missing grip evidence. This does not waive modeled-weapon grip checks.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.

The helper itself rejects a6mm independent grasp error, even without a closed-grip diagnostic.
