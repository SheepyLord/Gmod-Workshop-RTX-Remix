# client.lua

The overlay-copy acknowledgement is latched. After it succeeds, an unchanged wrist makes no
native Info call. Before it succeeds, both Info results are read; changed errors are logged
and thirty consecutive failures end VR. A failed camera push is attempted at most once per
engine frame, so additional CalcView queries cannot consume that allowance.

The second review defers a failed camera push for up to thirty consecutive frames, keeps the
last accepted camera, and logs a changed camera error once. A busy reply is not a one-frame
session failure. The wrist is repainted until Info.overlayUpdates acknowledges a runtime copy,
including when the game does not queue rendering.

Review follow-up: nil and nil/error retain the exact last pushed camera. Changed frame errors
are logged and thirty consecutive failures stop with their reason. Failed overlay mutations at
Start are errors. Recenter relatches yaw and standing XY on a fresh sequence, preserving height
and avoiding duplicate camera pushes. No controller locomotion/turning is added in V1.

VR-Q integration installs the session when Info.sdk_ready is true, while the first traced frame
is still pending. BeginFrame can then produce the first camera. A completion timeout holds the
last valid camera without pushing it again; a native error is reported through session cleanup.
The tested Index culling-FOV fallback is 145 degrees at 16:9.
Native mutators' nil/false plus error returns are handled, including a rejected camera push;
they are not assumed to raise Lua errors.

Client session implementation. `include("nlvr/client.lua")` returns `{Start(api, onError, worldUnitsPerMetre),
Stop()}`. The companion includes it after Info.sdk_ready, supplying the renderer's first camera. Stop is idempotent and handles
partial startup, frame errors, normal Exit, module quit and shutdown through the companion's lifecycle.

The add-on changes **no engine convar**. `fps_max` is Lua-blocked; engine convars cannot be written with
ConVar:SetString. `cl_drawhud` is unnecessary: the compositor samples the traced centre before desktop 2D. Ordinary
PreDrawViewModel/PreDrawPlayerHands hooks return true; ShouldDrawLocalPlayer returns false. Body/weapon render
proxies and their render children are hidden with SetNoDraw. The roots' Think methods are temporarily paused:
the weapon proxy otherwise draws the active weapon and re-shows its child even when the root is hidden. Stop
restores each original raw Lua Think field (including nil) and surviving entity's old NoDraw flag. Their convars
remain alone, avoiding callbacks that change Remix shadow settings. Hook.Call, hook.Run,
hook.Add and vgui.Create are never replaced. HUDPaint, default HUD, notices, menus and console keep their desktop path.

CalcView must have one authority while VR runs. The session temporarily owns only `hook.GetTable().CalcView`:
the engine-visible table dispatches just the VR callback. The previous table is held; late Add/Remove operations
are diverted to it through the temporary table's metatable. Stop restores its identity and those edits. No global
dispatch function or gamemode function is replaced. A later wholesale hook-library/table replacement is detected
in PreRender and ends the session rather than silently using a competing camera. The ownership assumes GMod's
standard table-based hook dispatcher (also used by the package's guard).

BeginFrame is called once per engine FrameNumber, at the first CalcView or PreRender. Real GMod asks CalcView
before PreRender; deferring the sample to PreRender alone made the pose one engine frame old. PreRender shares
the sample and still maintains proxy hiding. The first valid head pose and camera angles fix play-space yaw.
CalcView anchors tracking at **its supplied origin minus GetCurrentViewOffset()**, using
the engine's predicted/interpolated position and actual standing/duck transition. It never anchors at GetPos.
LocalToWorld transforms the module's Source-axis pose at the world scale latched by the companion at Start.
The first CalcView for each sequence is cached and pushed with SetFrameCamera exactly once; repeated requests
return that same view. Lost tracking holds the last valid head; absent frames are not pushed. FOV remains
adjustable (default 140 pending S6), with near/far planes preserved.

The wrist canvas is the single named literal `nlvr_wrist_v1_769x257`: RGBA8, no depth, no special flags, 790532
colour bytes. OverlayCreate/Source/Attach/Show place it 0.23 m wide on the left controller, Source-axis local
offset `(0,0,0.065)` m and angle `(0,0,90)`. First draw and health/armour/clip/reserve changes repaint through
ordinary raster text in PostRender. Camera/target scopes unwind on paint errors. The target's real dimensions
are checked so a guard fallback fails cleanly. Source caches that one target/fonts until process exit; Stop
unbinds/destroys the SteamVR overlay. There is no work against it while off.

Seven session hooks are removed on Stop; CalcView's prior table is restored. No timer, console command or file
write belongs to this add-on. Only the companion owns the session timer and shutdown hook. Initialization errors
raise to the page and later frame/paint errors call onError.

Offline: [test_vr.py](../../../../companion/tests/test_vr.py.md), whose engine-variable stand-ins reject SetString.
The [handover report](../../../../docs/handover/VR-V1-E-report.md) records client API probes and the real-game
stand-in run, including cleanup, camera samples and PNG evidence. VR-Q still checks submitted eyes/overlay pixels.
