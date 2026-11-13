# cl_ui_laser.lua

SteamVR overlay billboard with a narrow beam and endpoint dot, from the dominant controller to the nearest hit (1.3 m otherwise). Reserved 65 x 1027 target, created lazily, painted once, placed each frame and hidden without open panels/tracking. Uses tracking metres; never world draw geometry. Inputs: context, ray and hit. Output: owned overlay. Stop destroys it. No file/setting writes or process exit codes.


Review correction: sort order is stored by the lazy overlay manager before a native handle exists.
