# vr_v4_cases.lua

Extends F's framework cases with nine V4 scaffold scenarios. vr_framework_cases.lua supplies the existing environment and helpers; vr_v4_test.py drives the f_v4_* cases through vr_harness.lua. Exercises every 64..127 module type through both actual network APIs, range rejection, unchanged sync, all overlay reservations, convar declarations/ranges/page/core changes, client/server stubs in SP/listen-host mode and cleanup, 30-degree head roll and 60 yaw/movement combinations including a 90-degree aim change. Uses no game/OpenVR or network; only in-process harness state. Lua assertions exit nonzero.


The central reservation count is 21 after Q adds two reserved arc-dot sizes. Existing V4 role sizes, module orders, protocol ranges and setting expectations remain checked.
