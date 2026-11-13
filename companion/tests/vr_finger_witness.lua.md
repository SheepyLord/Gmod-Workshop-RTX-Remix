# vr_finger_witness.lua

Private combined-session metrology, never packaged. `New()` returns `Observe` and
`Snapshot`. Caller invokes Observe from the hand draw observer after SetBoneMatrix,
with the actual model, side, time/frame and open-reference flag. It re-reads engine
GetBoneMatrix for the authored Hand/Finger0..4 names; it ignores the renderer's planned
matrix array and GetManipulateBoneAngles. Relative-to-parent orientations cancel the
hand's world placement. Snapshot contains open/closed local rotations and provenance.
No hooks, game mutations or files are created; caller owns observer cleanup. Missing
models/bones yield no certificate. Compiled/executed by test_vr_combined.py; normal Lua
include errors propagate. Outputs are test JSON under out, never field data.
