# cl_ui_panels.lua

Fixed odd-size overlay canvases for existing sandbox spawn/context panels, wrist menu and settings. Panels open 1.15 m in front of the head; wrist attaches to the off controller. PaintManual(true) paints their VGUI roots. Borrowed panels retain tabs/search/widgets and restore parent, size, position, dock, layout, visibility and input. Scoped ScrW/ScrH makes layouts independent of the window and restores on errors. New Derma menus enter the interacting canvas. Context properties use both parts of the hand ray, including outside the canvas. Flat uses OverlayWindow or a translated update notice, plus a separate close overlay for a working source. Settings emits height_calibrate for L. Sizes: F's reservations, settings 1283 x 963, flat_close 131 x 133. No file/engine-setting writes; no process exit codes. Restore failures log without skipping root/overlay teardown.

VGUI can defer callbacks beyond the registry's current module. Buttons enqueue actions for the next owned
Frame; stale actions are discarded at Stop. Sandbox MakePopup roots and adopted popup menus are explicitly
painted, using fixed bounds instead of desktop docking. Scoped bookmark suppression keeps their
Remember/RestoreCursorPosition calls from changing the desktop cursor memory. Context keeps a transparent
body for world targeting. The owned settings canvas uses a light background and fixed 20-pixel extended fonts.
Context widget popup windows keep their original parent/lifetime; their manual paint and position restore
when leaving VR. Borrowed layout overrides restore the original raw slot, preserving inherited methods, and
the spawn divider's original width comes back after resizing.
The initial sandbox visibility/input/hang flags are captured at module Start, before any popup changes focus,
and restored at Stop. A working flat source offers the Escape menu after its opening transition only when no
other 2D window has the cursor; existing add-on/console windows keep focus. After Resume it enables the cursor
only if needed and removes that owned screen-clicker state at close. It hides only a game menu it opened.
Owned controls opt out of GUI Scaler with gScF and use independent 20/26-pixel fonts.
The owned settings combo's DForm wrapper receives the same row height, preventing its larger font being
clipped to the stock 13-pixel control row. The actual window picture works, but MENU/HTML mouse delivery is
unaccepted with current CLIENT-only APIs; no automatic menu hide/reset is used to fake a click result.
# Follow-up

The window's separate toolbar has X above and Aa below: close and request text respectively.
The native dispatcher now owns flat input; initial CLIENT-only evidence above is historical.
An 18-pixel extended keyboard font keeps the US fallback's translated action labels readable.

The settings and flat_close canvas dimensions now come from ctx.Overlay.Sizes.settings / .flat_close; placement and UI behavior are unchanged.

Inventory(optionalOutput) clears/repopulates a supplied list from cached plain per-entry rows; default callers still receive a fresh list. Source dimensions/handles are fixed for an entry.


Review correction: reparent borrowed sandbox menus before protected close hooks/Close, then restore layout and flags even when a callback throws. Window and sorting state use the lazy manager API; debug handles refresh after recreation.


Window state becomes ready only after accepted native binding and visibility. Refusal paints the existing update fallback and does not activate GameUI. Resource-deferred windows stay pending. Supported windows retain the ordinary close/keyboard controls.

Painted-panel Interaction(hit,x,y) retains the controller pixel and lazily scopes CursorPos overrides to the active hovered control and its ancestors. Stock drag Think therefore reads canvas coordinates even when a background desktop poll resets native cursor state to (0,0). Close restores prior per-instance methods only while still owned, preserving later replacements; no global Panel/input cursor function changes. Native flat-window input remains on its posted-message route.
