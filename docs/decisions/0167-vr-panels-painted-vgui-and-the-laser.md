# 0167: VR panels use painted VGUI and a laser

Accepted for V2 task M, 2026-11-11, implementing the binding V2/V3 plan.

The existing sandbox panels own their tabs, search, icons and properties. Borrow them into owned VGUI roots,
paint with PaintManual(true) into fixed odd-size RGBA8 targets, and show them through the framework's SteamVR
overlays. Ordinary panels stay at their opening pose in tracking space, 1.15 m forward; the wrist menu attaches
to the off controller. Scoped virtual ScrW/ScrH lets sandbox layout use the canvas dimensions. Restore those
functions even on failure and restore each borrowed panel before removing its root. Settings uses 1283 x 963,
separate from the framework's context reservation. No desktop resolution or GUI-scaler setting changes.

The main controller's ray selects the nearest panel. Its trigger is claimed for engine VGUI presses/releases,
including the entire hold and release after a miss; its stick scrolls. Cursor changes are scoped and restored.
The user command clears a claimed attack. A single SteamVR billboard draws the beam and dot; no UI is path
traced. Context world-property clicks supply both the hand's origin and direction. New Derma menus enter their
owner's canvas. Text focus requests SteamVR's keyboard; the page remains the sole native event reader and fans
events out through F's module registry. Closed/destroyed fields reject late results.

The wrist offers spawn/context/flat/settings, height calibration, recenter and Exit. Settings exposes the plan's
variables without redefining them. Height calibration emits `calibrate_height`; task L owns measurement and
scale changes. All UI resources belong to the active module; Exit restores borrowed resources and leaves no
session hook or overlay. Offline tests prove state/geometry and real sessions prove VGUI/overlay behavior.

Implementation clarification: the cursor scope is one hover/capture interaction. Restoring it after each
synthetic event would send a second movement to a captured slider. Restore on miss after release, close, error
or Exit instead. L's implemented event is `height_calibrate`, so the page/wrist use that name for integration;
the earlier provisional spelling above is superseded. No core change is needed.
