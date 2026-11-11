# 0148: VR panels use SteamVR overlays fed by exact-sized game render targets

- Status: Accepted 2026-11-10 for V1 and the later panel work.
- Context: the user's [VR UI decision](../handover/VR-plan.md), spike S8 and
  [Q's image checks](../handover/VR-V1-Q-report.md). A flat HUD at the depth of the world is
  uncomfortable and cannot become a useful controller panel through the centre-view warp.

## Decision

The add-on paints a dedicated raster render target. The module creates an owned SteamVR overlay
and tells the runtime its exact width and height. The runtime recognizes a target of that size,
copies it to a Vulkan image and supplies the texture to SteamVR. There is no global raster-UI
capture and no special interpretation of every HUD target. SteamVR composites the panel with
its own pose independently of the path-traced centre image.

V1 uses a 769 x 257 pixel target for health, armour and ammunition, 0.23 m wide on the left
controller with a local 0.065 m offset. Start checks the allocated size and every overlay setup
result (`vr/addon/lua/nlvr/client.lua:169`). An overlay requested visible stays hidden until it
has a valid transform; losing the controller hides it, and a valid controller places it again
before it is shown. Numeric handles
cross Lua as strings so all 64 bits survive.

The centre image and eye submissions are made before the game's ordinary 2D draws. The mirror
is copied to the desktop target before those draws. The flat HUD, spawn menu and other flat 2D
therefore remain on the desktop by construction, without changing `cl_drawhud` or replacing
the game's hook or VGUI libraries. The add-on reversibly suppresses the ordinary 3D view model,
hands and local body/weapon proxies; V2 to V5 supply their VR equivalents. World geometry drawn
with 3D2D remains world geometry.

## Consequences

In Q's gm_construct PoC captures on the RTX 5090 and Index at 90 Hz, a magenta flat-HUD witness
occupied 4231 desktop pixels and none in either eye in each of five captures. The world mirror
matched a left-eye crop within 0.58 to 0.77 colour levels out of 255 on average; the right-eye
comparison differed by 34.6 to 56.8 levels. The wrist showed the player's changed health,
armour and ammunition, with zero texture or transform errors. Its colour target occupies
790532 bytes; Source caches it and its fonts until game exit, while the SDK overlay and runtime
images are released at Exit VR.

Future menus can use separately owned, exact-sized targets and overlays. Input routing, lasers
and controller interaction are V2. A size collision remains something a new panel must avoid;
the dimensions are part of its interface, and the runtime does not identify the target by a
Source material pointer or by its contents.

## Alternatives considered

- Capturing the whole flat HUD would also capture unrelated add-ons, would put every panel in
  one plane and would need another way to separate the desktop UI.
- Rendering the wrist in the path-traced world would put its readability and update rate
  through the centre warp and temporal history.
- Matching a rounded or resized target would accept a different source accidentally. The
  exact-size handshake and allocation check fail visibly instead.
