# cl_tools_controls.lua

Client-only helper owned by tools at VR Start. New(ctx) returns physical-hand control
latches. Stick retains its claim until radial input is at most 0.2; Trigger retains
its claim until physical release. Frame renews claims even after tracking loss, tool
drop, wheel close/cancel or dominance change. Existing earlier owners keep their claim.
Move consumes the corresponding main primary/off secondary command bits. Stop clears
the latches. It never drives movement, pickup or use; no files/network/settings.
Tests exercise handoff to L/P, including a pushed drop and mirrored held trigger.
