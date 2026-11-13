# vr_v4_poc.lua

S's supplemental production-session probe, appended by vr_v4_poc.py. Records actual fixed module slots/settings, window size, settings canvas and GUI Scaler value, scrolls the settings panel to its final Weapons group for M's existing capture, then removes its own PreRender hook when VR stops. Reads actual NLVR/VGUI state; does not change module behavior, settings, scaler or game files. Outputs NLVR_Q v4s JSON records. No standalone process exit code.
