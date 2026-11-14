# vr_interact_poc_client.lua

Client probe appended to the stock VR session probe by vr_interact_poc.py. Reads the native
test timeline clock to select server fixture phases; requests an extra gloves capture and
both eyes/centre/mirror/overlay captures for each interaction phase, and
the server cleanup receipt after Exit. Uses a temporary PreRender hook removed after one cycle.
Inputs: test session only; output: ordinary server console commands and capture request.
No production file changes, archive writes or physics authority. Shared driver collects Lua
errors and restores the PoC. No process exit code.
Phase commands retry until the owned server acknowledges them, including a late first frame.
The acknowledgement global is removed after Exit. This changes no production network message.

V8: phases up to 17 are sent and captured. During phases 14 to 16 it prints `v8-client` records every 0.25 s: the
predictor's mode, `follow`, blending and drawn position (`Debug.interact.right.predicted`), the held entity's networked
position, the shown hand and the hold's flags.

V8, `--fg-check`: each `v8-frame-generation` record holds the setting, Auto's target, rate and budget, the perf
module's Motion Smoothing readout, the VR page's status text, the module's `motion_smoothing_supported`/`enabled` and
the latest frame's reprojection flags. The saved value of `nl_vr_frame_generation` is set back after 4 s.
