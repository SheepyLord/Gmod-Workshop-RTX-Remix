# 0152: Hotloader imports: detailed collision serves one import, every slow stage shows a percentage, static props draw their own meshes

- Status: Accepted 2026-11-10
- Context: the user's report of 2026-11-10, importing `花.pmx` (a static flower, 1,584 triangles) with the Model
  Hotloader of the RTX package: building the physics took a long time at what the user knew as the default settings,
  the importer showed no percentage for it, and every new import crashed the game once the importer showed it ("Garry's
  Mod closed unexpectedly", 0xC0000005). Evidence: the user's crash folder
  (`native-loader/logs/sessions/2026-11-10T212505.066Z-36508-crash`, a Remix minidump), the field install's import
  registry and `client.vdf` (read only), and offline imports with the shipped worker
  ([handover](../handover/hotloader-import-report.md), RESEARCH "Model Hotloader imports").

## What was found

1. **The slow physics is detailed collision, a remembered choice.** A static prop's collision is a single hull
   (`mmdhl_prop_import_collision hull`, the default since the option exists, 2.1.0) or detailed (`balanced`: CoACD's
   decomposition into up to 16 hulls). The flower imports in 0.08 s with the single hull and in 26-54 s with detailed
   collision (this machine; CoACD remeshes the non-manifold flower into 31,568 triangles, decomposes it in 20 passes into
   246 pieces, then merges them into 16 for another 24-27 s). The choice is an archived convar: the user's game had
   `balanced` saved, so every static import ran CoACD, and the field registry holds the flower imported both ways.
   Character imports spend no comparable time on physics ("Fitting native collision anatomy": 11 ms for the flower,
   64 ms for a 39,147-triangle character).
2. **No percentage:** the static importer reported the CoACD stage once, at 65 % of its bar, with "this stage has no
   percentage estimate", until it ended; character imports reported "Preparing Source materials" once (0.9 s of 3.3 s
   for a 24-material character) at a fixed 91 %.
3. **The crash** is GMod's `ENT:GetRenderMesh` path under queued rendering (`mat_queue_mode 2`, the user's): the
   material system's render thread faulted in studiorender's loop over a model's render meshes (`studiorender.dll
   +0x141b9` calling the matrix concatenation at `+0x66030`, read at `+0x6603b`), the fault R4 found with the glass
   shards (RESEARCH, R4 field facts) and issue 2's diagnosis found three times. The Hotloader drew every static prop
   through hidden client entities whose `GetRenderMesh` returned the prop's Lua mesh, drawn with `DrawModel`, and the
   importer selects and previews each new import at once, so every new static import crashed there.

## Decision

1. **Detailed collision serves one import.** An import that starts with `balanced` sets the choice back to the single
   hull (`P.ImportStarted`); listing a `.blend`'s objects does not use it up, the import of the chosen objects does. A
   reimport keeps detailed collision for a prop that has it (more than one hull; the single hull is always one), and the
   player's choice still applies to it. A `balanced` remembered from before goes back to `hull` once
   (`mmdhl_prop_import_collision_version` 1). The importer's combo boxes follow their setting, so the choice shows the
   single hull again after the import; its label and tooltip say "next import only" in all seven languages. So an
   ordinary import, and a static prop above all, never runs CoACD unless the player asked for it for that import.
   Rejected: keeping the remembered choice and only resetting it once (one later pick would make every import slow
   again, which is how the user got here); a faster CoACD for detailed collision (changes what the option builds, and
   the threshold that would make it fast is a quality choice this report did not ask for; noted in the handover).
2. **Every slow stage shows a percentage.** CoACD 1.0.14 has no progress callback; at log level `info` it writes each
   decomposition pass to standard output. The worker makes standard output a pipe before the DLL loads and reads it
   while CoACD runs (`props/collision.cpp`, `CoacdProgress`): a piece finished in pass N is 2^-N of the mesh, so the
   finished shares add up to exactly 1 at the end, and with the passes done they give the passes' share; the merge to
   16 hulls logs nothing until it ends and is estimated from the square of the number of pieces it merges, approaching
   its end without reaching it. The import's bar gives detailed collision 10-95 % (it is nearly all of such an
   import), and a character's Source materials report per material over 71-93 % (its textures 10-70 %). The importer
   already shows the job's percentage beside its stage; nothing changed in that display.
3. **Static props draw their own meshes.** `props/render.lua` keeps no proxy entity: `P.DrawAsset` pushes the prop's
   model matrix (rotation, uniform scale, the native render origin, as the proxy was placed) and draws each piece's
   mesh with `render.SetMaterial` and `IMesh:Draw`, in the colour pass and in `render.RenderFlashlights`, as R4's glass
   shards do. A prop with a colour (the colour tool, the placement ghost) gets materials of that colour (eight colours
   a prop, the least recently used one recoloured), because DrawModel modulated the material on the render thread and
   a mesh draw cannot: a shared material changed for one draw would reach the render thread after the next draw
   changed it again. Released meshes are destroyed eight frames later, as the glass add-on does.

## Consequences

- An ordinary static import of the flower takes 0.08 s again; detailed collision is still there, for one import at a
  time, now with a percentage (an estimate during CoACD's merge, which may end with a jump from about 80 %).
- The user's game keeps nothing slow by default after this update: its saved `balanced` goes back to `hull` once.
- No importer preview, placed prop or tool ghost goes through `GetRenderMesh` any more. Under RTX Remix the meshes are
  path traced as before (the runtime never used the raster lighting); in raster the colour pass keeps its ambient
  cube and flashlights.
- The worker, runtime and module natives are rebuilt from the source copy with the add-on's hash records regenerated
  (ADR 0107); the Linux build is unchanged (no pipe there: its CoACD stage keeps the old message).
- Not changed here: the fixes part's Seamless Portals add-on still draws through `GetRenderMesh` and `DrawModel`
  (`seamless_portal/cl_init.lua`), the same path; it is left for its own change.
