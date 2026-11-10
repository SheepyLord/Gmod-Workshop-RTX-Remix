# hotloader_props_render_harness.lua

Loads the Model Hotloader's shipped `props/render.lua` (the path in `arg[1]`) under LuaJIT with the
engine instrumented, prepares a three-material static prop through the file's own Think hooks
(materials, then one mesh per part), and draws it. Fails if anything creates a client entity or
registers an entity class for the pieces, or calls `DrawModel` (the `GetRenderMesh` path that crashed
queued rendering, `studiorender.dll+0x6603b`), if a mesh is drawn outside a pushed model matrix, with
the caller's colour modulation still set, after it was destroyed, or destroyed twice. Checks the model
matrix against the old proxy's placement (rotation, uniform scale, the native render origin), the
flashlight pass, the colour materials (`$color2`, `$alpha`, the translucent flag, reuse, eight colours
per prop with the least recently used taking a ninth), that released meshes are destroyed only after
`P.RetireFrames` frames, and also after the frame counter goes back. Prints
`PASS: static props draw their meshes directly`; exit 1 with `FAIL: <reason>` on stderr otherwise.
No game or user files are accessed. Run through [test_hotloader_props_render.py](test_hotloader_props_render.py.md).
