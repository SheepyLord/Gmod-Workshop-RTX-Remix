# 0168: The VR flat-screen panel uses the window source

Accepted for V2 task M, 2026-11-11, implementing the binding V2/V3 plan and interfaces 8/9.

Use nlvr.OverlayWindow(handle, true), whose native implementation requests SHOW and NO_MIRROR: the runtime's
post-2D window picture over black, at most 1920 pixels wide. This makes the escape menu, console and other
add-ons' windows accessible without tracing their UI or recursively showing the headset mirror.

Map laser UV to the actual window's pixel coordinates for real cursor and mouse dispatch. The source occupies
the whole flat overlay, so its close mark uses a separate 131 x 133 overlay just above it. Disable the source
before destroying its handle. The desktop cursor is restored after dispatch; no game-window size is changed.

Native/runtime additions are independently versioned optional exports. If the function is absent or refuses the
source, show a translated update explanation in an ordinary painted panel. Do not counterfeit window content
with a second world render or replace an unavailable source with the mirror. Q integrates the native/runtime
builds and verifies the black background, escape-menu Resume click and console on the actual source.

Implementation evidence (task M): the client InternalCursorMoved path recentres GameUI at 1920 x 1080 in a
3840 x 2160 window, despite requesting 140 x 249. Positioning the actual window cursor without that call makes
the same press/release resume the game. Painted client panels retain their own input path. The empty flat
window offers Escape so controllers can reach it without a keyboard; a pre-existing 2D window keeps focus.
Temporary cursor mode and synthetic mouse deltas are owned and restored by the UI module.

Evidence correction, 2026-11-11: the preceding Resume-success inference is withdrawn. The early probe did
not confirm menu visibility immediately before the press; its same-frame Hide/Activate reset could itself
hide the menu. Corrected flat-probe-03/04 require visibility before every press. Both getters can reach
140 x 249 with game focus true, but CLIENT's mouse APIs, both setters/clicker states, GMod code 107 and native
code 0 do not activate MENU's HTML control. Display/source delivery is accepted; MENU mouse delivery is not.
The attempted production reset was removed. A bounded owned-window/MENU native input primitive or verified
MENU relay is required from its owner; M did not change unassigned native or loader paths. See the task report.

## Follow-up — 2026-11-11

The user widened M's scope to `vr/native`: a single `nlvr.WindowInput(kind,...)` now owns flat-panel
input. It selects this process's unique top-level `Valve001` window, rechecks ownership before
each posted message and accepts no Lua HWND. Only cursor, three mouse buttons, wheel, printable
Unicode scalars (UTF-16 surrogate pairs) and the named editing/navigation keys are exposed. No
SendInput, global hooks, focus activation, arbitrary keys or window messages. Off/busy sessions
refuse clearly. Normal traffic is capped at 64 posted messages per acquired VR frame; owned
presses are balanced on errors, Exit, renderer failure and unload. Read-only diagnostics include
foreground state and delivery counts, never a handle. Failed posts do not count as consumption.

Painted panels keep their VGUI dispatcher. SteamVR's keyboard is still tried first. On failure,
an owned 1039 x 391 US keyboard overlay below the target accepts laser input, using normal field
text callbacks for painted panels and WindowInput for the actual window. Its shift, space,
backspace, enter/close and navigation labels use the existing six-language catalog generator.
The flat toolbar's Aa requests text, and X closes. Keyboard, settings and flat-close sizes come
from S's central overlay table after integration, not additional local reservations.

The platform message encoding follows Microsoft's [PostMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-postmessagew),
[WM_MOUSEMOVE](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousemove),
[WM_CHAR](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-char) and
[WM_KEYDOWN](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-keydown) contracts.
Foreground engine behaviour and guarded Resume/search/console acceptance require the PoC/Index
evidence recorded in the report; neither queue success nor an automatic menu hide establishes them.

Measured with the follow-up native path: background posts are queued successfully but do not act on
the HTML menu on this engine build. With the PoC window foreground, the guarded Resume click closes
the menu while both OS/Lua cursor getters remain centred. The foreground console receives WM_CHAR
and balanced Enter messages: laser fallback typing runs `echo nlvrmconsoleok` and produces its bare
output. This is an input focus limit, not permission to activate a window or inject global input.
