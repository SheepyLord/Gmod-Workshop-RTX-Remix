# vr_standin.lua

Runtime API discovery now reports wire version 3 and a boolean SDK presence; no absolute SDK
path is published. This remains an explicit stand-in, with no real SDK initialization.

The scripted discovery result reports SteamVR installed to exercise the production start path;
its DLL path/model still explicitly identify a test, and it never initializes OpenVR. The separate
missing_steamvr offline case verifies the actual not-installed refusal and install instructions.

Test-only factory returning `(api, controller)`, never shipped. Compile/include in a GMod client test to get the
work plan's API-v1 functions without loading any DLL/OpenVR/runtime. Set controller.pose to script the head;
enqueue controller.events to exercise a quit. BeginFrame returns Source-axis Vector/Angle poses and a rising
sequence. Every API call is recorded with args, engine frame number and time; cameras, pose frame numbers,
overlay lifetimes and duplicate pushes are recorded separately. Optional onCamera/onStop callbacks let the
real-game probe inspect cleanup at native Stop, including the genuine game ShutDown.

Info values explicitly say SCRIPTED TEST and are mock metadata, never hardware measurements. No files, console
commands, hooks, timers or native state are created by this factory. [vr_poc.lua](vr_poc.lua.md) drives it and
exports evidence through the console; [vr_poc.py](vr_poc.py.md) runs that probe under the PoC lock.

V2/F supplies empty Actions and records OverlayAlpha for the framework. These remain test-only API stand-ins.
