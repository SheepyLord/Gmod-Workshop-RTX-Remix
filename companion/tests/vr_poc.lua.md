# vr_poc.lua

Test-only real-game review probe assembled by [vr_poc.py](vr_poc.py.md); never shipped. Injects the shipping page
and add-on from strings in a private include/require environment supplying [vr_standin.lua](vr_standin.lua.md).
Loads no native VR module or OpenVR. It changes no global include/require, hook dispatcher or VGUI function.

Records engine SetString/RunConsoleCommand probes for fps_max/cl_drawhud/r_drawviewmodel, restoring allowed test
changes before Start. fps_max's blocked path is observed rather than bypassed. Then takes a baseline and drives
three scripted head poses, a short CreateMove walk, normal nl_vr_exit, an Events quit, and a final active session
which the real game ShutDown stops. Tests actual CalcView output against independent yaw/scale arithmetic and
render.GetViewSetup; repeats the production callback to check one push per sequence. Existing/late competing
CalcView hooks test authority. Source position/current view offset/GetPos and pose-frame age are logged.

Lists hooks/settings/global function identities and proxy flags before/after cleanup, witnesses actual view-model
and hand draws, and captures the painted 769x257 target in PostRender. PNG and full API/measurement JSON leave
through chunked base64 NLVR_E_BLOB console lines; there are **no game data/evidence file writes**. The runner
decodes them into repository out/. NL_SHOT markers use poc_session.py's screenshot/ack protocol. Native Stop's
test callback inspects addon cleanup during the genuine shutdown and exports the final evidence. A test-only
Stop wrapper records engine values immediately before/after cleanup: poc_session legitimately restores the
user's field config before quitting, so the launch fixture is not the expected shutdown cap. Root proxy Think
fields and render-child visibility are included in the before/after inventory.

Test-only hooks/timers/command callbacks live until this test game quits; all names start vr_e_review_probe
(nl_shot_taken is the driver's protocol). The assertions concern production addon/page session callbacks and
unchanged preexisting handlers. Errors print NLVR_E_FAILURE and export failure JSON. Both SP and listen-host
runs are required; command blocks are expected console diagnostics, not unhandled Lua errors.
