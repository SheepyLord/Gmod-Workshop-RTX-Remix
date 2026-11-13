# cl_overlay.lua: Owned overlay manager

New(core) creates NLVR.Overlay. Sizes reserves every planned panel, laser, teleport, comfort, ghost, gloves and ammo canvas, wrist 769x257 unchanged. Overlay.New{key,name,width,height,paint,device,pos,ang,metres,alpha} returns Show(bool), Place(device,pos,ang,metres), Alpha(a), Invalidate(), Destroy(). Reserved dimensions require their named key; all dimensions are odd integers <=4095, exact pairs unique while live. Native Source/Attach failure raises and partial objects remain owned for cleanup. paint(object,width,height) runs only after invalidation, within balanced target/2D scopes at PostRender. before_overlay_paint allows value-driven invalidation. A paint error uses V1 session failure/cleanup. Hit(object,worldOrigin,worldDirection) returns normalized u,v and world game-unit distance; respects visibility, tracking, front face and finite panel bounds. Placement is Source-basis tracking metres relative to left/right/head or standing world; the OpenVR front is Source -Forward, right is Angle:Right(), up is Up(). Destroy unbinds the native overlay; Source retains its named RT allocation until game exit, as in V1. No file writes.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

New optionally accepts clear={r,g,b,a}; default is transparent black. The manager clears directly before entering 2D, preserving literal RGBA instead of blending the clear colour through a rectangle.

V4 central reservations: wheel 1035x1037, tool 643x133, settings 1283x963, flat_close 131x133 and keyboard 1039x391. UI reads its two sizes from this table; all 19 reserved pairs are unique and odd, covered by the existing allocation checks.


Review correction: New creates a logical canvas only. Show allocates lazily; hidden handles retire after 2 seconds, with least recently hidden eviction at 32. All-visible pressure logs once and leaves the object hidden without a module error. Source/window/remove requests share a 16-distinct-handle frame budget. SortOrder and Window persist across handle recreation. Three reserved arc dots plus target bring the simultaneous reserved-role count to 21. No runtime cap changes.


Q3 repaint correction: native binding invalidates a static logical canvas immediately and once in the following frame, so the runtime sees paint after source registration even with a deferred render thread. Same-frame duplicate Paint calls remain avoided. Recreated handles also repaint.


Window(enable) returns nil/pending before native acceptance. WindowState reports pending/ready/refused; permanent refusal does not retry every frame, and IsVisible checks the actual native state when available. The UI can switch to a normal canvas fallback without pausing for an invisible source.
