# vr_ui_window_probe.lua

Task M's native-window diagnostic, loaded only by `vr_ui_poc.py --window-probe --seconds 15`.
`--window-press-at 20 --seconds 30` leaves more time for a foreground control.
Uses the production flat panel and main-hand laser/trigger. Opens Escape, captures before/after,
and records visibility immediately before the actual posted button down; it never hides/resets
GameUI before measuring Resume. Wraps only native pose/actions for the scripted hand and records
WindowInput diagnostics. Restores wrappers on Exit. Inputs: the driver's CONFIG/native timeline.
Output: `NLVR_Q` UI records and named captures. No standalone exit code or persistent setting.
