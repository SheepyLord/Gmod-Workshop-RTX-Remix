# native_render.lua

Client native-model rendering, material readiness and registration, preview materials, source
shadows, visual proxies and presentation/LOD updates. Native renderer initialization precedes the
cached shader-backend query. Fixed-function Remix reuses public color names in unused depth slots
and skips Source shadow/SSAO depth-view draws; it never creates the unavailable DepthWrite shader.
Programmable Source retains the original depth material, alpha cutout, cull and texture rules.
Cache version 11 refreshes existing material mappings. Model assets, carrier identities and saved
data are unchanged. Existing archived render convars remain. MIT, same license as Model Hotloader.

`mmdhl.NativeIdle()` (ADR 0273, this repository's change) tells the render boundary in `client.lua`
whether the frame has nothing for the natives: no model in `mmdhl.Entities()`, no client instance
(`mmdhl.HasClientInstances`), no editor or library preview, no legacy `mmdhl_ragdoll`
(`mmdhl.HasLegacyRagdolls`) and no reader of the frame profile, for two seconds. The presentation,
the natives' frame step and their render-cache sweep are then left out; the update-rate LOD's
frame-time average keeps running, so a character spawned later starts from the same value.
