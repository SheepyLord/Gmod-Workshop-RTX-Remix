# 0273: The Model Hotloader's frames cost nothing without a character

- Status: Accepted 2026-11-27 (the user's "Merge and publish", after the PoC measurements, the behaviour check and
  the Release gate). Proposed the same day on the branch `hotloader-idle`, for the main session's task: Codex found
  that "idle character processing can free CPU time: with zero imported characters present, the Model Hotloader's
  pre-render callback still used 0.46 ms per frame" (relayed by the user). Measured again in the PoC before anything
  changed.
- Package only: the Model Hotloader's Lua (`mmd_hotloader/lua/mmdhl/carrier.lua`, `client.lua`, `native_render.lua`,
  `instances.lua`). No loader (`winmm.dll`), runtime or natives change.
- Facts: [RESEARCH.md](../RESEARCH.md), "The Model Hotloader's frame with no character"; report:
  [hotloader-idle-report.md](../handover/hotloader-idle-report.md).

## Context

Every frame, on every map, the Hotloader's client looked for character models whether any existed or not:

- **The entity list was built from every candidate in every frame.** `mmdhl.Entities()` keeps the entities that can
  carry a model (props, ragdolls, NPCs, players, by class, kept incrementally since load-speedup round 2) and checks
  each one for the networked asset that makes it a character (`mmdhl.IsMMD`: the class, three fields of the entity's
  Lua table and `GetNW2String('MMDHLAsset')`, each a call into the engine). The render boundary (`PreRender`
  `MMDHL.Shadows`, through `UpdateClientInstances`) throws the frame's list away and builds it again, so that an
  entity that arrived after the last list is drawn in that frame, and the frame's other calls (about ten) reuse it:
  every candidate was checked once a frame, inside the pre-render callback. The cost grew with the map's props and
  NPCs, not with its characters: none on the map, and a map with 600 props still paid 600 checks a frame.
- **Legacy entities were searched for three times a frame.** `ents.FindByClass('mmdhl_ragdoll')`, a walk over every
  entity of the map, ran in `Think` (`MMDHL.RenderMode`), at the render boundary and in the translucent pass
  (`MMDHL.Models`), for the old `mmdhl_ragdoll` entity that only the legacy backend (`mmdhl_native_carrier 0`) makes.
- **The natives prepared a frame for nobody.** `native.PrepareFrame` and `native.PruneRenderCache` each queued a call
  for Source's render thread every frame (the frame's draw counters published as JSON there, an empty cache sweep),
  with no instance to step or buffer to release.
- **The server searched every tick for a world nothing makes.** `MMDHL.NativePose` (`carrier.lua`, server) walked
  `ents.FindByClass('prop_ragdoll')` each tick to send the morphs of ragdolls holding a server-side world
  (`MMDHLInstance`); no code of the add-on sets that value since the presentation's world became the client's, so the
  search found nothing to do, at a cost that grew with the map's entities. In single player the server's tick runs in
  the same process as the frame.

In the PoC (the report has the runs) the render boundary's list was one full pass over the candidates a frame: on
gm_construct as it is, `MMDHL.Shadows` took 0.035 ms; with 600 more props, 0.26 to 0.29 ms, of which the list was
0.23 ms and the searches the rest; each `ents.FindByClass` took about 60 ns per entity of the map (13 µs on
gm_construct). Codex's 0.46 ms is that cost on a map with more entities.

## Decision

1. **The client's entity list follows what can change it** (`carrier.lua`). The entities known to carry a model are
   checked at every list, as before, so one that loses its model leaves the list as before. Any other candidate is
   checked when something may have given it one, at every list for a short while: its creation (two seconds: its
   networked values can arrive frames later), its return into view (`NotifyShouldTransmit`, two seconds), a networked
   asset arriving for it (`EntityNetworkedVarChanged` for `MMDHLAsset`, half a second: the hook runs before the value
   changes, and the value may have been read for the frame already) and the add-on noting it (`mmdhl.NoteCarrier`).
   As a safety net for whatever these miss (another add-on's handler answering the hook first, a path of the game
   that does not run it), the other candidates are checked in turn, at least one a frame and each within about ten
   seconds at sixty frames a second. The full scan every five seconds, the order of the list and the client ragdoll
   and player copy registries are as before. The server's list is unchanged.
2. **Legacy entities are looked for only while one exists** (`client.lua`, `carrier.lua` `mmdhl.HasLegacyRagdolls`):
   the candidates' creation and the full scan note every `mmdhl_ragdoll`; while one exists, the three searches run as
   before.
3. **The natives rest while nothing needs them** (`native_render.lua` `mmdhl.NativeIdle`, `client.lua`): with no model
   in the list, no instance held (`instances.lua` `mmdhl.HasClientInstances`), no editor or library preview, no legacy
   entity and no reader of the frame profile for two seconds, the render boundary leaves out the presentation, the
   frame step, the bounds and the cache sweep. The two seconds let the sweep release what the last character used.
   The update-rate LOD's frame-time average keeps running, so a character spawned later starts from the value it
   would have had.
4. **The server's tick searches only once a server-side world exists** (`carrier.lua`, server): until some ragdoll's
   `MMDHLInstance` is set (the change hook runs on the server for the server's own values; one search every five
   seconds finds one set any other way), `MMDHL.NativePose` returns at once; from then on it searches every tick as
   before.
5. **Nothing changes for a character.** With one, every frame does what it did: the same list (each character
   checked, in the same order), the same presentation, natives, shadows and draws.

## Consequences

- With no character, the Hotloader's frame no longer depends on the map: in the harness, a map of 661 candidates cost
  661 asset reads, three searches of the map and two queued native calls a frame, and costs two reads and nothing
  else. In the PoC, measured A B A B inside one launch: `MMDHL.Shadows` 0.264 and 0.292 ms before, 0.019 and 0.018
  ms after on gm_construct with 600 props (0.035 to 0.014 ms as it is); all of the Hotloader's client hooks 0.33 and
  0.37 ms before, 0.059 and 0.053 ms after, what remains about a microsecond a hook; the server's `MMDHL.NativePose`
  0.041 ms a tick before, 0.002 ms after. Frame medians move by more than this between phases (±0.2 ms at 6 ms a
  frame). The branch's package deployed measured as its files loaded over the shipped ones did.
- With characters, the list costs what the characters and the turn cost, not what the map's props cost: with three on
  the busy map, `MMDHL.Shadows` 1.75 and 1.79 ms before, 1.42 and 1.42 ms after; the characters' own presentation
  (0.45 ms) and native work are the same.
- A model given to an entity already in view, with no hook announcing it, is found within one turn (about ten seconds
  on a map of 600 candidates) instead of the next frame. The game runs `EntityNetworkedVarChanged` for networked
  changes, so this is the safety net's case, not the usual one.
- Tests: [`test_hotloader_idle_frames.py`](../../tools/tests/test_hotloader_idle_frames.py.md) loads the three
  files whole under LuaJIT and runs frames: no scan without a character, a new character listed at once, an announced
  and an unannounced model, an entity back in view, removal, order, previews, a full update, legacy entities, the
  natives' rest and grace.
