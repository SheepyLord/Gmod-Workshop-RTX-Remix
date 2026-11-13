# vr_ui_poc.lua

Injected by vr_ui_poc.py; not shipped. A 70-second adaptive UI fixture: scripted off-hand B and
main-hand aim/trigger, wrist/spawn/context/flat/settings captures, prop-icon spawn count, property
removal, search text and escape Resume checks. Head/off hand come from the native timeline. Main-hand
angles are calculated from real widget bounds and fed into the production pose sampler;
mouse/hit code is untouched. Emits bounded NLVR_Q ui records. Runtime images stay under the
launcher's native capture root in out. Restores native wrappers and removes its hook after Exit;
the standard driver restores the game and settings. No standalone use or process exit status.
The fixture also drags a real slider, scrolls, restores all changed VR variables after controls are removed,
and compares borrowed VGUI geometry/input/parents and the desktop cursor after Exit. No test directly invokes
a prop icon/property action; those outcomes must come from the production laser and real VGUI callbacks.
When the fresh PoC has no saved spawnlists, a fixture ContentContainer in the real creation menu uses stock
spawnmenu.CreateContentIcon("model", ...). Its stock action remains unchanged; only real laser input can spawn
the barrel. Capture times avoid the standard probe's 30/42-second single capture-request slot. The flat Resume
point is mapped from its actual 720p/4K HTML-sidebar pixels. Geometry records prove fixed canvas dimensions.
The input diagnostic records setter arguments, both getters, client cursor moves and system focus at the
actual flat-window press. It never treats an explicit cleanup HideGameUI as successful Resume.


The review fixture supports head-attached stress canvases. Drag targets the snap-angle DNumSlider identified by its unique 15..90 range, then uses the stock knob and unchanged production laser/input path. A mid-drag observer records native widget dragging and the actual value; it never invokes a widget action to make the test pass.
