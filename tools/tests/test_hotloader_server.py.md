# test_hotloader_server.py

Runs [hotloader_server_harness.lua](hotloader_server_harness.lua.md) under LuaJIT, once per scenario, without
starting Garry's Mod (R19, the pre-release review). It loads Model Hotloader's shipped
`packages/model-hotloader/mmd_hotloader/lua/mmdhl/server.lua`, `props/server.lua` and `scene_sharing.lua`
whole, and two slices of production code it cuts out of files the harness cannot load whole (written to a
scratch file under `out\tmp`): `mmdhl.CanEdit` and `mmdhl.OwnsEntity` from `sharing.lua` (its server part
reads the cache when it loads) and the collision mesh receiver from `carrier.lua` (it uses Garry's Mod's
`continue`).

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_server.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_only_the_owner_or_an_admin_removes_or_replaces_a_character` | L-02: removing and replacing are asked as the `remover` property and need the owner (prop protection's CPPI owner, else the creator) or an admin; other edits stay with `CanProperty` |
| `test_a_prop_attaches_only_to_a_target_within_reach` | L-07: an attachment to a target farther than 4096 units is refused with `props.attach.aim_target`; one within reach goes on |
| `test_collision_meshes_keep_the_clients_pace` | L-08: one mesh per entity every 1.5 s and four a second per player; players do not hold each other up |
| `test_one_replacement_at_a_time_under_the_gamemodes_rules` | Review finding 3 (2026-11-16): two replaces of one character in one tick make one spawn; the original goes when its replacement arrives; a replacement whose original went meanwhile goes too; a gamemode refusing the ragdoll stops it |
| `test_resets_are_paced_and_only_the_requester_is_told` | Finding 20: one reset a second per player; `physics_reset.lua`'s server side sends every client the reset and only the requester the notice, and resets one character at most once a second |
| `test_the_legacy_dupe_factory_takes_only_look_and_place` | Finding 12: a pasted `mmdhl_ragdoll` is handed to the asynchronous `mmdhl.Spawn` with its look and place only (no excluded materials, height, animation reference or physics overrides; size and mass on their grids), and not at all when the gamemode refuses the ragdoll |
| `test_spawn_sizes_share_carriers_and_player_models_wait` | Finding 4: sizes on a 0.05 grid and masses in whole kilograms (NaN and infinity dropped); a player model takes no mass from the client, waits ten seconds between carriers on a server and is refused before any carrier when `MMDHLCanSetPlayerModel` says no |
| `test_a_piece_placed_where_it_was_is_at_its_model` | Finding 21: the Mesh Separator's in-place placement 1000 units from its model is refused; at its model it goes on |
| `test_saved_rigs_are_bounded_and_previews_never_saved` | Finding 4: of 20 player rigs of one model the newest 16 stay in `approved.json` (with the arms rigs they name; old previews go) and the newest 4 are registered at the map's start; arms previews stay out of `approved.json`, 64 kept this session (sliced from `sharing.lua`) |
| `test_remote_shapes_the_module_dropped_are_asked_for_again` | MH-05: a shape `PublishRemoteScene` says it dropped is requested again when a frame names it; one the module refused waits ten seconds |

LuaJIT is optional: without it (CI) the tests are skipped. Writes only its scratch file. Exit code 0 on success.
