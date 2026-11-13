# cl_tools.lua

The visual beam starts at the rendered physgun model's native muzzle attachment when
available (cached attachment id), with W's checked muzzle as fallback. The review capture
found W's nominal muzzle 4.369 units from that rendered attachment; T does not alter W's
aim/server geometry. Actual render-call arguments and raw pixels verify the visual start.

Review cache policy: tools/physgun/wheel debug objects are retained. Tool descriptions
and phrase lookups refresh immediately on mode/object/stage/operation/language changes,
otherwise at most every 0.25 s for dynamic text. Unchanged overlay visibility/transforms
make no native calls. Model grip bone lookup is cached per model. Beam material, Color
and debug table are allocated once; the beam adapter dispatches other add-ons first.

Review 1/2: physical stick ownership survives a drop/tracking loss until its radial
dead zone, including a dominant-hand change. A latched stick never drives native
distance buttons after a drop or while untracked. cl_tools_controls.lua also retains
the wheel's physical trigger claim and command suppression until release, so P never
receives that held control as a new use edge.

Reliable changed-only hold state stays valid while resting. A missing local pose disables
convergence/stick immediately but retains the authoritative snapshot until the server's drop
receipt or local death/weapon loss/entity removal. A brief loss between sync ticks can recover
without requiring a fabricated heartbeat. Debug distinguishes tracked/temporarily untracked.

Client tools module, order 48, included only at Start VR. Uses W's NLVR.Weapon interface;
without that dependency it stays inert and owns no resources or controls. A later failed
weapon service closes the wheel and hides tool information until session cleanup.
message 96 observes the server's confirmed native physgun hold; 97 sends the dominant hand.
Holds claim the main stick and feed held distance into convergence. Use plus forward/back
buttons drive the native distance path; time-weighted pulses give partial-stick duty after
a 0.2 dead zone. W/K own attack/secondary/reload. DrawPhysgunBeam replaces only the local
VR beam with one from the rendered attachment (W fallback), respecting the player's beam visibility setting.

The 643 x 133 tool canvas reads the actual selected tool/stage/operation and translations,
repaints on text/mode changes. Its own point follows Active.model's right-hand grip bone,
falling back to the shown hand if that model/bone is absent; it uses no W-private geometry.
Debug retains the actual anchor and paint count.
cl_tools_wheel.lua owns B holds.
NLVR.Tools.WheelOpen() exposes its state; a final mover consumes attack/reload while open
even when W already owns the armed trigger. Plain debug exposes both tools and the wheel.
No console attacks, approval-returning physgun hooks, files/settings or autorun changes.
The framework owns hooks/events/handlers/movers. Stop clears convergence, destroys canvases
and removes Tools/debug; safe after partial Start/repeat. No process exit code; errors use
the framework's cleanup. Offline: companion/tests/vr_tools_test.py.
Beam debug retains the native frame sequence. The independent probe observes actual
DrawBeam arguments, queries the model attachment separately, and checks pose-matched raw
colour/depth captures rather than comparing two W/debug coordinates.
Stick accumulation uses elapsed game time (capped at 100 ms) between commands, rather than
assuming one render frame per server tick. Mouse deltas are consumed after L has read them,
preventing the native Use rotation path from competing with the authoritative hand angle.

On ladders, neutral main-stick distance input does not add Use, so off-stick climbing cannot push a held prop. Real push/pull still adds Use+Forward/Back after movement-sector buttons.
