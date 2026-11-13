# vr_frames_harness.lua

LuaJIT fixture for `vr_frames_test.py`: arguments repository root and case name. Loads production core/frame and anatomical helpers with independent maths. Component constants are copied from SteamVR's named render models (same sources as `vr/native/tests/test_frames.cpp`). Does not read SteamVR, start VR or mutate game files. Prints PASS; exits nonzero on assertion.

The skeletal fixtures exercise Source-basis model-space reference placement and the actual bone-matrix retargeter through independent matrix/Euler stand-ins, including distal mesh endpoint mapping. The grasp-circle regression also runs in millimetres to catch a Source-unit-only degeneracy threshold. The companion Python metrology cases independently validate handle/cylinder fits.

## Review correction (2026-11-12)

Recorded JSON fixtures drive Open/GripLimit/Fist/WithController. Regressions cover bounded reference grasp, constant calibration, wrist/palm and roll continuity, partial-component raw/aim behavior, stable storage and changing recorded reader buffers. No SteamVR install is read.

## Placement review (2026-11-12)

draw_target_pool fails without persistent target storage; the palm-axis regression rejects an independently shifted rendered palm. Stability checks remain explicitly distinct from placement.
