# test_hotloader_idle_frames.py

Runs [hotloader_idle_frames_harness.lua](hotloader_idle_frames_harness.lua.md) under LuaJIT, once per scenario,
without starting Garry's Mod ([ADR 0273](../../docs/decisions/0273-the-hotloaders-frames-cost-nothing-without-a-character.md)).
The harness loads the Model Hotloader's shipped `client.lua` and `carrier.lua` (which includes `native_render.lua`)
from `packages/model-hotloader/mmd_hotloader/lua/mmdhl`, as the client loads them, and runs frames of the hooks that
run on every map: `Think` (`MMDHL.NativeVisuals`, `MMDHL.RenderMode`), `PreRender` (`MMDHL.Shadows`) and the opaque
and translucent draw hooks (`MMDHL.PendingVisuals`, `MMDHL.Models`).

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_idle_frames.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_a_map_without_character_models_costs_no_scans` | On a map of 600 props, 40 ragdolls and 20 NPCs with no character model, a frame reads at most two entities' networked asset (the safety net's turn), searches the map for legacy entities never, and calls neither the natives' frame step nor their render-cache sweep; the entity list stays empty |
| `test_the_counts_of_a_frame` | The counts the harness prints: 2 asset reads a frame with no character model, 5 with three (each character and the turn), no legacy search either way |
| `test_a_new_character_model_is_listed_at_once` | A ragdoll made with its model in the same tick is listed at once and stays listed; the natives prepare each frame from then on; a model arriving frames after its entity, with no change hook, is listed in the next frame |
| `test_a_model_announced_for_an_entity_in_view` | A player given a model long after joining (the change hook runs, before the value as in the game) is listed in the next frame; so is a prop whose asset was read this frame before the change arrived; a model taken away leaves the list in the next frame |
| `test_an_unannounced_model_is_found_in_turn` | A model given without any hook (another add-on's handler answered first) is found by the turn, within 600 frames for 661 candidates (prints the frames) |
| `test_an_entity_back_in_view` | An NPC that got a model out of view is listed in the frame after the game says it is back in view |
| `test_a_removed_character_model_leaves_the_list` | A removed character model leaves the list at once |
| `test_the_list_keeps_its_order` | Character models are listed by entity index; client ragdolls and other add-ons' copies follow, each once |
| `test_a_noted_preview_is_listed` | A client-side preview the add-on notes is listed at once |
| `test_a_full_update` | After a full update (every entity removed and made again as new objects without `OnEntityCreated`), a character model is listed in the next frame |
| `test_legacy_entities_are_looked_for_only_while_one_exists` | No legacy `mmdhl_ragdoll`: none reported; one made: reported, and the frame looks for them three times as before; removed: no longer reported; one made before the add-on's hooks is found by the full scan |
| `test_the_natives_rest_only_when_nothing_needs_them` | An empty map is idle from the first frame; a character model ends it at once; after the last one goes, the natives keep working two seconds (their caches are swept) and then rest; a held instance, an editor preview, the library preview, a reader of the frame profile and a legacy entity each keep them working |
| `test_the_server_searches_for_server_side_worlds_only_once_one_exists` | The server's `MMDHL.NativePose` tick (`carrier.lua`, server realm) on a map of 200 props and 20 ragdolls: ten seconds of ticks search the map at most three times (one search every five seconds) while no ragdoll has a server-side world (`MMDHLInstance`); one given a world with the change hook has its morphs sent in the next tick, every tick searches from then on, a changed weight is sent in the next tick and an unchanged one is not sent again |
| `test_an_unannounced_server_side_world_is_found` | The same with a world given without the change hook: found by the search every five seconds |

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
