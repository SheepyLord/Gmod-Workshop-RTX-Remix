# cl_move_overlay.lua

Included by `cl_move.lua` during an active session. `New(ctx)` returns `Arc(arc, landing)` and
`Comfort(strength, fade)`. Creates canvases lazily through the framework overlay manager:
eight world-attached arc dots, a horizontal landing ring, and a head-locked comfort canvas.
All VR UI travels through SteamVR overlays; nothing is drawn into the world's perspective pass.
Reserved arc/target/vignette dimensions remain unchanged; additional dots use unique odd sizes.
Green means a locally valid standing destination, red means rejected. The server checks again.
Comfort combines a feathered black border and full black blink/collision fade, even with
the optional vignette disabled. Overlay resources belong to the module and die at Exit.
No file access or settings changes. Returns its service; native/paint errors propagate to
the framework's failure handling.


Review correction: three arc dots plus target, all with unique central reserved sizes. Comfort sort order persists through lazy native handle recreation.
