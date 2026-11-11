# test_vr.py

The second-review cases cover busy camera recovery and the first overlay-copy acknowledgement;
the group has 58 cases with the render-guard and catalog checks.

Review regressions include nil camera retention, thirty nil/message failures with deduplicated
logging, paused render-hook quit polling without timer ticks, page nil/message failure, failed
overlay Start and recenter. The harness models async stopping and SDK-ready bootstrap separately.

VR-Q adds SDK-ready first-frame bootstrap, asynchronous Stop acknowledgement and the translated
fps_max warning cases. The tested Index FOV default is 145 degrees. Catalog tests reject codepage
damage in every new translation.

Run `python -m unittest discover -s companion/tests -p test_vr.py -v` from the repo. Runs the production page and
add-on under LuaJIT in [vr_harness.lua](vr_harness.lua.md). Each scenario has its own Lua process. Skips when
LuaJIT is absent (PATH or LOCALAPPDATA/Programs/LuaJIT/bin); no OpenVR, headset, game, GPU, network or file writes.

Checks off-state work, explicit status probe, native/runtime/API errors, local/remote hosts, active/inactive
VRMod/gVRMod, asynchronous start/cancel/failure/quit/shutdown/hot reload, partial startup and frame/paint failures,
unchanged engine settings, predicted tracking transforms and lost tracking, exclusive CalcView ownership and
late hook restoration, once-per-sequence camera submission, wrist contents/repaints, intact desktop 2D/notices,
GPU boundaries and numeric status readouts. Includes the
[production guard canvas check](vr_guard_harness.lua.md). Exit 0 on success, unittest nonzero on failure.
The session-scale race and body/weapon proxy visibility are covered too: VR never toggles the proxy convars or
their secondary Remix shadow-option callback. All seven session hooks and the temporary CalcView table are gone
after cleanup. The engine convar stand-ins reject SetString, matching GMod rather than accepting unsupported writes.
An additional pure-Python catalog byte check runs even without LuaJIT and catches UTF-8 decode failures,
replacement characters and unexpected question marks in every VR message of all six languages. It caught a
Cyrillic category abbreviation damaged by a PowerShell pipe during development; UTF-8 file edits corrected it.
